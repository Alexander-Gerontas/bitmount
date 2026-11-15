import AppKit
import Foundation
import BitMountCore
import Observation

enum Notice: Equatable {
    case canceled
    case adminRejected
    case wrongSecret
    case timedOut
    case engineMissing
    case mountFailed(String)
    case ejectFailed(String)
    case keychainFailed
    case rootfsMissing
}

@MainActor
@Observable
final class AppModel {
    var disks: [ExternalDisk] = []
    var mounts: [String: ParsedMount] = [:]
    var savedItems: [KeychainItem] = []
    var engine: EngineStatus = .missing
    var selectedVolumeID: String?
    var busyVolumeID: String?
    var notice: (volumeID: String, kind: Notice)?
    var hasLoaded = false
    var unlockSheetVolumeID: String?
    var sessionReadOnly: [String: Bool] = [:]
    /// Anything BitMount installed as root is still on this Mac.
    var helperInstalled = PrivilegedMount.isInstalled
    /// The installed helper is current, so mounting does not ask for the Mac password.
    var helperApproved = PrivilegedMount.ownHelperIsCurrent
    var isRemovingHelper = false
    var helperRemovalFailed = false
    /// Stable IDs of the volumes that unlock on their own when connected.
    var autoMountIDs = Set(UserDefaults.standard.stringArray(forKey: AppModel.autoMountKey) ?? [])

    private static let autoMountKey = "autoMountVolumes"
    private var monitoring: Task<Void, Never>?
    private var arrivals = AutoMountQueue()

    var selectedVolume: WindowsVolume? {
        disks.flatMap(\.volumes).first { $0.id == selectedVolumeID }
    }

    func savedKind(for volume: WindowsVolume) -> SecretKind? {
        savedItems.first { $0.account == volume.stableID }?.kind
    }

    func startMonitoring() {
        guard monitoring == nil else { return }
        monitoring = Task { @MainActor in
            while !Task.isCancelled {
                if busyVolumeID == nil {
                    await refresh()
                    await unlockArrivals()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func setAutoMount(_ enabled: Bool, for volume: WindowsVolume) {
        if enabled {
            autoMountIDs.insert(volume.stableID)
        } else {
            autoMountIDs.remove(volume.stableID)
        }
        UserDefaults.standard.set(autoMountIDs.sorted(), forKey: Self.autoMountKey)
    }

    /// Unlocks the volumes that were just connected, have the option on and have a saved password.
    private func unlockArrivals() async {
        let enabled = autoMountIDs
        for stableID in arrivals.drain(where: { enabled.contains($0) }) {
            guard busyVolumeID == nil,
                  let volume = disks.flatMap(\.volumes).first(where: { $0.stableID == stableID }),
                  mounts[volume.id] == nil,
                  savedKind(for: volume) != nil
            else { continue }
            await unlock(volume: volume, secret: nil, remember: false, readOnly: false)
        }
    }

    func refresh() async {
        let snapshot = await DiskScanner.scan()
        engine = snapshot.engine
        mounts = snapshot.mounts
        savedItems = KeychainStore.items()
        syncHelperState()
        if let found = snapshot.disks {
            disks = found
            arrivals.record(connected: Set(disks.flatMap(\.volumes).map(\.stableID)))
            let visible = disks.flatMap(\.volumes).map(\.id)
            if selectedVolumeID == nil || !visible.contains(selectedVolumeID ?? "") {
                selectedVolumeID = visible.first
            }
        }
        hasLoaded = true
    }

    func unlock(volume: WindowsVolume, secret: SavedSecret?, remember: Bool, readOnly: Bool) async {
        guard busyVolumeID == nil else { return }
        guard engine.path != nil else {
            notice = (volume.id, .engineMissing)
            return
        }
        guard engine.rootfsReady else {
            notice = (volume.id, .rootfsMissing)
            return
        }

        let resolved: SavedSecret?
        if let secret {
            resolved = secret
        } else {
            resolved = KeychainStore.load(account: volume.stableID)
        }
        guard let resolved, !resolved.passphrase.isEmpty else {
            unlockSheetVolumeID = volume.id
            return
        }

        busyVolumeID = volume.id
        notice = nil
        let result = await MountService.mount(
            volume: volume,
            passphrase: resolved.passphrase,
            readOnly: readOnly,
            enginePath: engine.path ?? ""
        )
        await finishMount(volume: volume, secret: resolved, typed: secret != nil, remember: remember, readOnly: readOnly, result: result)
    }

    func mountWithoutPassword(volume: WindowsVolume, readOnly: Bool) async {
        guard busyVolumeID == nil, let enginePath = engine.path else {
            notice = (volume.id, .engineMissing)
            return
        }
        guard engine.rootfsReady else {
            notice = (volume.id, .rootfsMissing)
            return
        }
        busyVolumeID = volume.id
        notice = nil
        let result = await MountService.mount(
            volume: volume,
            passphrase: nil,
            readOnly: readOnly,
            enginePath: enginePath
        )
        await finishMount(volume: volume, secret: nil, typed: false, remember: false, readOnly: readOnly, result: result)
    }

    func eject(volume: WindowsVolume) async {
        guard busyVolumeID == nil, let enginePath = engine.path else { return }
        busyVolumeID = volume.id
        let result = await MountService.unmount(deviceID: volume.id, enginePath: enginePath)
        busyVolumeID = nil
        if result.status == 0 {
            mounts[volume.id] = nil
            sessionReadOnly[volume.id] = nil
            notice = nil
            await refresh()
        } else {
            let detail = FailureClassifier.scrub(result.combined, secret: "").trimmingCharacters(in: .whitespacesAndNewlines)
            notice = (volume.id, .ejectFailed(tail(detail)))
        }
    }

    /// Removes the root-owned mount helper. Refused while a drive is mounted, so a mounted
    /// drive is never left with only a forced stop as its way out.
    func removeHelper() async {
        guard !isRemovingHelper, busyVolumeID == nil, mounts.isEmpty else { return }
        isRemovingHelper = true
        helperRemovalFailed = false
        let result = await MountService.uninstallHelper()
        isRemovingHelper = false
        syncHelperState()
        let kind = FailureClassifier.classify(status: result.status, output: result.combined, timedOut: result.timedOut)
        helperRemovalFailed = helperInstalled && kind != .canceled
    }

    private func syncHelperState() {
        helperInstalled = PrivilegedMount.isInstalled
        helperApproved = PrivilegedMount.ownHelperIsCurrent
    }

    /// Deletes the saved password. Automatic unlocking goes with it, so saving a new
    /// password later does not switch it back on unnoticed.
    func forget(account: String) {
        KeychainStore.delete(account: account)
        savedItems.removeAll { $0.account == account }
        if autoMountIDs.remove(account) != nil {
            UserDefaults.standard.set(autoMountIDs.sorted(), forKey: Self.autoMountKey)
        }
    }

    func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func finishMount(
        volume: WindowsVolume,
        secret: SavedSecret?,
        typed: Bool,
        remember: Bool,
        readOnly: Bool,
        result: ProcessRunner.Result
    ) async {
        let kind = FailureClassifier.classify(status: result.status, output: result.combined, timedOut: result.timedOut)
        let mount = await MountService.mountPoint(deviceID: volume.id, enginePath: engine.path ?? "")
        busyVolumeID = nil
        syncHelperState()

        guard result.status == 0, let mount else {
            if kind == .wrongSecret {
                // Only a saved password that failed is deleted. A typing mistake leaves it alone.
                if !typed {
                    forget(account: volume.stableID)
                }
                unlockSheetVolumeID = volume.id
            }
            notice = (volume.id, noticeKind(kind, output: result.combined, secret: secret?.passphrase ?? ""))
            return
        }

        mounts[volume.id] = mount
        sessionReadOnly[volume.id] = readOnly
        unlockSheetVolumeID = nil
        // A password read from the Keychain stays there. A typed one is saved when
        // "Save password" is on; otherwise any older entry for this volume is removed.
        if typed, let secret {
            if remember {
                do {
                    try KeychainStore.save(account: volume.stableID, label: volume.name.isEmpty ? volume.id : volume.name, secret: secret)
                    savedItems = KeychainStore.items()
                } catch {
                    notice = (volume.id, .keychainFailed)
                }
            } else {
                forget(account: volume.stableID)
            }
        }
        if UserDefaults.standard.bool(forKey: "openFinderAfterMount") {
            open(mount.mountPoint)
        }
        await refresh()
    }

    private func noticeKind(_ kind: FailureKind, output: String, secret: String) -> Notice {
        switch kind {
        case .canceled: .canceled
        case .adminRejected: .adminRejected
        case .wrongSecret: .wrongSecret
        case .timedOut: .timedOut
        case .engineMissing: .engineMissing
        case .other:
            .mountFailed(tail(FailureClassifier.scrub(output, secret: secret)))
        }
    }

    private func tail(_ text: String) -> String {
        let lines = text.split(separator: "\n").suffix(8).joined(separator: "\n")
        let trimmed = lines.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 500 { return trimmed }
        return String(trimmed.suffix(500))
    }
}

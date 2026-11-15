import AppKit
import BitMountCore
import SwiftUI

struct VolumeDetailView: View {
    @Environment(AppModel.self) private var model
    var volume: WindowsVolume
    @State private var readOnly = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let notice = model.notice, notice.volumeID == volume.id {
                    NoticeBanner(kind: notice.kind) {
                        model.notice = nil
                    }
                }
                if model.busyVolumeID == volume.id {
                    busyCard
                } else if !model.engine.isReady {
                    engineCard
                } else if let mount = model.mounts[volume.id] {
                    mountedCard(mount)
                } else {
                    lockedCard
                }
                if model.savedKind(for: volume) != nil {
                    autoMountToggle
                }
                metadata
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: model.mounts[volume.id] == nil ? "lock.fill" : "externaldrive.fill")
                    .font(.system(size: 28, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.mounts[volume.id] == nil ? Color.orange : Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(volume.name.isEmpty ? String(localized: "Windows volume", bundle: .module) : volume.name)
                    .font(.title2.weight(.semibold))
                Text("\(Format.bytes(volume.size)) · \(Format.bus(volume.bus)) · \(volume.id)")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatusPill(title: kindTitle, color: volume.isReadableByMac ? .secondary : .orange)
                    if model.mounts[volume.id] != nil {
                        StatusPill(title: modeTitle, color: .green)
                    } else if model.savedKind(for: volume) != nil {
                        StatusPill(title: String(localized: "Saved password", bundle: .module), color: .blue)
                    }
                }
            }
            Spacer()
        }
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.savedKind(for: volume) != nil {
                Text(savedCaption)
                Button(String(localized: "Enter a different password", bundle: .module)) {
                    model.unlockSheetVolumeID = volume.id
                }
                .buttonStyle(.borderless)
            }
            Toggle(isOn: $readOnly) {
                Text("Read only", bundle: .module)
            }
            .toggleStyle(.switch)
            Text("Files stay as they are. Leave this off to copy files onto the drive.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(String(localized: "Unlock", bundle: .module)) {
                    if model.savedKind(for: volume) != nil {
                        Task { await model.unlock(volume: volume, secret: nil, remember: false, readOnly: readOnly) }
                    } else {
                        model.unlockSheetVolumeID = volume.id
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                if volume.isReadableByMac {
                    Button(String(localized: "Mount without a password", bundle: .module)) {
                        Task { await model.mountWithoutPassword(volume: volume, readOnly: readOnly) }
                    }
                }
            }
            Text(MacAuthPrompt.caption(approved: model.helperApproved))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.engine.rootfsReady {
                Text("The Linux environment is not ready. Run anylinuxfs init once in Terminal.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func mountedCard(_ mount: ParsedMount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.sessionReadOnly[volume.id] == true
                 ? String(localized: "This mount does not change files on the drive.", bundle: .module)
                 : String(localized: "You can copy files onto this drive.", bundle: .module))
            LabeledContent(String(localized: "Mount point", bundle: .module)) {
                Text(mount.mountPoint).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button(String(localized: "Open in Finder", bundle: .module)) {
                    model.open(mount.mountPoint)
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "Eject", bundle: .module)) {
                    Task { await model.eject(volume: volume) }
                }
            }
        }
    }

    private var autoMountToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { model.autoMountIDs.contains(volume.stableID) },
                set: { model.setAutoMount($0, for: volume) }
            )) {
                Text("Unlock automatically when connected", bundle: .module)
            }
            .toggleStyle(.switch)
            Text("Uses the saved password. BitMount must be running.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var busyCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 4) {
                Text("Unlocking…", bundle: .module)
                    .font(.headline)
                Text("Starting the Linux environment. This can take a few seconds.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("anylinuxfs is not installed.", bundle: .module)
                .font(.headline)
            Text("Install it with Homebrew, then open BitMount again.", bundle: .module)
                .foregroundStyle(.secondary)
            Text(EngineStatus.installCommand)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Button(String(localized: "Copy install command", bundle: .module)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(EngineStatus.installCommand, forType: .string)
            }
        }
    }

    private var metadata: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                metaRow(String(localized: "Size", bundle: .module), Format.bytes(volume.size))
                metaRow(String(localized: "Device", bundle: .module), volume.devicePath)
                metaRow(String(localized: "Connection", bundle: .module), Format.bus(volume.bus))
                metaRow(String(localized: "Partition", bundle: .module), partitionTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Details", bundle: .module)
        }
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(.primary).textSelection(.enabled)
        }
    }

    private var kindTitle: String {
        volume.isReadableByMac
            ? String(localized: "Windows", bundle: .module)
            : String(localized: "BitLocker", bundle: .module)
    }

    private var modeTitle: String {
        model.sessionReadOnly[volume.id] == true
            ? String(localized: "Read only", bundle: .module)
            : String(localized: "Read and write", bundle: .module)
    }

    private var savedCaption: String {
        if model.savedKind(for: volume) == .recovery {
            String(localized: "Using the saved recovery key.", bundle: .module)
        } else {
            String(localized: "Using the saved password.", bundle: .module)
        }
    }

    private var partitionTitle: String {
        switch volume.content {
        case "Windows Recovery": String(localized: "Windows Recovery", bundle: .module)
        case "DOS_FAT_32", "DOS_FAT_16", "DOS_FAT_12": String(localized: "FAT", bundle: .module)
        case "Windows_NTFS", "NTFS": "NTFS"
        default: volume.content
        }
    }
}

struct StatusPill: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct NoticeBanner: View {
    var kind: Notice
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch kind {
        case .canceled:
            String(localized: "The administrator prompt was canceled.", bundle: .module)
        case .adminRejected:
            String(localized: "The Mac password was not accepted.", bundle: .module)
        case .wrongSecret:
            String(localized: "Wrong password or recovery key.", bundle: .module)
        case .timedOut:
            String(localized: "Mounting is taking too long.", bundle: .module)
        case .engineMissing:
            String(localized: "anylinuxfs is not installed.", bundle: .module)
        case .mountFailed:
            String(localized: "Mount failed", bundle: .module)
        case .ejectFailed:
            String(localized: "Eject failed", bundle: .module)
        case .keychainFailed:
            String(localized: "Could not save the password to the Keychain.", bundle: .module)
        case .rootfsMissing:
            String(localized: "The Linux environment is not ready. Run anylinuxfs init once in Terminal.", bundle: .module)
        }
    }

    private var detail: String? {
        switch kind {
        case .mountFailed(let text), .ejectFailed(let text):
            text
        default:
            nil
        }
    }
}

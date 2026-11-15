import Foundation
import BitMountCore

struct EngineStatus: Equatable, Sendable {
    var path: String?
    var version: String?
    var rootfsReady: Bool

    var isReady: Bool { path != nil }

    static let installCommand = "brew tap nohajc/anylinuxfs && brew trust nohajc/anylinuxfs && brew install anylinuxfs && anylinuxfs init"

    static let missing = EngineStatus(path: nil, version: nil, rootfsReady: false)
}

struct ScanSnapshot: Sendable {
    /// Nil when the system could not list the disks, which is not the same as no disks.
    var disks: [ExternalDisk]?
    var mounts: [String: ParsedMount]
    var engine: EngineStatus
}

enum DiskScanner {
    static func scan() async -> ScanSnapshot {
        let engine = await detectEngine()
        var mounts: [String: ParsedMount] = [:]
        if let enginePath = engine.path {
            let status = await ProcessRunner.run(executable: enginePath, arguments: ["status"], timeout: 15)
            if status.status == 0 {
                for mount in StatusParser.parse(status.stdout + "\n" + status.stderr) {
                    mounts[mount.deviceID] = mount
                }
            }
        }
        let disks = MediaList.records().map(DiskInventory.disks(from:))
        return ScanSnapshot(disks: disks, mounts: mounts, engine: engine)
    }

    static func detectEngine() async -> EngineStatus {
        let path = ["/opt/homebrew/bin/anylinuxfs", "/usr/local/bin/anylinuxfs"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let path else { return .missing }
        let versionResult = await ProcessRunner.run(executable: path, arguments: ["--version"])
        let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.anylinuxfs/alpine")
        return EngineStatus(path: path, version: version.isEmpty ? "anylinuxfs" : version, rootfsReady: root)
    }
}

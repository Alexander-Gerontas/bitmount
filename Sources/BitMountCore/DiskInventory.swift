import Foundation

/// A disk or a partition, as the system describes it.
public struct MediaRecord: Equatable, Sendable {
    /// BSD name, such as `disk4` or `disk4s1`.
    public var id: String
    public var isWhole: Bool
    /// The partition scheme of a disk, or the type of a partition: a name on MBR, a GUID on GPT.
    public var content: String
    public var size: Int64
    public var uuid: String?
    public var volumeName: String
    /// macOS recognises a file system on it.
    public var isReadableByMac: Bool
    /// Where macOS has mounted it, if it has.
    public var mountPoint: String?
    public var isInternal: Bool
    public var bus: String
    public var model: String

    public init(
        id: String,
        isWhole: Bool,
        content: String,
        size: Int64,
        uuid: String? = nil,
        volumeName: String = "",
        isReadableByMac: Bool = false,
        mountPoint: String? = nil,
        isInternal: Bool = false,
        bus: String = "",
        model: String = ""
    ) {
        self.id = id
        self.isWhole = isWhole
        self.content = content
        self.size = size
        self.uuid = uuid
        self.volumeName = volumeName
        self.isReadableByMac = isReadableByMac
        self.mountPoint = mountPoint
        self.isInternal = isInternal
        self.bus = bus
        self.model = model
    }
}

public enum DiskInventory {
    /// The external disks that have a partition table, each with its Windows partitions.
    public static func disks(from records: [MediaRecord]) -> [ExternalDisk] {
        records
            .compactMap { record -> (index: Int, disk: ExternalDisk)? in
                guard record.isWhole,
                      let index = number(in: record.id, after: "disk"),
                      isPartitionScheme(record.content),
                      !record.isInternal,
                      !isIgnoredBus(record.bus)
                else { return nil }
                let disk = ExternalDisk(
                    id: record.id,
                    name: record.model,
                    size: record.size,
                    bus: record.bus,
                    volumes: volumes(of: record, in: records)
                )
                return (index, disk)
            }
            .sorted { $0.index < $1.index }
            .map(\.disk)
    }

    private static func volumes(of disk: MediaRecord, in records: [MediaRecord]) -> [WindowsVolume] {
        records
            .compactMap { record -> (index: Int, volume: WindowsVolume)? in
                guard !record.isWhole, let index = number(in: record.id, after: disk.id + "s") else { return nil }
                let content = gptTypeNames[record.content.uppercased()] ?? record.content
                guard isWindowsPartition(content) else { return nil }
                let volume = WindowsVolume(
                    id: record.id,
                    name: record.volumeName,
                    size: record.size,
                    content: content,
                    uuid: record.uuid,
                    isReadableByMac: record.isReadableByMac,
                    mountPoint: record.mountPoint,
                    parentID: disk.id,
                    parentName: disk.model,
                    bus: disk.bus
                )
                return (index, volume)
            }
            .sorted { $0.index < $1.index }
            .map(\.volume)
    }

    /// `number(in: "disk4s2", after: "disk4s")` is 2. Nil when anything but a number follows.
    private static func number(in id: String, after prefix: String) -> Int? {
        guard id.hasPrefix(prefix) else { return nil }
        let rest = id.dropFirst(prefix.count)
        guard rest.allSatisfy(\.isNumber) else { return nil }
        return Int(rest)
    }

    /// GPT partition types, under the names `isWindowsPartition` knows.
    private static let gptTypeNames = [
        "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7": "Microsoft Basic Data",
        "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC": "Windows Recovery",
    ]

    static func isPartitionScheme(_ content: String) -> Bool {
        content.contains("partition_scheme")
    }

    static func isWindowsPartition(_ content: String) -> Bool {
        switch content {
        case "Microsoft Basic Data", "Windows_NTFS", "Windows Recovery",
             "DOS_FAT_32", "DOS_FAT_16", "DOS_FAT_12", "NTFS", "ExFAT", "MS-DOS":
            true
        default:
            false
        }
    }

    /// Disk images are on the "Virtual Interface" bus.
    static func isIgnoredBus(_ bus: String) -> Bool {
        bus == "Virtual Interface" || bus.contains("Apple Fabric")
    }
}

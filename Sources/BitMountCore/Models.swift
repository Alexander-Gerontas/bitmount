import Foundation

public enum SecretKind: String, Codable, Sendable, Hashable {
    case password
    case recovery
}

public struct SavedSecret: Codable, Equatable, Sendable {
    public var kind: SecretKind
    public var secret: String

    public init(kind: SecretKind, secret: String) {
        self.kind = kind
        self.secret = secret
    }

    public var passphrase: String {
        switch kind {
        case .password:
            secret
        case .recovery:
            SecretFormat.grouped(SecretFormat.digits(from: secret))
        }
    }
}

public struct WindowsVolume: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var size: Int64
    public var content: String
    public var uuid: String?
    /// macOS recognises a file system on it, so it is a plain Windows volume.
    /// A BitLocker volume looks like unformatted space to macOS.
    public var isReadableByMac: Bool
    /// Where macOS itself has mounted it, if it has.
    public var mountPoint: String?
    public var parentID: String
    public var parentName: String
    public var bus: String

    public init(
        id: String,
        name: String,
        size: Int64,
        content: String,
        uuid: String?,
        isReadableByMac: Bool,
        mountPoint: String?,
        parentID: String,
        parentName: String,
        bus: String
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.content = content
        self.uuid = uuid
        self.isReadableByMac = isReadableByMac
        self.mountPoint = mountPoint
        self.parentID = parentID
        self.parentName = parentName
        self.bus = bus
    }

    public var devicePath: String { "/dev/\(id)" }

    /// Stable across unplug/replug. Disk numbers (`disk4`, `disk5`) are not.
    public var stableID: String {
        if let uuid, !uuid.isEmpty {
            return "gpt:\(uuid)"
        }
        return "legacy:\(size):\(content)"
    }
}

public struct ExternalDisk: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var size: Int64
    public var bus: String
    public var volumes: [WindowsVolume]

    public init(id: String, name: String, size: Int64, bus: String, volumes: [WindowsVolume]) {
        self.id = id
        self.name = name
        self.size = size
        self.bus = bus
        self.volumes = volumes
    }
}

public struct ParsedMount: Hashable, Sendable {
    public var devicePath: String
    public var mountPoint: String
    public var filesystem: String

    public init(devicePath: String, mountPoint: String, filesystem: String) {
        self.devicePath = devicePath
        self.mountPoint = mountPoint
        self.filesystem = filesystem
    }

    public var deviceID: String {
        if devicePath.hasPrefix("/dev/") {
            return String(devicePath.dropFirst(5))
        }
        return devicePath
    }
}

public enum FailureKind: Equatable, Sendable {
    case canceled
    case adminRejected
    case wrongSecret
    case timedOut
    case engineMissing
    case other
}

import BitMountCore
import DiskArbitration
import Foundation
import IOKit

/// Every disk and partition the system knows about, read from IOKit and DiskArbitration.
///
/// Neither opens a device or touches a mounted volume. `diskutil list` does, so macOS asked
/// the user to let BitMount access removable volumes and network volumes.
enum MediaList {
    /// Nil when the system could not be asked.
    static func records() -> [MediaRecord]? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var records: [MediaRecord] = []
        while case let media = IOIteratorNext(iterator), media != 0 {
            defer { IOObjectRelease(media) }
            guard let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, media),
                  let description = DADiskCopyDescription(disk) as? [String: Any],
                  let id = description[kDADiskDescriptionMediaBSDNameKey as String] as? String
            else { continue }
            let model = description[kDADiskDescriptionDeviceModelKey as String] as? String ?? ""
            records.append(MediaRecord(
                id: id,
                isWhole: description[kDADiskDescriptionMediaWholeKey as String] as? Bool ?? false,
                content: description[kDADiskDescriptionMediaContentKey as String] as? String ?? "",
                size: (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.int64Value ?? 0,
                uuid: uuidString(description[kDADiskDescriptionMediaUUIDKey as String]),
                volumeName: description[kDADiskDescriptionVolumeNameKey as String] as? String ?? "",
                isReadableByMac: description[kDADiskDescriptionVolumeKindKey as String] != nil,
                mountPoint: (description[kDADiskDescriptionVolumePathKey as String] as? URL)?.path,
                isInternal: description[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? true,
                bus: description[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? "",
                model: model.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return records
    }

    private static func uuidString(_ value: Any?) -> String? {
        guard let value else { return nil }
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == CFUUIDGetTypeID() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, (object as! CFUUID)) as String?
    }
}

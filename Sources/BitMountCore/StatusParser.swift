import Foundation

public enum StatusParser {
    public static func parse(_ text: String) -> [ParsedMount] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap(parseLine)
    }

    public static func parseLine(_ line: Substring) -> ParsedMount? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/dev/disk") else { return nil }
        guard let onRange = trimmed.range(of: " on ") else { return nil }
        let device = String(trimmed[..<onRange.lowerBound])
        let rest = trimmed[onRange.upperBound...]
        guard let paren = rest.range(of: " (") else { return nil }
        let mountPoint = String(rest[..<paren.lowerBound])
        guard !mountPoint.isEmpty, device.hasPrefix("/dev/disk") else { return nil }
        let meta = rest[paren.upperBound...]
        let filesystem = meta.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        return ParsedMount(devicePath: device, mountPoint: mountPoint, filesystem: filesystem)
    }
}

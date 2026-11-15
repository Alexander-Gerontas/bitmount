import Foundation

public enum SecretFormat {
    public static func digits(from raw: String) -> String {
        raw.filter(\.isNumber)
    }

    public static func grouped(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }
        var parts: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let end = digits.index(index, offsetBy: 6, limitedBy: digits.endIndex) ?? digits.endIndex
            parts.append(String(digits[index..<end]))
            index = end
        }
        return parts.joined(separator: "-")
    }

    public static func isCompleteRecovery(_ raw: String) -> Bool {
        digits(from: raw).count == 48
    }
}

import Foundation

public enum DevicePath {
    public static func normalize(_ identifier: String) -> String? {
        guard identifier.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return "/dev/\(identifier)"
    }
}

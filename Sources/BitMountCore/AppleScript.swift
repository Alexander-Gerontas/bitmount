import Foundation

public enum AppleScript {
    public static func privilegedCommand(argv: [String], prompt: String) -> String {
        let pieces = argv.map { "quoted form of \(literal($0))" }.joined(separator: " & \" \" & ")
        return "do shell script \(pieces) with administrator privileges with prompt \(literal(prompt))"
    }

    public static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

import Foundation

public enum FailureClassifier {
    public static func classify(status: Int32, output: String, timedOut: Bool) -> FailureKind {
        if timedOut { return .timedOut }
        let lower = output.lowercased()
        if lower.contains("user canceled")
            || lower.contains("(-128)")
            || lower.contains("no password was provided")
            || lower.contains("a password is required")
        {
            return .canceled
        }
        if lower.contains("incorrect password attempt")
            || (lower.contains("administrator") && (lower.contains("incorrect") || lower.contains("not correct")))
        {
            return .adminRejected
        }
        // anylinuxfs can print this and still exit with status 0, so do not depend on the status here.
        if lower.contains("no key available")
            || lower.contains("failed to open encrypted device")
            || lower.contains("bad passphrase")
            || lower.contains("incorrect passphrase")
        {
            return .wrongSecret
        }
        if status == 127 || lower.contains("anylinuxfs is not installed") {
            return .engineMissing
        }
        return .other
    }

    public static func scrub(_ text: String, secret: String) -> String {
        guard secret.count >= 4 else { return text }
        let dashed = SecretFormat.grouped(SecretFormat.digits(from: secret))
        var cleaned = text.replacingOccurrences(of: secret, with: "••••")
        if dashed.count >= 8 {
            cleaned = cleaned.replacingOccurrences(of: dashed, with: "••••")
        }
        return cleaned
    }
}

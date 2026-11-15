import Foundation

/// Tracks which volumes have just been connected, by stable ID.
///
/// A volume enters the queue only when it appears: at the first scan, or when it was
/// absent from the previous scan. A drive that was ejected by hand and is still plugged
/// in never re-enters, so it is not unlocked again behind the user's back.
public struct AutoMountQueue: Sendable {
    private var connected: Set<String> = []
    private var waiting: [String] = []

    public init() {}

    /// Records one successful scan.
    public mutating func record(connected current: Set<String>) {
        let arrived = current.subtracting(connected).sorted()
        connected = current
        waiting.removeAll { !current.contains($0) }
        waiting.append(contentsOf: arrived)
    }

    /// Empties the queue and returns the volumes that pass `eligible`.
    /// The rest are dropped, so turning the option on later does not unlock a drive that is already connected.
    public mutating func drain(where eligible: (String) -> Bool) -> [String] {
        defer { waiting.removeAll() }
        return waiting.filter(eligible)
    }
}

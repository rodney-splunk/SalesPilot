import Foundation

/// Accepted questions survive blank/noise segments until the input queue settles.
struct PracticeInputProgress {
    private(set) var needsReply = false
    mutating func accept(_ text: String) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { needsReply = true }
    }
    mutating func takeReply(recording: Bool, muted: Bool, queued: Bool) -> Bool {
        guard needsReply, !recording, !muted, !queued else { return false }
        needsReply = false
        return true
    }
    mutating func reset() { needsReply = false }
}

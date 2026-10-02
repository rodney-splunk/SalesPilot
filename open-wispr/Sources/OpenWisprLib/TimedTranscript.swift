import Foundation
struct TimedWord: Codable {
    let word: String
    let start: Double
    let end: Double
    var valid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
struct TimedTranscript: Decodable {
    struct Segment: Decodable { let words: [TimedWord]? }
    let text: String
    let segments: [Segment]
}

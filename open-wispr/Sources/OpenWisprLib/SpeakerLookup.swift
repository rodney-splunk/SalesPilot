import Foundation

struct SpeakerEvidence {
    var text: String
    var startedAt: Double?
    var mic: Bool
    var name: String
}
enum SpeakerLookup {
    static func key(text: String, startedAt: Double?, mic: Bool) -> String {
        guard let startedAt, startedAt > 0 else { return text }
        return "\(Int64((startedAt * 1000).rounded()))|\(mic ? "mic" : "call")|\(text)"
    }
    static func microphoneName(_ turns: [SpeakerEvidence]) -> String {
        let mic = turns.filter { $0.mic }
        let generic: Set<String> = ["You", "Unconfirmed speaker", "Uncertain speaker", "Mixed speakers", "Call audio", "Microphone"]
        let candidates = mic.map { $0.name }.filter { !$0.isEmpty && !generic.contains($0) && !$0.hasPrefix("Speaker ") }
        let names = Set(candidates)
        return names.count == 1 ? names.first! : "You"
    }
    static let microphoneKey = "__microphone_display_name__"
    static func labels(_ turns: [SpeakerEvidence]) -> [String: String] {
        var counts: [String: Int] = [:]
        for turn in turns { counts[turn.text, default: 0] += 1 }
        var result: [String: String] = [microphoneKey: microphoneName(turns)]
        for turn in turns {
            let k = key(text: turn.text, startedAt: turn.startedAt, mic: turn.mic)
            if k != turn.text || counts[turn.text] == 1 { result[k] = turn.name }
            if counts[turn.text] == 1 { result[turn.text] = turn.name }
        }
        return result
    }
}

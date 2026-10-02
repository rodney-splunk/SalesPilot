import Foundation

/// Reports energy activity independently of slow transcription; not speaker identification.
struct SpeechActivity {
    struct Event { let active: Bool; let at: Double; let voicedAt: Double }
    private var voicedAt: Double? = nil
    private var lastReportedAt: Double = 0
    private var lastReportedActive = false
    mutating func ingest(rms: Float, at: Double) -> Event? {
        if rms > 0.012 { voicedAt = at }
        guard let voice = voicedAt else { return nil }
        let active = at - voice < 0.6
        guard active != lastReportedActive || (active && at - lastReportedAt >= 0.25) else { return nil }
        lastReportedAt = at; lastReportedActive = active
        return Event(active: active, at: at, voicedAt: voice)
    }
}

import Foundation

/// Endpoints depend on elapsed audio, not timer scheduling or transcription guesses.
struct PracticeTurnGate {
    enum Event: Equatable { case none, began, ended }
    private(set) var speaking = false
    private var onset = 0.0
    private var silence = 0.0
    private var elapsed = 0.0
    private var noise = -65.0
    mutating func reset() { self = Self() }
    mutating func ingest(db: Double, duration: Double, playback: Bool) -> Event {
        guard db.isFinite, duration.isFinite, duration > 0 else { return .none }
        let dt = min(duration, 0.2)
        // Voice processing removes playback; require stronger sustained residual speech for barge-in.
        let threshold = max(playback ? -36.0 : -45.0, min(-25.0, noise + (playback ? 16 : 12)))
        let voiced = db > threshold
        if !speaking {
            if !voiced { if !playback { noise = noise * 0.98 + db * 0.02 }; onset = 0; return .none }
            onset += dt
            if onset >= (playback ? 0.32 : 0.20) { speaking = true; elapsed = onset; silence = 0; return .began }
            return .none
        }
        elapsed += dt
        silence = voiced ? 0 : silence + dt
        if silence >= 1.25 || elapsed >= 60 { reset(); return .ended }
        return .none
    }
}

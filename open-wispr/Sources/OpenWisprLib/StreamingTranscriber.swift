// StreamingTranscriber.swift — SCAFFOLD (Phase 1)
// Continuous, low-latency transcription for ONE audio source, using a sliding window +
// LocalAgreement-2 commit: emit a word only once two successive runs AGREE on it → stable,
// non-flickering captions. Wraps open-wispr's existing whisper.cpp binding (Transcriber.swift)
// for the actual inference; this file is the streaming/commit policy layer.
//
// Policy source: whisper_streaming / WhisperLiveKit. Window 5s, hop 1s. base.en on Apple Silicon
// runs >15x real-time, so this is comfortably near-live.

import Foundation

struct TranscriptSegment {
    let speaker: String        // "me" (mic) | "customer" (system tap)
    let text: String
    let tStart: Double
    let tEnd: Double
    let committed: Bool        // true once LocalAgreement settles → engine fires the fast tier
}

final class StreamingTranscriber {
    private let speaker: String
    private let sampleRate: Double = 16_000
    private let windowSec: Double = 5
    private let hopSec: Double = 1

    private var ring: [Float] = []           // rolling 16 kHz mono buffer
    private var windowStart: Double = 0       // session-time (s) of ring[0]
    private var committedWords: [String] = [] // words already emitted as committed
    private var lastRunWords: [String] = []   // previous run's word list (for agreement)
    private let queue = DispatchQueue(label: "streaming.transcriber")
    private var timer: DispatchSourceTimer?

    var onSegment: ((TranscriptSegment) -> Void)?

    init(speaker: String) { self.speaker = speaker }

    /// Feed 16 kHz mono samples as they arrive from the capture source (mic or system tap).
    func append(_ samples: [Float]) { queue.async { self.ring.append(contentsOf: samples) } }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + hopSec, repeating: hopSec)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume(); timer = t
    }
    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        guard ring.count >= Int(hopSec * sampleRate) else { return }
        let window = Array(ring.suffix(Int(windowSec * sampleRate)))

        // TODO: run whisper.cpp on `window` via open-wispr's binding (Transcriber.swift).
        //   Return per-word tokens for the window. VAD-gate silence; drop [MUSIC]/(silence).
        //   let words = WhisperBridge.transcribeWords(window, sampleRate: sampleRate)
        let words: [String] = []   // <-- replace with real inference output

        // LocalAgreement-2: commit the longest common prefix of THIS run and the LAST run.
        let stable = commonPrefix(lastRunWords, words)
        if stable.count > committedWords.count {
            let fresh = Array(stable.dropFirst(committedWords.count))
            committedWords = stable
            emit(fresh.joined(separator: " "), committed: true)
            // TODO: once committed, slide the window: drop leading committed audio from `ring`
            //       and advance `windowStart` so memory/latency stay bounded.
        }
        let provisional = Array(words.dropFirst(committedWords.count))
        if !provisional.isEmpty { emit(provisional.joined(separator: " "), committed: false) }
        lastRunWords = words
    }

    private func emit(_ text: String, committed: Bool) {
        guard !text.isEmpty else { return }
        onSegment?(TranscriptSegment(speaker: speaker, text: text,
                                     tStart: windowStart, tEnd: windowStart + windowSec,
                                     committed: committed))
    }

    private func commonPrefix(_ a: [String], _ b: [String]) -> [String] {
        var out: [String] = []
        for (x, y) in zip(a, b) where x.lowercased() == y.lowercased() { out.append(y) }
        return out
    }
}

// Wire-up (in StreamSession): one instance per source.
//   let me = StreamingTranscriber(speaker: "me")        // fed by AudioRecorder streaming mode
//   let them = StreamingTranscriber(speaker: "customer") // fed by SystemAudioCapture
//   [me, them].forEach { $0.onSegment = sink.send; $0.start() }   // sink → serve.mjs over a socket

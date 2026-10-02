// StreamingMicTranscriber.swift — streaming transcription for ONE audio source.
// Either captures the mic itself (capturesMic: true → "You") or is fed external samples via
// append() (e.g. the system-audio process tap → "Customer"). Rolling window + LocalAgreement-2;
// a short silence finalizes the utterance as a turn.

import AVFoundation
import Foundation

final class StreamingMicTranscriber {
    var onUpdate: ((_ committed: String, _ provisional: String) -> Void)?
    /// (text, wavPath) — wavPath is a per-turn snapshot for speaker diarization, or nil when the
    /// turn was too short to have been re-transcribed. The consumer owns deleting it.
    var onTurnDetailed: ((String, String?, Double, Double, [TimedWord]) -> Void)?
    var onTurnFinalized: ((String, String?, Double, Double) -> Void)?

    var onActivity: ((Bool, Double, Double) -> Void)?
    private var speechActivity = SpeechActivity()

    let speaker: String
    private let capturesMic: Bool
    private let liveTranscriber: Transcriber    // fast (small.en, greedy) — drives the live scroll
    private let finalTranscriber: Transcriber   // accurate (medium/turbo, beam) — the committed turn
    private let sampleRate: Double = 16_000
    private let hop: TimeInterval = 0.4      // tick cadence: the fast live model (~0.3s/pass) keeps up at 0.4s
    private let silenceHold: TimeInterval = 0.6
    private let rmsThreshold: Float = 0.012
    private let minTranscribeSec: Double = 0.8
    private let maxUtteranceSec: Double = 25
    private let liveWindowSec: Double = 8    // per-tick transcription bounded to the last N s; finalize re-runs the FULL utterance accurately

    private let engine = AVAudioEngine()
    private let tmpURL: URL

    /// Set when a single utterance runs past maxUtteranceSec. The next tick closes the turn, so long
    /// answers split across turns instead of losing their opening.
    private var overlongFlush = false
    private let lock = NSLock()
    private var buffer: [Float] = []
    private var lastVoiceAt = Date()
    private var hadVoice = false
    private var voiceStartedAt: Date?

    private var committedWords: [String] = []
    private var lastRunWords: [String] = []

    private let workQ: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var running = false

    init(live: Transcriber, final: Transcriber, speaker: String, capturesMic: Bool) {
        self.liveTranscriber = live
        self.finalTranscriber = final
        self.speaker = speaker
        self.capturesMic = capturesMic
        self.tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("owstream-\(speaker)-\(UUID().uuidString).wav")
        self.workQ = DispatchQueue(label: "stream.work.\(speaker)")
    }

    /// Feed external 16 kHz mono samples (used by the system-audio tap).
    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        var sum: Float = 0
        for v in samples { sum += v * v }
        ingest(samples, rms: (sum / Float(samples.count)).squareRoot())
    }

    private func ingest(_ samples: [Float], rms: Float) {
        lock.lock()
        let activity = speechActivity.ingest(rms: rms, at: Date().timeIntervalSince1970)
        buffer.append(contentsOf: samples)
        if rms > rmsThreshold {
            let now = Date()
            if !hadVoice { voiceStartedAt = now.addingTimeInterval(-Double(samples.count) / sampleRate) }
            lastVoiceAt = now; hadVoice = true
        }
        if !hadVoice {
            let preRoll = Int(sampleRate * 0.25)
            if buffer.count > preRoll { buffer.removeFirst(buffer.count - preRoll) }
        }
        let maxN = Int(maxUtteranceSec * sampleRate)
        if buffer.count > maxN {
            if hadVoice {
                // This used to drop the OLDEST audio to hold the cap, which silently deleted the
                // beginning of any utterance longer than maxUtteranceSec. A customer walking through
                // their environment routinely talks past it without a real pause, so the front of the
                // most substantive answer of the call was the part being thrown away. Flush what we
                // have as a finished turn instead: the turn splits, but not one word is lost.
                overlongFlush = true
            } else {
                buffer.removeFirst(buffer.count - maxN)   // pure silence: bound memory, nothing to keep
            }
        }
        lock.unlock()
        if let event = activity {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.onActivity?(event.active, event.at, event.voicedAt)
            }
        }
    }

    func start() throws {
        guard !running else { return }
        if capturesMic {
            do {
                try startMicEngine(aec: UserDefaults.standard.bool(forKey: "aec"))
            } catch {
                // Voice processing can fail to build a valid graph on some devices (observed:
                // avfaudio -10875), which previously left the mic DEAD while the user thought echo
                // cancellation was simply working. An optional feature must never cost you the mic.
                guard UserDefaults.standard.bool(forKey: "aec") else { throw error }
                NSLog("StreamingMic: echo cancellation failed to start (\(error.localizedDescription)) — falling back to plain capture")
                try startMicEngine(aec: false)
            }
        }
        running = true
        let t = DispatchSource.makeTimerSource(queue: workQ)
        t.schedule(deadline: .now() + hop, repeating: hop)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Build and start the mic graph. With `aec`, Voice Processing needs a live render path, so the
    /// input is routed to a silenced mixer — connected with a nil format so the engine negotiates a
    /// compatible one (passing the raw input format is what produced -10875).
    private func startMicEngine(aec: Bool) throws {
        let input = engine.inputNode
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        try? input.setVoiceProcessingEnabled(aec)

        let inFmt = input.outputFormat(forBus: 0)
        guard inFmt.channelCount > 0, inFmt.sampleRate > 0,
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFmt, to: outFmt) else {
            if aec { try? input.setVoiceProcessingEnabled(false) }
            throw NSError(domain: "StreamingMic", code: 1, userInfo: [NSLocalizedDescriptionKey: "mic audio format unavailable (permission not granted?)"])
        }
        if aec {
            let mixer = engine.mainMixerNode
            mixer.outputVolume = 0
            engine.connect(input, to: mixer, format: nil)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buf, _ in
            guard let self = self else { return }
            let cap = AVAudioFrameCount(Double(buf.frameLength) * self.sampleRate / inFmt.sampleRate)
            guard cap > 0, let conv = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return }
            var err: NSError?
            var fed = false
            converter.convert(to: conv, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            guard err == nil, let ch = conv.floatChannelData?[0] else { return }
            let n = Int(conv.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            self.ingest(Array(UnsafeBufferPointer(start: ch, count: n)), rms: (sum / Float(n)).squareRoot())
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            if aec { try? input.setVoiceProcessingEnabled(false) }
            throw error
        }
    }

    func stop(completion: @escaping () -> Void = {}) {
        guard running else { DispatchQueue.main.async(execute: completion); return }
        running = false
        timer?.cancel(); timer = nil
        if capturesMic {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        workQ.async { [self] in
            finalizeTurn()
            try? FileManager.default.removeItem(at: tmpURL)
            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: - Transcription loop (workQ)
    private func tick() {
        lock.lock()
        let full = buffer
        let silent = Date().timeIntervalSince(lastVoiceAt) > silenceHold
        let voiced = hadVoice
        let overlong = overlongFlush
        lock.unlock()

        // Only spend Whisper on voiced audio — a silent/idle stream skips work entirely.
        guard voiced, full.count >= Int(minTranscribeSec * sampleRate) else {
            if silent && voiced { finalizeTurn() }
            return
        }
        // Past the length cap mid-speech: close this turn now rather than let ingest() bin the front.
        if overlong || silent { finalizeTurn(); return }
        // Bound per-tick cost: transcribe only the last liveWindowSec for the streaming display, so a
        // long monologue doesn't make each pass slower. Short turns (buffer <= window) are unchanged.
        let windowN = Int(liveWindowSec * sampleRate)
        let snapshot = full.count > windowN ? Array(full.suffix(windowN)) : full
        guard writeWav(snapshot, to: tmpURL) else { return }
        let text = (try? liveTranscriber.transcribe(audioURL: tmpURL)) ?? ""
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

        if full.count > windowN {
            committedWords = []; lastRunWords = words
            DispatchQueue.main.async { self.onUpdate?("", text) }
            return
        }
        let stable = commonPrefix(lastRunWords, words)
        if stable.count > committedWords.count { committedWords = stable }
        lastRunWords = words

        let committed = committedWords.joined(separator: " ")
        let provisional = words.count > committedWords.count
            ? words[committedWords.count...].joined(separator: " ") : ""
        DispatchQueue.main.async { self.onUpdate?(committed, provisional) }

        if silent && voiced { finalizeTurn() }
    }

    private func finalizeTurn() {
        lock.lock()
        let full = buffer
        let startedAt = (voiceStartedAt ?? Date()).timeIntervalSince1970
        let endedAt = lastVoiceAt.timeIntervalSince1970
        buffer.removeAll(); hadVoice = false; overlongFlush = false; voiceStartedAt = nil
        lock.unlock()
        var finalWords = lastRunWords.count >= committedWords.count ? lastRunWords : committedWords
        // Always re-transcribe the full utterance with the ACCURATE model on finalize — the live ticks
        // only ran the FAST model (small.en, greedy, tail window). This committed text is what gets
        // shown, coached, and recorded, so it takes the quality pass regardless of turn length.
        var timedWords: [TimedWord] = []
        var turnWav: String? = nil
        if full.count >= Int(minTranscribeSec * sampleRate), writeWav(full, to: tmpURL) {
            let detailed = try? finalTranscriber.transcribeDetailed(audioURL: tmpURL)
            let text = detailed?.0 ?? ""
            timedWords = detailed?.1 ?? []
            let w = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            if !w.isEmpty { finalWords = w }
            // A SECOND copy under a unique name, written straight from the same buffer. tmpURL is
            // reused by every live tick (every 0.4s), so handing that path to an async consumer
            // would hand it whatever audio happened to be there by the time it read the file.
            let uniq = FileManager.default.temporaryDirectory
                .appendingPathComponent("owturn-\(speaker)-\(UUID().uuidString).wav")
            if writeWav(full, to: uniq) { turnWav = uniq.path }
        }
        committedWords = []; lastRunWords = []
        var final = finalWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        final = StreamingMicTranscriber.stripHallucination(final)
        if !final.isEmpty && !isJunkTurn(final) {
            DispatchQueue.main.async { self.onUpdate?("", ""); if let detailed = self.onTurnDetailed { detailed(final, turnWav, startedAt, endedAt, timedWords) } else { self.onTurnFinalized?(final, turnWav, startedAt, endedAt) } }
        } else {
            // Junk: clear the line, commit nothing, and don't leave the snapshot behind.
            if let w = turnWav { try? FileManager.default.removeItem(atPath: w) }
            DispatchQueue.main.async { self.onUpdate?("", "") }
        }
    }

    /// Whisper emits stock phrases when fed near-silence ("you", "Thank you.", "Bye."). Those became
    /// real turns — polluting the transcript, the coach context, and the archived record. Drop them.
    private static let junkPhrases: Set<String> = [
        "you", "thank you", "thanks", "thanks for watching", "thank you for watching",
        "bye", "goodbye", "okay", "ok", "uh", "um", "hmm", "mm", "mhm", "mm-hmm",
        "yeah", "yep", "so", "the", "a", "i", "and", "oh", "please subscribe", "subscribe",
    ]
    /// Whisper fills near-silence with the closing credits of its training data: "Thank you for
    /// watching.", "For more information, visit our website at ...", "That's it for this week."
    /// Measured across archived calls these were 3% of ALL turns, and on one real call 7% — they
    /// land in the transcript as things the customer said, and the coach then reads them.
    /// They are stripped rather than dropped, because one arrived as "Thanks for your time. My
    /// internal developers." where the second half was real speech running into the next turn.
    // Two shapes. A promo line ("for more information, visit ...") is always the whole dead turn and
    // runs to the end, because the URL in it defeats any sentence boundary. A sign-off ("thank you
    // for joining us today") is one sentence and real speech can follow it in the same turn.
    private static let hallucinatedWholeTurn = try! NSRegularExpression(pattern:
        "^(?:" +
        "(?:for more information|to learn more)[ ,]" +
        "|(?:please )?(?:visit|see) (?:our|the) (?:website|complete disclaimer|full disclaimer)" +
        "|(?:please )?(?:like and )?subscribe" +
        ").*$", options: [.caseInsensitive, .dotMatchesLineSeparators])

    private static let hallucinatedSentence = try! NSRegularExpression(pattern:
        "^(?:" +
        "thank(?:s| you)(?: so much| very much)?(?: for)? (?:watching|joining|listening|tuning in|reaching out|your time|your attention)" +
        "|thanks for watching" +
        "|see you (?:in the )?next (?:video|time|week)" +
        "|that'?s it for this (?:week|video|episode)" +
        "|(?:this video is )?available (?:on|at) the (?:google play store|app store)" +
        ")[^.?!]*[.?!]*\\s*", options: [.caseInsensitive])

    /// Remove a leading credit-roll artifact. Returns "" when that is all the turn was.
    static func stripHallucination(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Exact stock sentence observed in silence; preserve ordinary pandemic discussion.
        if t.range(of: #"(?i)^[,.\s]*(?:and )?if you are looking for a solution to the covid[- ]19 pand\s*emic,? please contact your local\s*[.!?]*$"#, options: .regularExpression) != nil { return "" }
        guard t.split(separator: " ").count <= 14 else { return t }   // only ever a short, dead turn
        let range = NSRange(t.startIndex..., in: t)
        if hallucinatedWholeTurn.firstMatch(in: t, options: [.anchored], range: range) != nil { return "" }
        guard let m = hallucinatedSentence.firstMatch(in: t, options: [.anchored], range: range),
              let r = Range(m.range, in: t) else { return t }
        let rest = String(t[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // A couple of stray words left over from a sign-off are debris, not speech.
        return rest.split(separator: " ").count >= 3 ? rest : ""
    }

    private func isJunkTurn(_ text: String) -> Bool {
        let norm = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?-—…\"'"))
            .trimmingCharacters(in: .whitespaces)
        guard !norm.isEmpty else { return true }
        // Whisper also emits bracketed annotations on silence ("[ Pause ]", "(silence)", "[BLANK_AUDIO]").
        // Drop anything that is ENTIRELY such an annotation, rather than chasing a list of words.
        if norm.count <= 40,
           let f = norm.first, let l = norm.last,
           (f == "[" && l == "]") || (f == "(" && l == ")") { return true }
        guard norm.split(separator: " ").count <= 3 else { return false }
        return StreamingMicTranscriber.junkPhrases.contains(norm)
    }

    private func commonPrefix(_ a: [String], _ b: [String]) -> [String] {
        var out: [String] = []
        for (x, y) in zip(a, b) {
            if x.lowercased() == y.lowercased() { out.append(y) } else { break }
        }
        return out
    }

    private func writeWav(_ samples: [Float], to url: URL) -> Bool {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(max(1, samples.count))) else { return false }
        buf.frameLength = AVAudioFrameCount(samples.count)
        if let ch = buf.floatChannelData?[0] { for i in 0..<samples.count { ch[i] = samples[i] } }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try file.write(from: buf)
        } catch { return false }
        return true
    }
}

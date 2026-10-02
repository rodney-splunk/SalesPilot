// ReplayRunner.swift — feed a recorded audio file through the REAL transcription pipeline (same split
// models, same StreamingMicTranscriber) headlessly, and report the turns + timing. Lets us verify and
// profile the live path on real audio without a live call or the GUI.  Run: `SalesPilot replay <file>`.

import AVFoundation
import Foundation

public enum ReplayRunner {
    private static var coachWatch: DispatchSourceTimer?

    /// Load any audio file as 16 kHz mono Float32 samples (the format the transcriber ingests).
    private static func loadSamples(_ path: String) -> [Float]? {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFmt = file.processingFormat
        guard inFmt.sampleRate > 0,
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFmt, to: outFmt),
              file.length > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }
        let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * (16000.0 / inFmt.sampleRate)) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCap) else { return nil }
        var err: NSError?
        var fed = false
        converter.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil, let ch = outBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
    }

    /// Turns in latest.json that carry a coaching card, newest last.
    private static func coachCards() -> [(target: String, q: String)] {
        let url = WorkspacePaths.session
        guard let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let turns = obj["turns"] as? [[String: Any]] else { return [] }
        return turns.compactMap { t in
            guard let q = t["coachQ"] as? String, !q.isEmpty else { return nil }
            return (target: (t["coachTarget"] as? String) ?? "?", q: q)
        }
    }

    /// Capture from the REAL system input via AVAudioEngine (the one layer replay can't reach).
    /// Pair with a virtual input device (BlackHole) to feed it known audio.
    public static func micCheck(seconds: Double) {
        let cfg = Config.load()
        let liveModel = Transcriber.modelExists(modelSize: "small.en") ? "small.en"
                      : Transcriber.modelExists(modelSize: "base.en") ? "base.en" : cfg.modelSize
        let finalModel = Transcriber.modelExists(modelSize: "medium.en") ? "medium.en"
                       : Transcriber.modelExists(modelSize: "large-v3-turbo") ? "large-v3-turbo" : liveModel
        let vocab = (cfg.whisperPrompt?.isEmpty == false) ? cfg.whisperPrompt! : Transcriber.salesVocabulary
        print("── mic check ──")
        print("live: \(liveModel)  final: \(finalModel)")
        let t = StreamingMicTranscriber(
            live: Transcriber(modelSize: liveModel, language: cfg.language, whisperPrompt: vocab, threads: 4, beamSize: nil),
            final: Transcriber(modelSize: finalModel, language: cfg.language, whisperPrompt: vocab, threads: 6, beamSize: 5),
            speaker: "you", capturesMic: true)
        var turns = 0
        var sawAudio = false
        t.onUpdate = { c, p in if !(c.isEmpty && p.isEmpty) { sawAudio = true } }
        t.onTurnFinalized = { turn, wav, _, _ in
            turns += 1; print("  [mic turn \(turns)] \(turn)")
            if let w = wav { try? FileManager.default.removeItem(atPath: w) }
        }
        do { try t.start() } catch {
            print("  MIC START FAILED: \(error.localizedDescription)")
            WhisperServerPool.shared.shutdownAll(); exit(1)
        }
        print("listening on the system input for \(Int(seconds))s…\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            t.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                print("\n── mic check done: \(turns) turn(s), audio seen: \(sawAudio) ──")
                WhisperServerPool.shared.shutdownAll()
                exit(turns > 0 ? 0 : 2)
            }
        }
        dispatchMain()
    }

    /// Duplex: drive BOTH channels at once (mic side + customer side) to exercise stream interleaving
    /// and speaker attribution. `youPath` nil = customer-only (the original behaviour).
    public static func run(wavPath: String, coach: Bool = false, youPath: String? = nil) {
        if coach {
            guard ProcessInfo.processInfo.environment["SALESPILOT_ROOT"] != nil else {
                fputs("Coached replay requires an isolated SALESPILOT_ROOT.\n", stderr); exit(1)
            }
            setenv("SALESPILOT_LOCAL_ONLY", "1", 1); setenv("SALESPILOT_OFFLINE", "1", 1); setenv("COACH_LOCAL", "1", 1); setenv("PROVIDER", "ollama", 1)
            do { try CaptureJournal.begin() } catch { fputs("Replay journal unavailable.\n", stderr); exit(1) }
        }
        guard let samples = loadSamples(wavPath) else {
            FileHandle.standardError.write(Data("replay: could not read audio file '\(wavPath)'\n".utf8))
            exit(1)
        }
        let sr = 16000.0
        let cfg = Config.load()
        let liveModel = Transcriber.modelExists(modelSize: "small.en") ? "small.en"
                      : Transcriber.modelExists(modelSize: "base.en") ? "base.en" : cfg.modelSize
        let finalModel = Transcriber.modelExists(modelSize: "medium.en") ? "medium.en"
                       : Transcriber.modelExists(modelSize: "large-v3-turbo") ? "large-v3-turbo" : liveModel

        print("── replay ──")
        print(String(format: "file:  %@  (%.1fs)", wavPath, Double(samples.count) / sr))
        print("live:  \(liveModel) (greedy)   final: \(finalModel) (beam)")
        print("feeding in real time; turns segment on natural pauses\n")

        let vocab = (cfg.whisperPrompt?.isEmpty == false) ? cfg.whisperPrompt! : Transcriber.salesVocabulary
        let t = StreamingMicTranscriber(
            live: Transcriber(modelSize: liveModel, language: cfg.language, whisperPrompt: vocab, threads: 4, beamSize: nil),
            final: Transcriber(modelSize: finalModel, language: cfg.language, whisperPrompt: vocab, threads: 6, beamSize: 5),
            speaker: "customer", capturesMic: false)

        var start = Date()
        var firstText: Double? = nil
        var turns = 0
        var lastFinalize = start

        t.onUpdate = { committed, provisional in
            if firstText == nil && !(committed.isEmpty && provisional.isEmpty) {
                firstText = Date().timeIntervalSince(start)
                print(String(format: "  first live text: %.2fs after audio start", firstText!))
            }
        }
        // Optional second channel: the mic side. Same pipeline, speaker="you".
        var youT: StreamingMicTranscriber? = nil
        var youSamples: [Float] = []
        if let yp = youPath {
            guard let ys = loadSamples(yp) else {
                FileHandle.standardError.write(Data("replay: could not read '\(yp)'\n".utf8)); exit(1)
            }
            youSamples = ys
            let yt = StreamingMicTranscriber(
                live: Transcriber(modelSize: liveModel, language: cfg.language, whisperPrompt: vocab, threads: 4, beamSize: nil),
                final: Transcriber(modelSize: finalModel, language: cfg.language, whisperPrompt: vocab, threads: 6, beamSize: 5),
                speaker: "you", capturesMic: false)
            yt.onTurnDetailed = { turn, wav, began, ended, words in
                print(String(format: "  [YOU  ] %@", turn))
                if coach { LiveCoach.shared.feed(speaker: "you", text: turn, wav: wav, startedAt: began, endedAt: ended, words: words) }
                else if let w = wav { try? FileManager.default.removeItem(atPath: w) }
            }
            try? yt.start()
            youT = yt
            print("duplex: also driving the mic channel from \(yp)\n")
        }

        var fedAt: [Date] = []
        t.onTurnDetailed = { turn, wav, began, ended, words in
            turns += 1
            let gap = Date().timeIntervalSince(lastFinalize)
            lastFinalize = Date()
            print(String(format: "  [%@ %d  +%.1fs] %@", youPath == nil ? "turn" : "CUST", turns, gap, turn))
            if coach { fedAt.append(Date()); LiveCoach.shared.feed(speaker: "customer", text: turn, wav: wav, startedAt: began, endedAt: ended, words: words) }
            else if let w = wav { try? FileManager.default.removeItem(atPath: w) }
        }
        try? t.start()

        // Optional: run the REAL coach on each finalized turn and report the card + its latency.
        var cardsSeen = 0
        if coach {
            LiveCoach.shared.start(framework: Coaching.selectedID,
                                   mode: UserDefaults.standard.string(forKey: "coachCueMode") ?? "autopilot")
            let watch = DispatchSource.makeTimerSource(queue: .main)
            watch.schedule(deadline: .now() + 0.5, repeating: 0.25)
            watch.setEventHandler {
                let cards = coachCards()
                while cardsSeen < cards.count {
                    let c = cards[cardsSeen]
                    let lat = cardsSeen < fedAt.count ? Date().timeIntervalSince(fedAt[cardsSeen]) : -1
                    print(String(format: "     ↳ coach %@[%@] %@",
                                 lat >= 0 ? String(format: "(%.1fs) ", lat) : "", c.target, c.q))
                    cardsSeen += 1
                }
            }
            watch.resume()
            coachWatch = watch
        }

        // Feed 0.1s chunks in real time so RMS silence gaps finalize turns exactly like a live call.
        var idx = 0
        let chunk = Int(0.1 * sr)
        let feeder = DispatchSource.makeTimerSource(queue: .main)
        feeder.schedule(deadline: .now() + 0.1, repeating: 0.1)
        feeder.setEventHandler {
            if idx >= samples.count {
                feeder.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    t.stop(); youT?.stop() // flush the final turns on both channels
                    // Give the coach time to finish the last card(s) before summarizing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + (coach ? 8.0 : 3.0)) {
                        if coach { coachWatch?.cancel(); coachWatch = nil; LiveCoach.shared.stop() }
                        print(String(format: "\n── done: %d turns, %.1fs wall%@ ──",
                                     turns, Date().timeIntervalSince(start),
                                     firstText.map { String(format: ", first text %.2fs", $0) } ?? ""))
                        WhisperServerPool.shared.shutdownAll()
                        exit(0)
                    }
                }
                return
            }
            let end = min(idx + chunk, samples.count)
            t.append(Array(samples[idx..<end]))
            if let yt = youT, idx < youSamples.count {
                let yend = min(idx + chunk, youSamples.count)
                yt.append(Array(youSamples[idx..<yend]))
            }
            idx = end
        }
        // Warm the resident servers before feeding, so replay measures the same warm path a real call
        // gets (servers are prewarmed at Start Live). Falls back to whisper-cli if they don't come up.
        let livePath = Transcriber.findModel(modelSize: liveModel)
        let finalPath = Transcriber.findModel(modelSize: finalModel)
        WhisperServerPool.shared.prewarm(modelPaths: [livePath, finalPath].compactMap { $0 }, threads: 6)
        DispatchQueue.global().async {
            var warm = false
            if let lp = livePath {
                for _ in 0..<24 {   // up to ~12s for the model to become resident
                    if WhisperServerPool.shared.inferenceURL(forModelPath: lp, threads: 4) != nil { warm = true; break }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            DispatchQueue.main.async {
                print(warm ? "servers: warm (resident model, no per-call reload)\n"
                           : "servers: whisper-cli fallback (whisper-server not ready)\n")
                start = Date(); lastFinalize = start   // measure from when audio actually starts
                feeder.resume()
            }
        }
        dispatchMain()
    }
}

// MARK: - Dictation path test hook
public enum DictationCheck {
    /// Run the DICTATION transcribe path over a wav, exactly as a hotkey press would, and report what
    /// it produced, how long it took, and whether it went through the resident server or fell back to
    /// whisper-cli. The call path has `replay` and `miccheck`; this is the equivalent for dictation,
    /// and without it changes to prompting or model residency could not be verified at all.
    public static func run(wavPath: String, repeats: Int = 3) {
        let cfg = Config.load()
        guard let modelPath = Transcriber.findModel(modelSize: cfg.modelSize) else {
            print("no model for \(cfg.modelSize)"); return
        }
        let prompt = (cfg.whisperPrompt?.isEmpty == false) ? cfg.whisperPrompt! : Transcriber.salesVocabulary
        print("── dictation check ──")
        print("model:  \(cfg.modelSize)")
        print("prompt: \(prompt.count) chars\(cfg.whisperPrompt?.isEmpty == false ? " (from config)" : " (salesVocabulary)")")

        let t = Transcriber(modelSize: cfg.modelSize, language: cfg.language, whisperPrompt: prompt)
        t.spokenPunctuation = cfg.spokenPunctuation?.value ?? false
        let url = URL(fileURLWithPath: wavPath)

        for i in 1...max(repeats, 1) {
            let served = WhisperServerPool.shared.inferenceURL(forModelPath: modelPath, threads: 4) != nil
            let t0 = Date()
            let text = (try? t.transcribe(audioURL: url)) ?? "(failed)"
            let dt = Date().timeIntervalSince(t0)
            print(String(format: "  run %d  %.2fs  [%@]  %@", i, dt,
                         served ? "server" : "cli/warming", text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        print("── done ──")
    }
}

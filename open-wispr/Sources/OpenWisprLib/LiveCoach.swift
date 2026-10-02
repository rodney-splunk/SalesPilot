// LiveCoach.swift — keeps a persistent serve.mjs process running for a live call and streams
// finalized turns to it. serve.mjs coaches the newest turn, writes latest.json, prints "@@updated@@";
// we post .reloadSession so the review window refreshes in real time.

import Foundation

final class LiveCoach {
    static let shared = LiveCoach()
    private var proc: Process?
    private var recapProc: Process?          // a process still finishing its end-of-call recap
    private var stdin: FileHandle?
    private var outReadHandle: FileHandle?
    private var lineBuffer = Data()
    private let outputLock = NSLock()
    private var generation = UUID()
    private var logHandle: FileHandle?

    private func isCurrent(_ epoch: UUID) -> Bool {
        outputLock.lock(); defer { outputLock.unlock() }
        return generation == epoch
    }

    private static func readSessionMeta() -> (name: String?, engineError: String?, answer: String?, answerSources: String?, rosterCount: Int, whoByText: [String: String], nextQuestion: String?, nextTarget: String?, answerStatus: String?) {
        let url = WorkspacePaths.session
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil, nil, nil, 0, [:], nil, nil, nil) }
        let name = (obj["customerName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let err = (obj["engineError"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var answer: String? = nil, sources: String? = nil
        if let la = obj["liveAnswer"] as? [String: Any] {
            answer = (la["answer"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let s = la["sources"] as? [String], !s.isEmpty {
                let titles = la["sourceTitles"] as? [String: String] ?? [:]
                sources = "sources: " + s.map { titles[$0] ?? $0 }.joined(separator: ", ")
            }
        }
        let rosterCount = (obj["roster"] as? [[String: Any]])?.filter { ($0["side"] as? String) != "seller" }.count ?? 0
        // Who the engine says spoke each customer line. Carrying only the roster COUNT meant the HUD
        // fell back to a generic "CUST" for everyone the moment a second person was known, throwing
        // away attribution the engine had already worked out.
        let evidence = ((obj["turns"] as? [[String: Any]]) ?? []).flatMap { t -> [SpeakerEvidence] in
            guard let text = t["text"] as? String, let name = t["who"] as? String else { return [] }
            var items = [SpeakerEvidence(text: text, startedAt: t["startedAt"] as? Double, mic: (t["me"] as? Bool) ?? false, name: name)]
            if let raw = t["rawText"] as? String, raw != text { items.append(SpeakerEvidence(text: raw, startedAt: t["startedAt"] as? Double, mic: (t["me"] as? Bool) ?? false, name: name)) }
            return items
        }
        let whoByText = SpeakerLookup.labels(evidence)
        let cue = (obj["nextq"] as? [[String: Any]])?.first
        return (name, err, answer, sources, rosterCount, whoByText, cue?["q"] as? String, (cue?["reason"] as? String) ?? (cue?["tag"] as? String), (obj["liveAnswer"] as? [String: Any])?["status"] as? String)
    }

    private static func nodePath() -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func start(framework: String, mode: String = "autopilot") {
        stop()
        let epoch = generation
        let engineDir = WorkspacePaths.engine
        let script = engineDir.appendingPathComponent("serve.mjs")
        guard let node = LiveCoach.nodePath(), FileManager.default.fileExists(atPath: script.path) else {
            DispatchQueue.main.async { LiveState.shared.engineError = "Coaching engine not found — is Node installed?" }
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [script.path, "--framework", framework, "--mode", mode]
        p.currentDirectoryURL = engineDir
        var environment = ProcessInfo.processInfo.environment
        environment["SALESPILOT_CALL_ID"] = CaptureJournal.callID
        environment["SALESPILOT_CALL_PURPOSE"] = UserDefaults.standard.string(forKey: "callPurpose") ?? "standard"
        environment["SALESPILOT_CREDENTIAL_READER"] = Bundle.main.executableURL?.path
        environment["SALESPILOT_CONSENT_CONFIRMED_AT"] = ISO8601DateFormatter().string(from: Date())
        environment["SALESPILOT_CALL_PROCESSING_MODE"] = UserDefaults.standard.string(forKey: "callProcessingMode") ?? "circuit"
        if environment["SALESPILOT_CALL_PROCESSING_MODE"] == "local" {
            environment["SALESPILOT_LOCAL_ONLY"] = "1"; environment["SALESPILOT_OFFLINE"] = "1"; environment["COACH_LOCAL"] = "1"; environment["PROVIDER"] = "ollama"
        }
        p.environment = environment
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        let log = SessionCapture.sessionsDir.appendingPathComponent("engine.log")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: log.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 2_000_000 {
            try? FileManager.default.removeItem(at: log.appendingPathExtension("previous"))
            try? FileManager.default.moveItem(at: log, to: log.appendingPathExtension("previous"))
        }
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        logHandle = try? FileHandle(forWritingTo: log)
        try? logHandle?.seekToEnd()
        p.standardError = logHandle ?? FileHandle.nullDevice

        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }   // EOF — stop firing
            guard let self = self else { return }
            self.outputLock.lock(); defer { self.outputLock.unlock() }
            guard self.generation == epoch else { return }
            self.lineBuffer.append(data)
            var sawUpdate = false
            while let nl = self.lineBuffer.firstIndex(of: 10) {
                let line = String(decoding: self.lineBuffer[..<nl], as: UTF8.self)
                self.lineBuffer.removeSubrange(...nl)
                if line.contains("@@updated@@") { sawUpdate = true }
                else if line.hasPrefix("@@drop@@ ") {
                    // Cross-channel echo: this turn was the customer's audio bleeding into the mic.
                    // Pull it off the live transcript so it isn't shown or attributed to the rep.
                    let json = String(line.dropFirst("@@drop@@ ".count))
                    if let d = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String],
                       let text = obj["text"] {
                        CaptureJournal.drop(text: text)
                        DispatchQueue.main.async {
                            guard self.isCurrent(epoch) else { return }
                            if let idx = LiveState.shared.turns.lastIndex(where: { $0.text == text }) {
                                LiveState.shared.turns.remove(at: idx)
                            }
                        }
                    }
                }
                else if line.hasPrefix("@@correct@@ ") {
                    // Background ASR cleanup: swap this turn's on-screen text in place (same id → no flicker).
                    let json = String(line.dropFirst("@@correct@@ ".count))
                    if let d = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String],
                       let orig = obj["orig"], let fixed = obj["text"] {
                        DispatchQueue.main.async {
                            guard self.isCurrent(epoch) else { return }
                            if let idx = LiveState.shared.turns.firstIndex(where: { $0.text == orig }) {
                                LiveState.shared.turns[idx].text = fixed
                            }
                        }
                    }
                }
            }
            if sawUpdate {
                let meta = LiveCoach.readSessionMeta()
                DispatchQueue.main.async {
                    guard self.isCurrent(epoch) else { return }
                    if let name = meta.name { LiveState.shared.customerName = name }
                    LiveState.shared.customerCount = meta.rosterCount
                    LiveState.shared.whoByText = meta.whoByText
                    LiveState.shared.engineError = meta.engineError   // nil when healthy → auto-clears
                    LiveState.shared.nextQuestion = meta.nextQuestion
                    LiveState.shared.nextQuestionTarget = meta.nextTarget
                    LiveState.shared.answer = meta.answer
                    LiveState.shared.answerSources = meta.answerSources
                    LiveState.shared.answerStatus = meta.answerStatus
                    NotificationCenter.default.post(name: .reloadSession, object: nil)
                }
            }
        }
        outReadHandle = outHandle

        p.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self, self.isCurrent(epoch), self.proc === process else { return }
                self.stdin = nil
                LiveState.shared.engineError = "Coaching stopped unexpectedly. End this call and restart coaching."
            }
        }
        do {
            try p.run()
            proc = p
            stdin = inPipe.fileHandleForWriting
        } catch {
            NSLog("LiveCoach start failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                guard self.isCurrent(epoch) else { return }
                LiveState.shared.engineError = "Could not start coaching. Check the local engine log."
            }
        }
    }

    /// Switch the coaching methodology mid-call (the live engine re-coaches the current transcript).
    func setFramework(_ id: String) {
        guard let stdin = stdin else { return }
        let obj: [String: String] = ["cmd": "framework", "value": id]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else { return }
        try? stdin.write(contentsOf: line)
    }

    /// Switch the coaching CUE STYLE mid-call (autopilot / nudge / gap). The engine re-renders the
    /// current SAY-NEXT list in the new style; future turns follow it. No re-coach LLM call.
    func setMode(_ id: String) {
        guard let stdin = stdin else { return }
        let obj: [String: String] = ["cmd": "mode", "value": id]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else { return }
        try? stdin.write(contentsOf: line)
    }

    func setSpeakerSide(clusterId: Int, side: String, name: String? = nil) {
        var profile: [String: Any] = ["cmd": "speaker", "clusterId": clusterId, "side": side]
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { profile["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let input = stdin,
              let data = try? JSONSerialization.data(withJSONObject: profile),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let encoded = line.data(using: .utf8) { try? input.write(contentsOf: encoded) }
    }

    func retryRequest(id: Int? = nil) {
        guard let input = stdin else { return }
        var command: [String: Any] = ["cmd": "retry"]
        if let id { command["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: command) else { return }
        try? input.write(contentsOf: data + Data([10]))
    }

    func resolveQuestion(id: Int, status: String) {
        guard ["answered", "deferred", "open"].contains(status), let input = stdin,
              let data = try? JSONSerialization.data(withJSONObject: ["cmd": "question", "id": id, "status": status]),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let encoded = line.data(using: .utf8) { try? input.write(contentsOf: encoded) }
    }

    func feedActivity(speaker: String, active: Bool, at: Double, voicedAt: Double) {
        guard let input = stdin,
              let data = try? JSONSerialization.data(withJSONObject: ["cmd": "activity", "speaker": speaker, "active": active, "at": at, "voicedAt": voicedAt]),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let encoded = line.data(using: .utf8) { try? input.write(contentsOf: encoded) }
    }

    /// Send a finalized turn. speaker is "you" or "customer". Safe if the process has died.
    /// `wav` is a per-turn audio snapshot for speaker diarization; the engine deletes it when done.
    /// If the engine is not running we delete it here, so a dead coach cannot leak temp files.
    func feed(speaker: String, text: String, wav: String? = nil, startedAt: Double? = nil, endedAt: Double? = nil, words: [TimedWord] = []) {
        do { try CaptureJournal.append(speaker: speaker, text: text, startedAt: startedAt, endedAt: endedAt) }
        catch { DispatchQueue.main.async { LiveState.shared.engineError = "Could not save the capture journal. End this call and check available storage." } }
        guard let stdin = stdin else {
            if let w = wav { try? FileManager.default.removeItem(atPath: w) }
            return
        }
        var obj: [String: Any] = ["speaker": speaker, "text": text, "finalizedAt": Date().timeIntervalSince1970]
        if let start = startedAt { obj["startedAt"] = start }
        if let end = endedAt { obj["endedAt"] = end }
        if let w = wav { obj["wav"] = w }
        if !words.isEmpty, let data = try? JSONEncoder().encode(words), let array = try? JSONSerialization.jsonObject(with: data) { obj["words"] = array }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else {
            if let wav { try? FileManager.default.removeItem(atPath: wav) }
            return
        }
        do {
            try stdin.write(contentsOf: line)
        } catch {
            if let wav { try? FileManager.default.removeItem(atPath: wav) }
            try? stdin.close()
            self.stdin = nil
            let epoch = generation
            DispatchQueue.main.async {
                guard self.isCurrent(epoch) else { return }
                LiveState.shared.engineError = "Coaching is unavailable. The transcript is still being captured."
            }
        }
    }

    /// Ask for an end-of-call recap, then close input so the engine finishes and exits cleanly.
    func finishWithRecap() {
        guard let stdin = stdin else { return }   // idempotent: a 2nd stop must NOT kill a running recap
        if let cmd = "{\"cmd\":\"recap\"}\n".data(using: .utf8) { try? stdin.write(contentsOf: cmd) }
        try? stdin.close()
        self.stdin = nil
        recapProc = proc   // keep it killable if a new call starts before the recap finishes
        proc = nil
        let p = recapProc
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { if p?.isRunning == true { p?.terminate() } }
    }

    func stop() {
        outReadHandle?.readabilityHandler = nil
        outReadHandle = nil
        outputLock.lock()
        generation = UUID(); lineBuffer = Data()
        outputLock.unlock()
        try? logHandle?.close(); logHandle = nil
        try? stdin?.close()
        stdin = nil
        proc?.terminate(); proc = nil
        recapProc?.terminate(); recapProc = nil   // kill any lingering recap from a previous call
    }
}

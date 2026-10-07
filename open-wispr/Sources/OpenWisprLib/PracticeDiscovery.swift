import AppKit
import SwiftUI
import AVFoundation

@MainActor final class PracticeMicrophoneMeter: ObservableObject {
    @Published var level = 0.0
}
struct PracticeMicrophoneLevel: View {
    @ObservedObject var meter: PracticeMicrophoneMeter
    var body: some View { ProgressView(value: meter.level).tint(SalesPilotStyle.accent).accessibilityLabel("Microphone input level") }
}

/// Fictional practice owns its audio and session, never the global system-audio tap.
@MainActor final class PracticeDiscovery: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PracticeDiscovery()
    @Published private(set) var active = false
    @Published private(set) var busy = false
    @Published private(set) var recording = false
    @Published private(set) var status = "Choose a practice option."
    @Published private(set) var failure: String?
    @Published private(set) var watching = false
    @Published private(set) var demoPaused = false
    @Published private(set) var demoComplete = false
    private var window: NSWindow?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var child: Process?
    private var inputChild: Process?
    private var inputTask: Task<Void, Never>?
    private var inputQueue: [(URL, Double, Double)] = []
    private var inputProgress = PracticeInputProgress()
    private var handsFree: PracticeAudio?
    var microphoneAvailable: Bool { handsFree != nil }
    @Published private(set) var muted = false
    let meter = PracticeMicrophoneMeter()
    @Published private(set) var microphoneName = "System default microphone"
    private var sessionGeneration = UUID()
    private var inputGeneration = UUID()
    private var player: AVAudioPlayer?
    private var conversation: [[String: String]] = []
    private var revealed: [String] = []
    private var root: URL?
    private var processing = "local"
    private let intro = "Hi, I'm Dana Reyes. I lead security operations at the fictional company Northstar. Thanks for meeting with me."
    private let demo: [(String, String)] = [
        ("you", "Hi Dana, I'm Rodney White from Splunk. I'd like to understand your investigation workflow today. Could you walk me through what happens when an alert arrives?"),
        ("customer", "Hi, I'm Dana Reyes. I lead security operations at Northstar. We use Palo Alto firewalls and collect about forty five gigabytes of logs a day. When an analyst needs firewall evidence, we ask the network team to export it and usually wait six hours."),
        ("you", "What happens to the investigation while your analysts are waiting?"),
        ("customer", "They switch to other alerts, then spend more time getting back into the investigation. The delays put our incident response target at risk."),
        ("you", "How does that affect you and the team?"),
        ("customer", "My analysts sometimes work late to catch up. I want them to spend that time improving detections, and I need to show leadership that we are making progress."),
        ("you", "If analysts could find that evidence directly, how would you judge whether the change was worthwhile?"),
        ("customer", "We would measure investigation time and the coordination we no longer need. How does data ingestion differ between Splunk Cloud and Splunk Enterprise?")
    ]
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 530), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Practice Discovery"; w.isReleasedWhenClosed = false; w.delegate = self
            w.contentView = NSHostingView(rootView: PracticeDiscoveryView(model: self)); w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    nonisolated func windowWillClose(_ notification: Notification) { Task { @MainActor in self.stop() } }
    func saveDemoReview() {
        guard active, watching, demoComplete, let root else { return }
        do {
            let html = try PracticeDemoReview.render(Data(contentsOf: root.appendingPathComponent("sessions/latest.json")))
            let panel = NSSavePanel(); panel.allowedFileTypes = ["html"]
            panel.nameFieldStringValue = "SalesPilot Fictional Demo Review.html"
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try html.write(to: destination, atomically: true, encoding: .utf8)
            failure = nil; status = "Demo review saved. It opens offline; source links need internet."
        } catch { failure = error.localizedDescription }
    }
    func toggleDemoPause() {
        guard active, watching, !demoComplete else { return }
        demoPaused.toggle()
    }
    func start(watch: Bool) {
        guard !active, !LiveState.shared.listening, !LiveState.shared.starting, !LiveState.shared.finishing else { failure = "End the current call before starting practice."; return }
        guard LiveCoach.nodePath() != nil, Transcriber.findModel(modelSize: modelSize) != nil else { failure = "Install Node and an approved Whisper transcription model before practice."; return }
        demoPaused = false; demoComplete = false
        processing = UserDefaults.standard.string(forKey: "callProcessingMode") ?? "circuit"
        do {
            let dir = WorkspacePaths.root.appendingPathComponent("sessions/practice/" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("sessions"), withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try "People: Dana Reyes — customer, security operations director\nContext: FICTIONAL PRACTICE ONLY. Northstar is invented. Do not use real customer information.\n".write(to: dir.appendingPathComponent("sessions/prep.txt"), atomically: true, encoding: .utf8)
            root = dir; WorkspacePaths.practiceRoot = dir
            try CaptureJournal.begin()
        } catch { WorkspacePaths.practiceRoot = nil; root = nil; failure = "Could not create an isolated practice session."; return }
        generation = UUID(); sessionGeneration = UUID(); inputProgress.reset(); muted = false; active = true; watching = watch; busy = true; failure = nil; conversation = []; revealed = []
        SessionStore.showingExample = false; SessionStore.reviewSelection = nil; SessionStore.showingReady = false
        LiveState.shared.turns = []; LiveState.shared.engineError = nil; LiveState.shared.listening = true
        LiveState.shared.customerName = nil; LiveState.shared.customerCount = 0; LiveState.shared.whoByText = [:]
        LiveState.shared.youCommitted = ""; LiveState.shared.youProvisional = ""; LiveState.shared.custCommitted = ""; LiveState.shared.custProvisional = ""
        LiveState.shared.answer = nil; LiveState.shared.answerSources = nil; LiveState.shared.answerStatus = nil
        LiveState.shared.nextQuestion = nil; LiveState.shared.nextQuestionTarget = nil; LiveState.shared.audioNotice = nil; LiveState.shared.customerAvailable = true
        NotificationCenter.default.post(name: .clearSession, object: nil)
        status = "Preparing practice…"
        ReviewWindow.shared.show()
        let epoch = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Authorize before starting the short coaching deadline. The app cache is
                // then shared with the coach and customer through their private stdin pipes.
                if self.processing != "local", ProviderCredentials.isConfigured {
                    self.status = "Authorizing Cisco practice…"
                    do { _ = try await Task.detached { try ProviderCredentials.data() }.value }
                    catch { try self.check(epoch); throw NSError(domain: "PracticeReply", code: 1) }
                    try self.check(epoch)
                }
                LiveCoach.shared.start(framework: Coaching.selectedID)
                if watch {
                    for (side, text) in self.demo {
                        try self.check(epoch)
                        while self.demoPaused {
                            self.status = "Demo paused between turns. Review the workspace, then resume."
                            try await Task.sleep(nanoseconds: 200_000_000)
                            try self.check(epoch)
                        }
                        try await self.speak(text, side: side, epoch: epoch)
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                    self.demoComplete = true; self.demoPaused = false
                    self.status = "Demo complete. Review the workspace, then end practice."; self.busy = false
                } else {
                    let granted = await withCheckedContinuation { continuation in
                        AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
                    }
                    try self.check(epoch)
                    guard granted else { self.busy = false; self.muted = true; self.failure = "Allow microphone access in macOS Settings, then end and restart practice. Watch a demo uses no microphone."; return }
                    guard let root = self.root else { throw CancellationError() }
                    let session = self.sessionGeneration
                    self.microphoneName = AudioDeviceManager.listInputDevices().first(where: { $0.isDefault })?.name ?? "System default microphone"
                    let audio = PracticeAudio(root: root, began: { [weak self] in
                        Task { @MainActor in guard let self, self.active, self.sessionGeneration == session, !self.muted else { return }; self.speechBegan() }
                    }, ended: { [weak self] url, start, end in
                        Task { @MainActor in
                            guard let self, self.active, self.sessionGeneration == session, !self.muted else { try? FileManager.default.removeItem(at: url); return }
                            self.sendTurn(url: url, start: start, end: end)
                        }
                    }, failed: { [weak self] in
                        Task { @MainActor in guard let self, self.active, self.sessionGeneration == session else { return }; self.captureFailed(); self.failure = "Microphone capture stopped. End practice and check your audio device before restarting."; self.status = "Microphone unavailable." }
                    }, level: { [weak self] db in
                        Task { @MainActor in guard let self, self.active, self.sessionGeneration == session, !self.muted else { return }; self.meter.level = min(1, max(0, (db + 80) / 55)) }
                    })
                    self.handsFree = audio
                    do { try audio.start() } catch {
                        let e = error as NSError
                        let diagnostic = "audio startup (" + audio.startupStage + "): " + e.domain + " " + String(e.code)
                        try? diagnostic.write(to: root.appendingPathComponent("audio-diagnostic.txt"), atomically: true, encoding: .utf8)
                        audio.stop(); self.handsFree = nil; self.muted = true; throw error
                    }
                    try await self.speak(self.intro, side: "customer", epoch: epoch)
                    self.revealed = ["intro"]; self.busy = false; self.status = "Listening. Ask Dana a question naturally."
                }
            } catch { self.handle(error, epoch: epoch) }
        }
    }
    private var modelSize: String { Transcriber.modelExists(modelSize: "small.en") ? "small.en" : Config.load().modelSize }
    private func check(_ epoch: UUID) throws { if !active || generation != epoch || Task.isCancelled { throw CancellationError() } }
    private func handle(_ error: Error, epoch: UUID) {
        guard active, generation == epoch else { return }
        busy = false; recording = false; if !watching, handsFree != nil, !muted { handsFree?.interrupt() }
        failure = (error as NSError).domain == "PracticeReply" ? "Dana couldn't reach the configured AI provider. If Cisco access needs reconnecting, end practice and use More → Privacy & local data → Connect Cisco." : "Practice could not complete that turn. Check audio/model access. End practice and restart if needed."; status = (error as NSError).domain == "PracticeReply" && handsFree == nil ? "Provider unavailable. End practice and check Cisco access before restarting." : watching ? "Demo interrupted. End practice to restart." : (handsFree == nil ? "Audio unavailable. End practice and check your microphone before restarting." : "Listening. Please try again.")
    }
    private func captureFailed() {
        cancelInput()
        generation = UUID(); task?.cancel(); task = nil
        if child?.isRunning == true { child?.terminate() }; child = nil
        handsFree?.stop(); handsFree = nil; muted = true; busy = false; recording = false
    }
    private func speechBegan() {
        guard active, !watching, !muted else { return }
        // Invalidate the prior reply before touching playback: late provider/ASR results cannot speak.
        generation = UUID(); task?.cancel(); task = nil
        if child?.isRunning == true { child?.terminate() }; child = nil
        handsFree?.interrupt()
        busy = false; recording = true; failure = nil; status = "Listening to you…"
    }
    func toggleMute() {
        guard active, !watching, handsFree != nil else { return }
        muted.toggle(); meter.level = 0; handsFree?.setMuted(muted)
        if muted {
            cancelInput()
            generation = UUID(); task?.cancel(); task = nil
            if child?.isRunning == true { child?.terminate() }; child = nil
            handsFree?.interrupt(); recording = false; busy = false; status = "Microphone muted. Resume when ready."
        } else { failure = nil; status = "Listening. Ask Dana a question naturally." }
    }
    private func sendTurn(url: URL, start: Double, end: Double) {
        guard active, !watching, !muted else { try? FileManager.default.removeItem(at: url); return }
        recording = false
        guard inputQueue.count < 4 else {
            try? FileManager.default.removeItem(at: url); toggleMute()
            failure = "Speech arrived faster than practice could transcribe it. Your microphone is muted and unfinished audio was discarded. Resume and repeat your last question; earlier transcript is preserved."; return
        }
        inputQueue.append((url, start, end)); drainInput()
    }
    private func drainInput() {
        guard inputTask == nil, !inputQueue.isEmpty else { return }
        let (url, start, end) = inputQueue.removeFirst()
        let session = inputGeneration
        busy = true
        inputTask = Task {
            let wav = url.deletingPathExtension().appendingPathExtension("wav")
            defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: wav) }
            do {
                let convert = Process(); convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                convert.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", url.path, wav.path]
                _ = try await execute(convert, epoch: session, input: true)
                let text = try await transcribe(wav, epoch: session, input: true)
                if !text.isEmpty {
                    inputProgress.accept(text)
                    failure = nil
                    LiveState.shared.turns.append(LiveTurn(speaker: "you", text: text, startedAt: start))
                    let voiceFile = wav.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
                    try FileManager.default.copyItem(at: wav, to: voiceFile)
                    LiveCoach.shared.feed(speaker: "you", text: text, wav: voiceFile.path, startedAt: start, endedAt: end)
                    conversation.append(["role": "user", "text": text])
                }
                guard active, inputGeneration == session else { return }
                inputTask = nil
                if !inputQueue.isEmpty { drainInput() }
                else if inputProgress.takeReply(recording: recording, muted: muted, queued: false) { replyToCustomer() }
                else {
                    busy = false
                    if !muted, !recording {
                        status = text.isEmpty ? "Audio detected, but no clear words. Please repeat your question." : "Listening. Continue whenever you're ready."
                    }
                }
            } catch {
                guard active, inputGeneration == session else { return }
                inputTask = nil; busy = false
                failure = "That speech could not be transcribed. Please repeat your question; your earlier transcript is preserved."; status = muted ? "Microphone muted." : "Transcription failed. Please try again."
                if !inputQueue.isEmpty { drainInput() }
            }
        }
    }
    private func replyToCustomer() {
        let epoch = generation
        busy = true; status = "Dana is thinking…"
        task = Task {
            do {
                let reply: (text: String, ids: [String])
                do { reply = try await customerReply(epoch: epoch) }
                catch { try check(epoch); throw NSError(domain: "PracticeReply", code: 1) }
                try await speak(reply.text, side: "customer", epoch: epoch)
                revealed += reply.ids
                busy = false; status = "Listening. Continue whenever you're ready."
            } catch { handle(error, epoch: epoch) }
        }
    }
    private func transcribe(_ url: URL, epoch: UUID, input: Bool = false) async throws -> String {
        status = "Transcribing audio locally…"
        let size = modelSize
        let text = try await Task.detached(priority: .userInitiated) {
            try Transcriber(modelSize: size, language: "en", whisperPrompt: Transcriber.salesVocabulary + " Dana Reyes. Northstar.", threads: 4, beamSize: 5).transcribe(audioURL: url)
        }.value
        try checkAudioEpoch(epoch, input: input); return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func checkAudioEpoch(_ epoch: UUID, input: Bool) throws {
        if input { guard active, inputGeneration == epoch, !muted, !Task.isCancelled else { throw CancellationError() } }
        else { try check(epoch) }
    }
    private func execute(_ p: Process, epoch: UUID, input: Bool = false) async throws -> Data {
        let output = Pipe(); p.standardOutput = output; p.standardError = FileHandle.nullDevice
        if input { inputChild = p } else { child = p }; try p.run()
        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            DispatchQueue.global().async {
                let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: deadline)
                let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); deadline.cancel(); continuation.resume(returning: data)
            }
        }
        try checkAudioEpoch(epoch, input: input); if input { inputChild = nil } else { child = nil }
        guard p.terminationStatus == 0 else { throw NSError(domain: "PracticeProcess", code: Int(p.terminationStatus)) }
        return data
    }
    private func customerReply(epoch: UUID) async throws -> (text: String, ids: [String]) {
        guard let node = LiveCoach.nodePath() else { throw NSError(domain: "PracticeNode", code: 1) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: node); p.arguments = [WorkspacePaths.engine.appendingPathComponent("practice-customer.mjs").path]
        var env = ProcessInfo.processInfo.environment
        env["SALESPILOT_CREDENTIAL_INPUT"] = "stdin"; env["PROVIDER"] = "ollama"
        env.removeValue(forKey: "SALESPILOT_OFFLINE")
        if processing != "local" { env.removeValue(forKey: "COACH_LOCAL"); env.removeValue(forKey: "SALESPILOT_LOCAL_ONLY") }
        if processing == "local" { env["SALESPILOT_LOCAL_ONLY"] = "1"; env["COACH_LOCAL"] = "1" }
        p.environment = env
        let input = Pipe(); p.standardInput = input
        let history = conversation, facts = revealed, local = processing == "local"
        let payload = try await Task.detached {
            let credentials: Any = !local && ProviderCredentials.isConfigured ? ((try? ProviderCredentials.data()).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]) : [:]
            var data = try JSONSerialization.data(withJSONObject: ["cmd": "provider-credentials", "credentials": credentials]); data.append(10)
            data.append(try JSONSerialization.data(withJSONObject: ["cmd": "respond", "turns": history, "revealed": facts])); data.append(10); return data
        }.value
        try check(epoch)
        // Write on a background queue once the reader exists; no secret is passed in argv/env.
        DispatchQueue.global().async { try? input.fileHandleForWriting.write(contentsOf: payload); try? input.fileHandleForWriting.close() }
        let data = try await execute(p, epoch: epoch)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reply = object["text"] as? String, !reply.isEmpty else { throw NSError(domain: "PracticeReply", code: 1) }
        return (reply, object["ids"] as? [String] ?? [])
    }
    private func speak(_ text: String, side: String, epoch: UUID) async throws {
        try check(epoch)
        guard let root else { throw CancellationError() }
        status = side == "customer" ? "Fictional customer is speaking…" : "Demo SE is speaking…"
        let base = root.appendingPathComponent(UUID().uuidString)
        let aiff = base.appendingPathExtension("aiff"), wav = base.appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: aiff); try? FileManager.default.removeItem(at: wav) }
        let say = Process(); say.executableURL = URL(fileURLWithPath: "/usr/bin/say"); say.arguments = ["-v", side == "customer" ? "Samantha" : "Daniel", "-o", aiff.path, text]
        _ = try await execute(say, epoch: epoch)
        let convert = Process(); convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert"); convert.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path]
        _ = try await execute(convert, epoch: epoch)
        let audio = try AVAudioPlayer(contentsOf: wav)
        let start = Date().timeIntervalSince1970
        if let handsFree, !watching {
            let playback = try handsFree.play(wav)
            while handsFree.isPlaying(playback) {
                try await Task.sleep(nanoseconds: 50_000_000)
                try check(epoch)
            }
            try check(epoch)
        } else {
            player = audio
            guard audio.play() else { throw NSError(domain: "PracticePlayback", code: 1) }
            try await Task.sleep(nanoseconds: UInt64((audio.duration + 0.2) * 1_000_000_000))
            try check(epoch); player = nil
        }
        let recognized = try await transcribe(wav, epoch: epoch)
        guard !recognized.isEmpty else { throw NSError(domain: "PracticeASR", code: 1) }
        // Generated audio goes through Whisper, never directly injected as a transcript.
        LiveState.shared.turns.append(LiveTurn(speaker: side, text: recognized, startedAt: start))
        let voiceFile = root.appendingPathComponent(UUID().uuidString + ".wav")
        try FileManager.default.copyItem(at: wav, to: voiceFile)
        LiveCoach.shared.feed(speaker: side, text: recognized, wav: voiceFile.path, startedAt: start, endedAt: start + audio.duration)
        conversation.append(["role": side == "customer" ? "assistant" : "user", "text": recognized])
    }
    private func cancelInput() {
        inputGeneration = UUID(); inputProgress.reset()
        inputTask?.cancel(); inputTask = nil
        if inputChild?.isRunning == true { inputChild?.terminate() }; inputChild = nil
        for (url, _, _) in inputQueue { try? FileManager.default.removeItem(at: url) }; inputQueue = []
    }
    func stop() {
        guard active else { return }
        generation = UUID(); sessionGeneration = UUID(); cancelInput(); task?.cancel(); task = nil
        handsFree?.stop(); handsFree = nil; muted = false; meter.level = 0; player?.stop(); player = nil; if child?.isRunning == true { child?.terminate() }; child = nil
        LiveCoach.shared.stop()
        demoPaused = false; demoComplete = false
        active = false; recording = false; busy = false; watching = false; failure = nil
        LiveState.shared.listening = false; LiveState.shared.starting = false; LiveState.shared.turns = []; LiveState.shared.engineError = nil
        if let root, let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for file in files where ["wav", "aiff", "caf"].contains(file.pathExtension) { try? FileManager.default.removeItem(at: file) }
        }
        WorkspacePaths.practiceRoot = nil; root = nil
        SessionStore.showingReady = true; SessionStore.reviewingLatest = false; status = "Practice ended. Customer call data is unchanged."
        NotificationCenter.default.post(name: .reloadSession, object: nil)
    }
}

struct PracticeDiscoveryView: View {
    @ObservedObject var model: PracticeDiscovery
    @State private var confirmed = false
    @AppStorage("callProcessingMode") private var processing = "circuit"
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Label("Practice Discovery", systemImage: "person.wave.2").font(.title2.bold())
            Text("Ask better questions. Follow the customer's story. See what you uncover.").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("MEET YOUR FICTIONAL CUSTOMER").font(.caption.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
                Text("Dana Reyes · Security operations leader").font(.headline)
                Text("Her team waits for firewall evidence during investigations. Discover what that means for the business and the people doing the work.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(SalesPilotStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            Text(processing == "local" ? "Processing: Local only. An installed local model is needed for AI replies; public documentation searches are blocked." : "Processing: Cisco + docs. Practice text may reach your configured Cisco provider; product questions may query public documentation. Local model fallback may be used.").font(.callout)
            if !model.active {
                Toggle("Use fictional information only. I understand the processing choice above.", isOn: $confirmed).font(.callout)
                VStack(alignment: .leading, spacing: 8) {
                    Button("Interactive practice") { model.start(watch: false) }.buttonStyle(.borderedProminent).tint(SalesPilotStyle.buttonFill).disabled(!confirmed)
                    Text("You play the SE; Dana is an AI-generated fictional customer. Your audience can watch without role-playing. Talk naturally; Dana replies after you finish. You can interrupt her. Your microphone stays active until you mute it or end practice. A headset is recommended.").font(.callout).foregroundStyle(.secondary)
                    Divider().padding(.vertical, 6)
                    Button("Watch a demo") { model.start(watch: true) }.buttonStyle(.bordered).disabled(!confirmed)
                    Text("Present one fictional discovery story: technical pain, business risk, personal impact and a desired outcome. Generated voices are transcribed live; pause between turns to discuss the coaching and notes. This does not test your microphone or meeting-audio capture.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Label(model.watching ? "Fictional audio demo" : "Interactive fictional practice", systemImage: "sparkles").foregroundStyle(SalesPilotStyle.accent)
                if !model.watching {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Microphone: " + model.microphoneName).font(.caption).foregroundStyle(.secondary)
                        PracticeMicrophoneLevel(meter: model.meter)
                        Text(model.muted ? "Muted" : "The meter should move when you speak. Practice uses your Mac’s current system input.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.status).accessibilityLabel("Practice status: " + model.status)
                HStack {
                    if model.watching && model.demoComplete { Button("Save demo review") { model.saveDemoReview() } }
                    if model.watching { Button(model.demoPaused ? "Resume demo" : "Pause after this turn") { model.toggleDemoPause() }.disabled(model.demoComplete) }
                    if !model.watching { Button(model.muted ? "Resume microphone" : "Mute microphone") { model.toggleMute() }.disabled(!model.microphoneAvailable) }
                    Button("Open workspace") { ReviewWindow.shared.show() }
                    Spacer()
                    Button("End practice") { model.stop() }
                }
            }
            if let error = model.failure { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            DisclosureGroup("Audio, privacy & saved practice") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Speech is transcribed locally. Generated voices are played and their audio files are transcribed by Whisper; this does not test Webex system-audio capture. Interactive practice uses voice-processed microphone audio, waits through brief pauses, and ends a turn after sustained silence or 60 seconds. Use a headset to reduce residual echo. Microphone capture continues during replies to detect interruptions.")
                    Text("Practice uses separate files and no saved customer prep or reference library. The AI selects from a bounded fictional scenario and cannot read coaching suggestions. Results depend on your configured models and available sources.")
                    Text("Practice files stay under sessions/practice for local review and follow organizational retention requirements. Temporary audio is removed after use. End practice before a customer call; closing this window ends practice. Interrupting stops the reply; only completed customer replies are included in the transcript. Mute cancels the current reply and discards unfinished microphone audio.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
        .frame(minWidth: 480, minHeight: 450)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

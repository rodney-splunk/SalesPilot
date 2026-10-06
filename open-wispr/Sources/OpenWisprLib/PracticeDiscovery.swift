import AppKit
import SwiftUI
import AVFoundation

/// Fictional practice owns its audio and session, never the global system-audio tap.
@MainActor final class PracticeDiscovery: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PracticeDiscovery()
    @Published private(set) var active = false
    @Published private(set) var busy = false
    @Published private(set) var recording = false
    @Published private(set) var status = "Choose a practice option."
    @Published private(set) var failure: String?
    @Published private(set) var watching = false
    private var window: NSWindow?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var child: Process?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var microphoneLimit: Timer?
    private var audioURL: URL?
    private var recordingStart = Date()
    private var peakLevel: Float = -160
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
    func start(watch: Bool) {
        guard !active, !LiveState.shared.listening, !LiveState.shared.starting, !LiveState.shared.finishing else { failure = "End the current call before starting practice."; return }
        guard LiveCoach.nodePath() != nil, Transcriber.findModel(modelSize: modelSize) != nil else { failure = "Install Node and an approved Whisper transcription model before practice."; return }
        processing = UserDefaults.standard.string(forKey: "callProcessingMode") ?? "circuit"
        do {
            let dir = WorkspacePaths.root.appendingPathComponent("sessions/practice/" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("sessions"), withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try "People: Dana Reyes — customer, security operations director\nContext: FICTIONAL PRACTICE ONLY. Northstar is invented. Do not use real customer information.\n".write(to: dir.appendingPathComponent("sessions/prep.txt"), atomically: true, encoding: .utf8)
            root = dir; WorkspacePaths.practiceRoot = dir
            try CaptureJournal.begin()
        } catch { WorkspacePaths.practiceRoot = nil; root = nil; failure = "Could not create an isolated practice session."; return }
        generation = UUID(); active = true; watching = watch; busy = true; failure = nil; conversation = []; revealed = []
        SessionStore.showingExample = false; SessionStore.reviewSelection = nil; SessionStore.showingReady = false
        LiveState.shared.turns = []; LiveState.shared.engineError = nil; LiveState.shared.listening = true
        LiveState.shared.customerName = nil; LiveState.shared.customerCount = 0; LiveState.shared.whoByText = [:]
        LiveState.shared.youCommitted = ""; LiveState.shared.youProvisional = ""; LiveState.shared.custCommitted = ""; LiveState.shared.custProvisional = ""
        LiveState.shared.answer = nil; LiveState.shared.answerSources = nil; LiveState.shared.answerStatus = nil
        LiveState.shared.nextQuestion = nil; LiveState.shared.nextQuestionTarget = nil; LiveState.shared.audioNotice = nil; LiveState.shared.customerAvailable = true
        NotificationCenter.default.post(name: .clearSession, object: nil)
        LiveCoach.shared.start(framework: Coaching.selectedID)
        ReviewWindow.shared.show()
        let epoch = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if watch {
                    for (side, text) in self.demo {
                        try self.check(epoch)
                        try await self.speak(text, side: side, epoch: epoch)
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                    self.status = "Demo complete. Review the workspace, then end practice."; self.busy = false
                } else {
                    try await self.speak(self.intro, side: "customer", epoch: epoch)
                    self.revealed = ["intro"]; self.busy = false; self.status = "Your turn. Click Speak, ask a question, then Send turn."
                }
            } catch { self.handle(error, epoch: epoch) }
        }
    }
    private var modelSize: String { Transcriber.modelExists(modelSize: "small.en") ? "small.en" : Config.load().modelSize }
    private func check(_ epoch: UUID) throws { if !active || generation != epoch || Task.isCancelled { throw CancellationError() } }
    private func handle(_ error: Error, epoch: UUID) {
        guard active, generation == epoch else { return }
        busy = false; recording = false; failure = "Practice could not complete that turn. Check audio/model access. End practice and restart if needed."; status = watching ? "Demo interrupted. End practice to restart." : "Click Speak to try another turn."
    }
    func beginTurn() {
        guard active, !watching, !busy, !recording else { return }
        failure = nil
        let epoch = generation
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard self.active, self.generation == epoch, !self.busy, !self.recording else { return }
                guard granted else { self.failure = "Microphone access is required for interactive practice. Watch a demo uses no microphone."; return }
                do {
                    let url = self.root!.appendingPathComponent(UUID().uuidString + ".wav")
                    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
                    let r = try AVAudioRecorder(url: url, settings: settings)
                    guard r.record() else { throw NSError(domain: "PracticeAudio", code: 1) }
                    r.isMeteringEnabled = true; self.peakLevel = -160
                    self.recorder = r; self.audioURL = url; self.recordingStart = Date(); self.recording = true; self.status = "Listening to you. Click Send turn when finished."
                    self.microphoneLimit = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in Task { @MainActor in
                        guard self.recording else { return }; self.recorder?.updateMeters(); self.peakLevel = max(self.peakLevel, self.recorder?.peakPower(forChannel: 0) ?? -160)
                        if Date().timeIntervalSince(self.recordingStart) >= 60 { self.sendTurn() }
                    } }
                } catch { self.handle(error, epoch: epoch) }
            }
        }
    }
    func sendTurn() {
        guard active, recording, let url = audioURL else { return }
        microphoneLimit?.invalidate(); microphoneLimit = nil
        recorder?.updateMeters(); peakLevel = max(peakLevel, recorder?.peakPower(forChannel: 0) ?? -160)
        recorder?.stop(); recorder = nil; recording = false
        guard peakLevel > -45 else { try? FileManager.default.removeItem(at: url); failure = "No clear microphone audio was detected. Check the input device and try again."; return }
        busy = true
        let epoch = generation, start = recordingStart.timeIntervalSince1970, end = Date().timeIntervalSince1970
        task = Task {
            do {
                let text = try await transcribe(url, epoch: epoch)
                guard text.split(separator: " ").count >= 2 else { failure = "No clear question was captured. Click Speak to try again."; busy = false; return }
                try check(epoch)
                LiveState.shared.turns.append(LiveTurn(speaker: "you", text: text, startedAt: start))
                let voiceFile = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
                try FileManager.default.copyItem(at: url, to: voiceFile)
                LiveCoach.shared.feed(speaker: "you", text: text, wav: voiceFile.path, startedAt: start, endedAt: end)
                conversation.append(["role": "user", "text": text]); status = "AI customer is thinking…"
                let reply = try await customerReply(epoch: epoch)
                try await speak(reply, side: "customer", epoch: epoch)
                busy = false; status = "Your turn. Click Speak to continue."
            } catch { handle(error, epoch: epoch) }
            try? FileManager.default.removeItem(at: url)
        }
    }
    private func transcribe(_ url: URL, epoch: UUID) async throws -> String {
        status = "Transcribing audio locally…"
        let size = modelSize
        let text = try await Task.detached(priority: .userInitiated) {
            try Transcriber(modelSize: size, language: "en", whisperPrompt: Transcriber.salesVocabulary + " Dana Reyes. Northstar.", threads: 4, beamSize: 5).transcribe(audioURL: url)
        }.value
        try check(epoch); return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func execute(_ p: Process, epoch: UUID) async throws -> Data {
        let output = Pipe(); p.standardOutput = output; p.standardError = FileHandle.nullDevice
        child = p; try p.run()
        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            DispatchQueue.global().async {
                let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: deadline)
                let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); deadline.cancel(); continuation.resume(returning: data)
            }
        }
        try check(epoch); child = nil
        guard p.terminationStatus == 0 else { throw NSError(domain: "PracticeProcess", code: Int(p.terminationStatus)) }
        return data
    }
    private func customerReply(epoch: UUID) async throws -> String {
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
        revealed += object["ids"] as? [String] ?? []; return reply
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
        let audio = try AVAudioPlayer(contentsOf: wav); player = audio
        guard audio.play() else { throw NSError(domain: "PracticePlayback", code: 1) }
        let start = Date().timeIntervalSince1970
        try await Task.sleep(nanoseconds: UInt64((audio.duration + 0.2) * 1_000_000_000))
        try check(epoch); player = nil
        let recognized = try await transcribe(wav, epoch: epoch)
        guard !recognized.isEmpty else { throw NSError(domain: "PracticeASR", code: 1) }
        // Generated audio goes through Whisper, never directly injected as a transcript.
        LiveState.shared.turns.append(LiveTurn(speaker: side, text: recognized, startedAt: start))
        let voiceFile = root.appendingPathComponent(UUID().uuidString + ".wav")
        try FileManager.default.copyItem(at: wav, to: voiceFile)
        LiveCoach.shared.feed(speaker: side, text: recognized, wav: voiceFile.path, startedAt: start, endedAt: start + audio.duration)
        conversation.append(["role": side == "customer" ? "assistant" : "user", "text": recognized])
    }
    func stop() {
        guard active else { return }
        generation = UUID(); task?.cancel(); task = nil; microphoneLimit?.invalidate(); microphoneLimit = nil
        recorder?.stop(); recorder = nil; player?.stop(); player = nil; if child?.isRunning == true { child?.terminate() }; child = nil
        LiveCoach.shared.stop()
        if let url = audioURL { try? FileManager.default.removeItem(at: url) }; audioURL = nil
        active = false; recording = false; busy = false; watching = false
        LiveState.shared.listening = false; LiveState.shared.starting = false; LiveState.shared.turns = []
        if let root, let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for file in files where ["wav", "aiff"].contains(file.pathExtension) { try? FileManager.default.removeItem(at: file) }
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
                    Text("You speak; Dana replies aloud. Click Speak to record your question, then Send turn. No microphone capture while Dana speaks.").font(.callout).foregroundStyle(.secondary)
                    Divider().padding(.vertical, 6)
                    Button("Watch a demo") { model.start(watch: true) }.buttonStyle(.bordered).disabled(!confirmed)
                    Text("A prepared conversation plays both sides while SalesPilot transcribes, takes notes and coaches. No microphone capture.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Label(model.watching ? "Fictional audio demo" : "Interactive fictional practice", systemImage: "sparkles").foregroundStyle(SalesPilotStyle.accent)
                Text(model.status).accessibilityLabel("Practice status: " + model.status)
                HStack {
                    if !model.watching { Button(model.recording ? "Send turn" : "Speak") { model.recording ? model.sendTurn() : model.beginTurn() }.disabled(model.busy) }
                    Button("Open workspace") { ReviewWindow.shared.show() }
                    Spacer()
                    Button("End practice") { model.stop() }
                }
            }
            if let error = model.failure { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            DisclosureGroup("Audio, privacy & saved practice") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Speech is transcribed locally. Generated voices are played and their audio files are transcribed by Whisper; this does not test Webex system-audio capture. Interactive recording is limited to 60 seconds per turn. Use a headset for comfortable listening.")
                    Text("Practice uses separate files and no saved customer prep or reference library. The AI selects from a bounded fictional scenario and cannot read coaching suggestions. Results depend on your configured models and available sources.")
                    Text("Practice files stay under sessions/practice for local review and follow organizational retention requirements. Temporary audio is removed after use. End practice before a customer call; closing this window ends practice. Full-duplex interruption is not supported.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
        .frame(minWidth: 480, minHeight: 450)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

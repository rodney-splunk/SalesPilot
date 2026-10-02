// LiveHUD.swift — M3 live copilot: dual-source, speaker-labeled.
// Mic  → "You"  (StreamingMicTranscriber capturesMic).
// System audio (process tap) → "Customer".
// Both stream into LiveState (shown in the HUD + the Discovery session window). Finalized turns
// feed the coaching pipeline (customer turns drive coverage + SAY NEXT).

import SwiftUI
import AppKit
import Combine

struct LiveTurn: Identifiable { let id = UUID(); let speaker: String; var text: String; var startedAt: Double = 0 }

final class LiveState: ObservableObject {
    static let shared = LiveState()
    @Published var turns: [LiveTurn] = []
    @Published var youCommitted = "";  @Published var youProvisional = ""
    @Published var custCommitted = ""; @Published var custProvisional = ""
    @Published var listening = false
    /// True from the moment Start is pressed until audio is actually flowing. Bringing up the audio
    /// engine and the system-audio tap takes a couple of seconds, and without this the UI sat on
    /// "Paused" the whole time, so pressing Start looked like it had done nothing.
    @Published var starting = false
    @Published var finishing = false
    @Published var audioNotice: String? = nil
    @Published var customerAvailable = false   // did the system-audio tap start?
    @Published var customerName: String? = nil // filled once the customer says who they are
    @Published var customerCount: Int = 0      // people on the customer side
    /// Who the engine resolved for each customer line, keyed by the line. Lets the HUD name the
    /// right person on a multi-person call instead of labelling everyone "CUST".
    @Published var whoByText: [String: String] = [:]
    @Published var engineError: String? = nil  // set when the coaching model is unreachable
    @Published var answer: String? = nil        // live doc/Slack answer to the customer's question
    @Published var nextQuestion: String? = nil
    @Published var nextQuestionTarget: String? = nil
    @Published var answerSources: String? = nil
    @Published var answerStatus: String? = nil
    var presentation: CallPresentation { CallPresentation(listening: listening, starting: starting, finishing: finishing) }
}

struct LiveHUDView: View {
    @ObservedObject var state: LiveState
    @State private var showTranscript = false
    private var panelHeight: CGFloat { (state.answer == nil ? 270 : 410) + (showTranscript ? 170 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(state.listening ? Color.red : (state.starting ? Color.orange : Color.secondary)).frame(width: 8, height: 8)
                Text(state.presentation.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(state.customerAvailable ? "you + customer" : "you only")
                    .font(.system(size: 10, weight: state.customerAvailable ? .regular : .bold))
                    .foregroundStyle(state.customerAvailable ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.red))
                Button("End call") { LiveHUD.shared.stop() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .disabled(!state.listening).accessibilityLabel("End call")
            }
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
            if let notice = state.audioNotice {
                Label(notice, systemImage: "ear.badge.waveform").font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let e = state.engineError {
                Text("⚠︎ \(e)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let a = state.answer {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.answerStatus == "unverified" ? "◆ FOLLOW UP" : (state.answerStatus == "searching" ? "◆ SEARCHING SOURCES" : "◆ LIVE ANSWER"))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(SalesPilotStyle.accent)
                    Text(a).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    if let src = state.answerSources { Text(src).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 7) {
                Label("NEXT MOVE", systemImage: "sparkle").font(.system(size: 10, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                Text(state.nextQuestion ?? "Listen for their next thought.")
                    .font(.system(size: 17, weight: .medium, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                if let target = state.nextQuestionTarget { Text(target).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(SalesPilotStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(showTranscript ? "Hide transcript" : "Show transcript") { showTranscript.toggle() }.buttonStyle(.plain)
                Spacer()
                Button("Open workspace") { ReviewWindow.shared.show() }.accessibilityLabel("Open workspace").buttonStyle(.plain)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if showTranscript {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.turns.suffix(6)) { turn in
                        line(turn.speaker, turn.text, committed: true, startedAt: turn.startedAt)
                    }
                    if !state.youCommitted.isEmpty || !state.youProvisional.isEmpty {
                        liveLine("you", state.youCommitted, state.youProvisional)
                    }
                    if !state.custCommitted.isEmpty || !state.custProvisional.isEmpty {
                        liveLine("customer", state.custCommitted, state.custProvisional)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 140)
            }
        }
        .padding(16).frame(width: 380, height: panelHeight, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        .onChange(of: panelHeight) { height in LiveHUD.shared.resizePanel(height: height) }
    }

    private func speakerLabel(_ s: String, text: String = "", startedAt: Double? = nil) -> some View {
        // Prefer the per-line answer the engine resolved. Only fall back to a generic label when
        // several people are known AND this particular line has no answer.
        let resolved = (state.whoByText[SpeakerLookup.key(text: text, startedAt: startedAt, mic: s == "you")] ?? state.whoByText[text])?.uppercased()
        let fallback = state.customerCount > 1 ? "CUST" : (state.customerName?.uppercased() ?? "CUST")
        let label = resolved ?? (s == "you" ? (state.whoByText[SpeakerLookup.microphoneKey] ?? "You").uppercased() : "UNCONFIRMED")
        return Text(label).font(.system(size: 9, weight: .bold))
            .foregroundStyle(s == "you" ? Color.accentColor : Color.orange)
            .fixedSize(horizontal: false, vertical: true).minimumScaleFactor(0.75).frame(width: 65, alignment: .leading)
    }
    private func line(_ speaker: String, _ text: String, committed: Bool, startedAt: Double? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            speakerLabel(speaker, text: text, startedAt: startedAt)
            Text(text).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.9))
        }
    }
    private func liveLine(_ speaker: String, _ committed: String, _ provisional: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            speakerLabel(speaker)
            (Text(committed).foregroundColor(.primary) + Text(committed.isEmpty ? "" : " ") + Text(provisional).foregroundColor(.secondary))
                .font(.system(size: 13, weight: .medium))
        }
    }
}

final class LiveHUD {
    static let shared = LiveHUD()
    let state = LiveState.shared
    private(set) var isRunning = false
    private var finishing = false
    private var panel: NSPanel?
    private var youT: StreamingMicTranscriber?
    private var custT: StreamingMicTranscriber?
    private var systemCapture: AnyObject?
    private var silenceWatchdog: Timer?

    func toggle() { isRunning ? stop() : start() }

    func start(consentConfirmed: Bool = false) {
        guard !isRunning && !finishing else { return }
        if youT != nil || custT != nil || systemCapture != nil {
            stop()
            return
        }
        guard consentConfirmed else { CallConsentWindow.shared.show(); return }
        do {
            try CaptureJournal.recover(session: WorkspacePaths.session)
            try CallArchive.preserveCurrent(session: WorkspacePaths.session, history: SessionCapture.sessionsDir.appendingPathComponent("history", isDirectory: true))
            try CaptureJournal.begin()
            ComplianceAudit.record("consent-confirmed", fields: ["processingMode": UserDefaults.standard.string(forKey: "callProcessingMode") ?? "circuit", "noticeVersion": "2026-10-01"])
            SessionCapture.startNewCall()
        } catch {
            state.engineError = "Could not preserve your previous call. Try again before starting a new one."
            ReviewWindow.shared.show()
            return
        }
        state.starting = true
        state.turns = []; state.youCommitted = ""; state.youProvisional = ""
        state.custCommitted = ""; state.custProvisional = ""; state.customerAvailable = false; state.audioNotice = nil; state.customerName = nil; state.customerCount = 0; state.whoByText = [:]; state.engineError = nil; state.answer = nil; state.answerSources = nil; state.answerStatus = nil; state.nextQuestion = nil; state.nextQuestionTarget = nil
        if panel == nil { buildPanel() }
        panel?.orderOut(nil)
        ReviewWindow.shared.show()
        // show() posts a reload, which reads latest.json — still the PREVIOUS call at this point,
        // because the new engine has not spawned yet. Clear right after, so the old transcript never
        // appears. Without this the last call stayed on screen until state.listening flipped, which
        // is gated behind the audio engine starting and takes seconds.
        NotificationCenter.default.post(name: .clearSession, object: nil)
        let cueMode = UserDefaults.standard.string(forKey: "coachCueMode") ?? "autopilot"
        // Start on the methodology the user actually selected. Hardcoding "meddic" here meant every new
// call opened on MEDDPICC even with SPIN chosen, and only a mid-call switch appeared to work.
LiveCoach.shared.start(framework: Coaching.selectedID, mode: cueMode)   // persistent, incremental coach

        let cfg = Config.load()
        // Two-model split (latency vs accuracy): the FAST model drives the live scroll (small.en, greedy,
        // ~0.3s/pass); the ACCURATE model runs once on each finalized turn (beam search). Best available
        // accurate model: large-v3-turbo (faster AND more accurate than medium) > medium.en > small.en.
        let liveModel = Transcriber.modelExists(modelSize: "small.en") ? "small.en"
                      : Transcriber.modelExists(modelSize: "base.en") ? "base.en" : cfg.modelSize
        // medium.en BEATS large-v3-turbo on English domain jargon once the vocabulary prompt is in play
        // (measured: medium got "legacy SIEM / SOC 2 audit / miss triage SLAs" perfect; turbo got all
        // three wrong — it's multilingual and less prompt-steerable) and it's slightly faster too.
        let finalModel = Transcriber.modelExists(modelSize: "medium.en") ? "medium.en"
                       : Transcriber.modelExists(modelSize: "large-v3-turbo") ? "large-v3-turbo"
                       : liveModel
        // Domain vocabulary so security/sales terms transcribe correctly (SIEM, SOC 2, SLAs, MEDDIC).
        var vocab = (cfg.whisperPrompt?.isEmpty == false) ? cfg.whisperPrompt! : Transcriber.salesVocabulary
        // Plus whoever call prep says is on the call. A name is the single hardest thing for whisper
        // to guess and the most embarrassing to get wrong in front of the customer.
        let prepURL = SessionCapture.sessionsDir.appendingPathComponent("prep.txt")
        if let prep = try? String(contentsOf: prepURL, encoding: .utf8) {
            let names = Transcriber.attendeeNames(fromPrep: prep)
            if !names.isEmpty { vocab += " On this call: " + names.joined(separator: ", ") + "." }
        }
        let makeLive = { Transcriber(modelSize: liveModel, language: cfg.language, whisperPrompt: vocab, threads: 4, beamSize: nil) }   // greedy = fast
        let makeFinal = { Transcriber(modelSize: finalModel, language: cfg.language, whisperPrompt: vocab, threads: 6, beamSize: 5) }   // beam = accurate

        // Bring the resident whisper-servers up NOW so they're loaded before audio flows — eliminates
        // the per-call model reload (measured ~50% of each transcription pass).
        let liveModelPath = Transcriber.findModel(modelSize: liveModel)
        let finalModelPath = Transcriber.findModel(modelSize: finalModel)
        WhisperServerPool.shared.prewarm(modelPaths: [liveModelPath, finalModelPath].compactMap { $0 }, threads: 6)

        // Mic → "You"
        let you = StreamingMicTranscriber(live: makeLive(), final: makeFinal(), speaker: "you", capturesMic: true)
        you.onActivity = { active, at, voicedAt in LiveCoach.shared.feedActivity(speaker: "you", active: active, at: at, voicedAt: voicedAt) }
        you.onUpdate = { [weak self] c, p in self?.state.youCommitted = c; self?.state.youProvisional = p }
        you.onTurnDetailed = { [weak self] turn, wav, startedAt, endedAt, words in
            self?.state.turns.append(LiveTurn(speaker: "you", text: turn, startedAt: startedAt))
            self?.state.youCommitted = ""; self?.state.youProvisional = ""
            SessionCapture.appendYou(turn)
            self?.state.turns.sort { $0.startedAt < $1.startedAt }
            LiveCoach.shared.feed(speaker: "you", text: turn, wav: wav, startedAt: startedAt, endedAt: endedAt, words: words)
        }

        // System audio → "Customer"
        let cust = StreamingMicTranscriber(live: makeLive(), final: makeFinal(), speaker: "customer", capturesMic: false)
        cust.onActivity = { active, at, voicedAt in LiveCoach.shared.feedActivity(speaker: "customer", active: active, at: at, voicedAt: voicedAt) }
        cust.onUpdate = { [weak self] c, p in self?.state.custCommitted = c; self?.state.custProvisional = p }
        cust.onTurnDetailed = { [weak self] turn, wav, startedAt, endedAt, words in
            self?.state.turns.append(LiveTurn(speaker: "customer", text: turn, startedAt: startedAt))
            self?.state.custCommitted = ""; self?.state.custProvisional = ""
            SessionCapture.appendCustomer(turn)
            self?.state.turns.sort { $0.startedAt < $1.startedAt }
            LiveCoach.shared.feed(speaker: "customer", text: turn, wav: wav, startedAt: startedAt, endedAt: endedAt, words: words)
        }

        do {
            try you.start()
            youT = you
            isRunning = true
            state.listening = true
            ComplianceAudit.record("capture-started")
            state.starting = false
        } catch {
            state.listening = false
            state.starting = false
            state.engineError = "Could not start the microphone. Check microphone access and the selected input device."
            NSLog("LiveHUD mic start failed: \(error.localizedDescription)")
            LiveCoach.shared.stop()   // don't leave the coach running with no audio
            WhisperServerPool.shared.shutdownAll()
            return                    // and don't start customer capture if the mic failed
        }

        if #available(macOS 14.4, *) {
            let cap = SystemAudioCapture()
            cap.onSamples = { [weak cust] samples in cust?.append(samples) }
            cap.onAudioDetected = { [weak self] in
                self?.state.audioNotice = nil
                self?.state.customerAvailable = true
            }
            cap.onOutputDeviceChanged = { [weak self] in self?.rebuildCustomerCapture() }
            let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
            if cap.startGlobal(excluding: [ownPID] + LiveHUD.testExcludedPIDs()) {
                try? cust.start()
                custT = cust
                systemCapture = cap
                state.customerAvailable = true
                startCustomerSilenceWatchdog()
            } else {
                NSLog("[SalesPilot] customer audio capture did NOT start — transcript will be one-sided")
            }
        }
    }

    /// TEST AFFORDANCE. The system-audio tap is GLOBAL: it captures what every process plays,
    /// whatever device that process renders to. An automated end-to-end test has to synthesize the
    /// REP's voice through a loopback input, and without this that synthetic playback would also
    /// land on the customer channel and make the test measure its own artifact.
    ///
    /// Read from the ENVIRONMENT rather than a stored preference on purpose: an environment variable
    /// exists only for the life of one deliberately launched process, so it cannot be left switched
    /// on by accident, and a normally launched app can never see it.
    static func testExcludedPIDs() -> [pid_t] {
        (ProcessInfo.processInfo.environment["SALESPILOT_TEST_EXCLUDE_PIDS"] ?? "")
            .split(separator: ",").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The tap can attach to a device the call is not playing through: it starts cleanly, reports
    /// success, and delivers digital silence for the whole call. That produced a one-sided
    /// transcript with no warning anywhere. If no real audio has arrived after 45s of listening,
    /// say so instead of letting the call run to the end looking healthy.
    private func startCustomerSilenceWatchdog() {
        silenceWatchdog?.invalidate()
        silenceWatchdog = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            guard #available(macOS 14.4, *), let cap = self.systemCapture as? SystemAudioCapture else { return }
            if !cap.sawRealAudio {
                NSLog("[SalesPilot] customer channel silent for 45s on '\(cap.tappedDeviceName)' — wrong output device?")
                self.state.audioNotice = "No call audio heard yet. If others are speaking, check the call audio output."
            }
        }
    }

    /// Conferencing apps take over the system default-output slot when a meeting starts and hand it
    /// back when it ends. The tap is bound to one device, so a swap mid-call silently stranded it on
    /// the old device and the customer's side went missing for the rest of the call. Rebuild onto
    /// the device that is actually playing audio now, reusing the existing transcriber so the
    /// transcript and the coaching thread continue uninterrupted.
    private func rebuildCustomerCapture() {
        guard #available(macOS 14.4, *), isRunning, let cust = custT else { return }
        (systemCapture as? SystemAudioCapture)?.stop()
        systemCapture = nil

        let cap = SystemAudioCapture()
        cap.onSamples = { [weak cust] samples in cust?.append(samples) }
            cap.onAudioDetected = { [weak self] in
                self?.state.audioNotice = nil
                self?.state.customerAvailable = true
            }
        cap.onOutputDeviceChanged = { [weak self] in self?.rebuildCustomerCapture() }
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        if cap.startGlobal(excluding: [ownPID] + LiveHUD.testExcludedPIDs()) {
            systemCapture = cap
            state.customerAvailable = true
            startCustomerSilenceWatchdog()   // re-arm: the new device may be the silent one
        } else {
            state.customerAvailable = false   // surfaces the red "customer audio is NOT captured" banner
            NSLog("[SalesPilot] could not re-attach customer capture after the output device changed")
        }
    }

    func stop() {
        guard !finishing else { return }
        if isRunning { ComplianceAudit.record("capture-stop-requested") }
        finishing = true
        state.finishing = true
        state.starting = false
        silenceWatchdog?.invalidate(); silenceWatchdog = nil
        if #available(macOS 14.4, *), let cap = systemCapture as? SystemAudioCapture { cap.stop() }
        systemCapture = nil
        let group = DispatchGroup()
        if let mic = youT { group.enter(); mic.stop { group.leave() } }
        if let customer = custT { group.enter(); customer.stop { group.leave() } }
        youT = nil; custT = nil
        isRunning = false
        state.listening = false
        panel?.orderOut(nil)
        group.notify(queue: .main) { [weak self] in
            WhisperServerPool.shared.shutdownAll()
            LiveCoach.shared.finishWithRecap()
            self?.finishing = false
            self?.state.finishing = false
            self?.state.youCommitted = ""; self?.state.youProvisional = ""
            self?.state.custCommitted = ""; self?.state.custProvisional = ""
        }
    }

    func showCompact() {
        guard state.listening else { return }
        if panel == nil { buildPanel() }
        ReviewWindow.shared.hideForCompact()
        panel?.orderFrontRegardless()
    }

    func hideCompact() { panel?.orderOut(nil) }

    func resizePanel(height: CGFloat) {
        guard let panel else { return }
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: 380, height: height))
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    private func buildPanel() {
        let rect = NSRect(x: 0, y: 0, width: 380, height: 270)
        let p = NSPanel(contentRect: rect,
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
                        backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: LiveHUDView(state: state))
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: vf.maxX - rect.width - 20, y: vf.maxY - rect.height - 20))
        }
        panel = p
    }
}

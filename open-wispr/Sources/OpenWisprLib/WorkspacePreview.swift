import AppKit
import SwiftUI

/// Renders the actual workspace without starting capture, models, integrations or the menu-bar app.
public enum WorkspacePreview {
    public static func verifyOffline() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard ProcessInfo.processInfo.environment["SALESPILOT_ROOT"] != nil else {
            throw NSError(domain: "SalesPilotVerify", code: 1, userInfo: [NSLocalizedDescriptionKey: "An isolated workspace is required"])
        }
        guard !FileManager.default.fileExists(atPath: SessionCapture.sessionsDir.appendingPathComponent("prep.txt").path),
              !FileManager.default.fileExists(atPath: SessionCapture.sessionsDir.appendingPathComponent("prep").path) else {
            throw NSError(domain: "SalesPilotVerify", code: 3, userInfo: [NSLocalizedDescriptionKey: "Verification requires a fresh workspace with no saved context"])
        }
        var passed = 0
        func check(_ name: String, _ condition: Bool) throws {
            guard condition else { throw NSError(domain: "SalesPilotVerify", code: 2, userInfo: [NSLocalizedDescriptionKey: name]) }
            passed += 1; print("PASS " + name)
        }
        try check("workspace survives closing and reopening without release", ReviewWindow.shared.verifyHiddenReopen())
        let suiteName = "salespilot-offline-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = CallPrepModel(preview: true, preferences: preferences)
        model.save()
        let active = SessionCapture.sessionsDir.appendingPathComponent("prep.txt")
        let savedText = try String(contentsOf: active, encoding: .utf8)
        let parsed = CallPrepDraft(text: savedText)
        try check("context save retains account, goal, people and notes", parsed.account == model.account && parsed.goal == model.goal && parsed.people == model.people && parsed.notes == model.notes)
        try check("context save adds a reusable saved copy", model.saved.count == 1)
        let loaded = CallPrepModel(preferences: preferences)
        try check("saved context reloads into the editor", loaded.goal == model.goal && loaded.people == model.people)
        loaded.notes = "An unsaved change"
        try check("editing a draft does not change active prep", try String(contentsOf: active, encoding: .utf8) == savedText)
        loaded.load(model.saved[0])
        try check("loading saved context recovers its original draft", loaded.notes == model.notes)
        loaded.clearActive()
        try check("clearing context preserves saved copies", !FileManager.default.fileExists(atPath: active.path) && FileManager.default.fileExists(atPath: model.saved[0].path))
        try check("live state offers End call across all entry points", LiveState.shared.presentation == .ready && CallPresentation(listening: true, starting: false, finishing: false).actionTitle == "End live call")
        LiveHUD.shared.start()
        try check("unconfirmed consent cannot start capture or create a capture journal", !LiveState.shared.listening && !LiveState.shared.starting && !FileManager.default.fileExists(atPath: CaptureJournal.url.path))
        CallConsentWindow.shared.close()
        let sample = DemoSession.make()
        try check("fictional competitive example retains categorized answer and customer signal", sample.liveAnswer?.category == "competition" && sample.competition?.first?.name == "Sumo Logic")
        let discovery = DemoSession.make(purpose: "discovery")
        let flexible = DemoSession.make(purpose: "standard")
        try check("both mode examples show the same immediate demo request with distinct contextual cues", discovery.turns.last?.text == flexible.turns.last?.text && discovery.nextq.first?.q != flexible.nextq.first?.q && discovery.nextq.first?.q == discovery.turns.last?.coachQ && flexible.nextq.first?.q == flexible.turns.last?.coachQ)
        try check("discovery example redirects today while flexible example explores demo criteria", discovery.nextq.first?.q.contains("next step") == true && flexible.nextq.first?.q.contains("judge") == true && discovery.turns.filter { $0.me }.allSatisfy { $0.who == "Rodney White" })
        let roundTrip = try JSONDecoder().decode(SessionData.self, from: JSONEncoder().encode(sample))
        try check("competition and call style survive session round trip", roundTrip.callPurpose == sample.callPurpose && roundTrip.competition?.first?.resources.first?.url == sample.competition?.first?.resources.first?.url)
        print("offline workspace: \(passed)/\(passed) passed")
    }

    public static func verifyAudio(path: String) throws {
        guard ProcessInfo.processInfo.environment["SALESPILOT_ROOT"] != nil else { throw NSError(domain: "SalesPilotVerify", code: 4, userInfo: [NSLocalizedDescriptionKey: "An isolated workspace is required"]) }
        let model = Transcriber.modelExists(modelSize: "small.en") ? "small.en" : "base.en"
        guard let modelPath = Transcriber.findModel(modelSize: model) else { throw TranscriberError.modelNotFound(model) }
        defer { WhisperServerPool.shared.shutdownAll() }
        WhisperServerPool.shared.prewarm(modelPaths: [modelPath], threads: 4)
        let deadline = Date().addingTimeInterval(30)
        while WhisperServerPool.shared.inferenceURL(forModelPath: modelPath, threads: 4) == nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        let start = Date()
        let result = try Transcriber(modelSize: model, language: "en", threads: 4).transcribeDetailed(audioURL: URL(fileURLWithPath: path))
        guard !result.0.isEmpty, !result.1.isEmpty, result.1.allSatisfy({ $0.valid }) else { throw NSError(domain: "SalesPilotVerify", code: 5, userInfo: [NSLocalizedDescriptionKey: "Actual local ASR did not return valid timed words"]) }
        if let output = ProcessInfo.processInfo.environment["SALESPILOT_VERIFY_AUDIO_OUTPUT"] {
            try result.0.write(toFile: output, atomically: true, encoding: .utf8)
        }
        print("PASS actual local ASR: \(result.1.count) timed tokens, model \(model), \(Date().timeIntervalSince(start)) seconds; no audio device or network model used")
    }

    public static func render(path: String, compact: Bool = false, prep: Bool = false, notes: Bool = false, section: String? = nil, knowledge: Bool = false, consent: Bool = false, privacy: Bool = false, example: Bool = false) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let size = privacy ? NSSize(width: 720, height: 700) : consent ? NSSize(width: 630, height: 600) : knowledge ? NSSize(width: 680, height: 460) : prep ? NSSize(width: 720, height: 780) : compact ? NSSize(width: 380, height: 270) : NSSize(width: 1080, height: 740)
        SessionStore.showingExample = example
        let host: NSView
        if privacy {
            host = NSHostingView(rootView: PrivacyControls())
        } else if consent {
            host = NSHostingView(rootView: CallConsent())
        } else if knowledge {
            host = NSHostingView(rootView: ReferenceLibrary())
        } else if prep {
            host = NSHostingView(rootView: CallPrepView(model: CallPrepModel(preview: true)))
        } else if compact {
            let state = LiveState.shared
            let session = example ? DemoSession.make() : SessionStore.load()
            state.nextQuestion = session.nextq.first?.q
            state.nextQuestionTarget = session.nextq.first?.tag
            state.customerAvailable = true
            host = NSHostingView(rootView: LiveHUDView(state: state))
        } else {
            SessionStore.reviewingLatest = true
            host = NSHostingView(rootView: ReviewView(notes: notes, section: section))
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "SalesPilotPreview", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SalesPilotPreview", code: 2)
        }
        try data.write(to: URL(fileURLWithPath: path))
        window.close()
    }
}

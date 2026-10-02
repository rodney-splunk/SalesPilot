import AppKit
import ServiceManagement
import Combine

class MenuItemTarget: NSObject {
    let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var animationFrames: [NSImage] = []
    private var downloadProgress: String?
    private var downloadPercent: Double = 0
    private var copiedFeedback = false
    private var menuItemTargets: [MenuItemTarget] = []
    private var liveSubscription: AnyCancellable?
    private var stateMenuItem: NSMenuItem?

    var reprocessHandler: ((URL) -> Void)?
    var onConfigChange: ((Config) -> Void)?

    enum State {
        case idle
        case recording
        case transcribing
        case downloading
        case waitingForPermission
        case copiedToClipboard
        case error(String)
    }

    var state: State = .idle {
        didSet { updateIcon() }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = StatusBarController.drawLogo(active: false)
            button.image?.isTemplate = true
            button.title = " SalesPilot"
            button.imagePosition = .imageLeading
        }

        liveSubscription = LiveState.shared.$listening.combineLatest(LiveState.shared.$starting, LiveState.shared.$finishing)
            .map { CallPresentation(listening: $0.0, starting: $0.1, finishing: $0.2) }
            .removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon(); self?.buildMenu() }
        NotificationCenter.default.addObserver(forName: .callPrepChanged, object: nil, queue: .main) { [weak self] _ in self?.buildMenu() }
        buildMenu()
    }

    @objc private func copyLastTranscription() {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate,
              let text = delegate.lastTranscription else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedFeedback = true
        buildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.copiedFeedback = false
            self?.buildMenu()
        }
    }

    func updateDownloadProgress(_ text: String?, percent: Double = 0) {
        downloadProgress = text
        downloadPercent = percent
        if case .downloading = state {
            setIcon(StatusBarController.drawDownloadProgress(downloadPercent))
        }
        if let text = text, let item = stateMenuItem {
            item.title = text
        } else {
            buildMenu()
        }
    }

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    func buildMenu() {
        menuItemTargets = []
        let menu = NSMenu()

        // --- Status (no dictation hotkey; this is a call copilot, not a dictation tool) ---
        let stateLabel: String
        if let progress = downloadProgress {
            stateLabel = progress
        } else {
            switch state {
            case .idle: stateLabel = LiveState.shared.presentation.label
            case .recording: stateLabel = "Recording…"
            case .transcribing: stateLabel = "Transcribing…"
            case .downloading: stateLabel = "Downloading model…"
            case .waitingForPermission: stateLabel = "Waiting for Accessibility permission…"
            case .copiedToClipboard: stateLabel = "Copied"
            case .error(let message): stateLabel = "Error: \(message)"
            }
        }
        if case .waitingForPermission = state {
            let target = MenuItemTarget { Permissions.openAccessibilitySettings() }
            menuItemTargets.append(target)
            let stateItem = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            stateItem.target = target
            menu.addItem(stateItem)
            stateMenuItem = stateItem
        } else {
            let stateItem = NSMenuItem(title: stateLabel, action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            menu.addItem(stateItem)
            stateMenuItem = stateItem
        }

        menu.addItem(NSMenuItem.separator())

        // --- The live call ---
        let liveTarget = MenuItemTarget { [weak self] in
            self?.toggleLive()
            self?.buildMenu()
        }
        menuItemTargets.append(liveTarget)
        let liveItem = NSMenuItem(title: LiveState.shared.presentation.actionTitle,
                                  action: #selector(MenuItemTarget.invoke), keyEquivalent: "l")
        liveItem.target = liveTarget
        liveItem.isEnabled = LiveState.shared.presentation.canToggle
        menu.addItem(liveItem)
        let workspaceTarget = MenuItemTarget { ReviewWindow.shared.show() }
        menuItemTargets.append(workspaceTarget)
        let workspaceItem = NSMenuItem(title: "Open workspace", action: #selector(MenuItemTarget.invoke), keyEquivalent: "w")
        workspaceItem.target = workspaceTarget
        menu.addItem(workspaceItem)
        if LiveState.shared.listening {
            let compactTarget = MenuItemTarget { LiveHUD.shared.showCompact() }
            menuItemTargets.append(compactTarget)
            let compactItem = NSMenuItem(title: "Show compact view", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            compactItem.target = compactTarget
            menu.addItem(compactItem)
        }

        // Coaching style — the fading ladder (build skill, don't script the rep).
        let curMode = UserDefaults.standard.string(forKey: "coachCueMode") ?? "autopilot"
        let styleItem = NSMenuItem(title: "Coaching Style", action: nil, keyEquivalent: "")
        let styleSub = NSMenu()
        let styles: [(String, String, String)] = [
            ("autopilot", "Autopilot — the full question", "Shows the exact question to ask. Best for brand-new reps."),
            ("nudge",     "Nudge — the move + their words", "Names the move; you phrase the question."),
            ("gap",       "Gap only — just what's missing", "Names only the uncovered element. Most skill-building."),
        ]
        for (id, title, help) in styles {
            let target = MenuItemTarget { [weak self] in
                UserDefaults.standard.set(id, forKey: "coachCueMode")
                if LiveHUD.shared.isRunning { LiveCoach.shared.setMode(id) }
                self?.buildMenu()
            }
            menuItemTargets.append(target)
            let item = NSMenuItem(title: title, action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            item.target = target
            item.state = (curMode == id) ? .on : .off
            item.toolTip = help
            styleSub.addItem(item)
        }
        styleItem.submenu = styleSub
        menu.addItem(styleItem)

        menu.addItem(NSMenuItem.separator())

        // --- Before / after the call ---
        let prepTarget = MenuItemTarget { [weak self] in self?.prepareForCall() }
        menuItemTargets.append(prepTarget)
        let prepItem = NSMenuItem(title: "Call context…",
                                  action: prepping ? nil : #selector(MenuItemTarget.invoke), keyEquivalent: "")
        prepItem.target = prepping ? nil : prepTarget
        prepItem.isEnabled = !prepping
        menu.addItem(prepItem)
        if FileManager.default.fileExists(atPath: SessionCapture.sessionsDir.appendingPathComponent("prep.txt").path) {
            let name = UserDefaults.standard.string(forKey: "prepName") ?? "prep.txt"
            let loaded = NSMenuItem(title: "   ↳ using: \(name)", action: nil, keyEquivalent: "")
            loaded.isEnabled = false
            menu.addItem(loaded)
        }

        let callsTarget = MenuItemTarget { ReviewWindow.shared.show(); NotificationCenter.default.post(name: .showPastCalls, object: nil) }
        menuItemTargets.append(callsTarget)
        let callsItem = NSMenuItem(title: "Past calls…", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        callsItem.target = callsTarget
        menu.addItem(callsItem)

        let exampleTarget = MenuItemTarget { [weak self] in self?.showExample() }
        menuItemTargets.append(exampleTarget)
        let exampleItem = NSMenuItem(title: "Show Example Call", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        exampleItem.target = exampleTarget
        menu.addItem(exampleItem)

        let recapTarget = MenuItemTarget { ReviewWindow.shared.show(); NotificationCenter.default.post(name: .showRecapReview, object: nil) }
        menuItemTargets.append(recapTarget)
        let recapItem = NSMenuItem(title: "Review / copy recap…", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        recapItem.target = recapTarget
        menu.addItem(recapItem)

        menu.addItem(NSMenuItem.separator())

        // --- Advanced (nested; transparent about the files it touches) ---
        let advItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let advSub = NSMenu()

        let docsHeader = NSMenuItem(title: "Live answers read your docs in:", action: nil, keyEquivalent: "")
        docsHeader.isEnabled = false
        advSub.addItem(docsHeader)
        let docsPathItem = NSMenuItem(title: "   ~/Documents/sales-copilot/sessions/docs", action: nil, keyEquivalent: "")
        docsPathItem.isEnabled = false
        advSub.addItem(docsPathItem)
        let openDocsTarget = MenuItemTarget { [weak self] in self?.openDocsFolder() }
        menuItemTargets.append(openDocsTarget)
        let openDocsItem = NSMenuItem(title: "Open Docs Folder…", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        openDocsItem.target = openDocsTarget
        advSub.addItem(openDocsItem)
        let indexTarget = MenuItemTarget { [weak self] in self?.indexDocs() }
        menuItemTargets.append(indexTarget)
        let indexItem = NSMenuItem(title: "Re-index Docs (rebuild answer index)", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        indexItem.target = indexTarget
        advSub.addItem(indexItem)

        advSub.addItem(NSMenuItem.separator())

        let testAudioItem = NSMenuItem(title: "Test Customer Audio", action: nil, keyEquivalent: "")
        let testSub = NSMenu()
        let hintItem = NSMenuItem(title: "Pick the app playing the call:", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        testSub.addItem(hintItem)
        testSub.addItem(NSMenuItem.separator())
        let globalTarget = MenuItemTarget { [weak self] in self?.testSystemAudio() }
        menuItemTargets.append(globalTarget)
        let globalItem = NSMenuItem(title: "🔊 All system audio (recommended)", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        globalItem.target = globalTarget
        testSub.addItem(globalItem)
        testSub.addItem(NSMenuItem.separator())
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !($0.localizedName ?? "").isEmpty }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in runningApps {
            let name = app.localizedName ?? ""
            let pid = app.processIdentifier
            let target = MenuItemTarget { [weak self] in self?.testCustomerAudio(pid: pid, name: name) }
            menuItemTargets.append(target)
            let item = NSMenuItem(title: name, action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            item.target = target
            testSub.addItem(item)
        }
        testAudioItem.submenu = testSub
        advSub.addItem(testAudioItem)

        advSub.addItem(NSMenuItem.separator())

        let aecOn = UserDefaults.standard.bool(forKey: "aec")
        let aecTarget = MenuItemTarget { UserDefaults.standard.set(!aecOn, forKey: "aec") }
        menuItemTargets.append(aecTarget)
        let aecItem = NSMenuItem(title: "Echo Cancellation (beta — applies next call)", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        aecItem.target = aecTarget
        aecItem.state = aecOn ? .on : .off
        advSub.addItem(aecItem)

        if #available(macOS 13.0, *) {
            let loginOn = SMAppService.mainApp.status == .enabled
            let loginTarget = MenuItemTarget {
                do {
                    if loginOn { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
                } catch { NSLog("Launch at Login toggle failed: \(error.localizedDescription)") }
            }
            menuItemTargets.append(loginTarget)
            let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            loginItem.target = loginTarget
            loginItem.state = loginOn ? .on : .off
            advSub.addItem(loginItem)
        }

        advSub.addItem(NSMenuItem.separator())
        let ghostAuthTarget = MenuItemTarget { [weak self] in self?.ghostAuthLogin() }
        menuItemTargets.append(ghostAuthTarget)
        let ghostAuthItem = NSMenuItem(title: "Log in to Ghost (refresh Slack)…", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        ghostAuthItem.target = ghostAuthTarget
        advSub.addItem(ghostAuthItem)

        advItem.submenu = advSub
        menu.addItem(advItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SalesPilot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    /// Delete archived calls. Multi-select, then an explicit confirm — this removes the transcript,
    /// coaching and recap for those calls and cannot be undone.
    private func managePastCalls() {
        let historyDir = SessionCapture.sessionsDir.appendingPathComponent("history", isDirectory: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard !files.isEmpty else {
            infoAlert("No past calls", "Nothing has been archived yet.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Manage Past Calls"
        alert.informativeText = "Tick the calls you want to remove, then choose Delete Selected."

        let rowH: CGFloat = 22
        let width: CGFloat = 460
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: CGFloat(files.count) * rowH))
        var boxes: [NSButton] = []
        for (i, url) in files.enumerated() {
            let b = NSButton(checkboxWithTitle: pastCallLabel(url), target: nil, action: nil)
            b.frame = NSRect(x: 0, y: content.frame.height - CGFloat(i + 1) * rowH, width: width, height: rowH)
            content.addSubview(b)
            boxes.append(b)
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(CGFloat(files.count) * rowH, 280)))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = content
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Delete Selected")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let toDelete = zip(boxes, files).filter { $0.0.state == .on }.map { $0.1 }
        guard !toDelete.isEmpty else {
            infoAlert("Nothing selected", "No calls were removed.")
            return
        }
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Delete \(toDelete.count) call\(toDelete.count == 1 ? "" : "s")?"
        confirm.informativeText = "This permanently removes the archived transcript, coaching and recap. It can't be undone."
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        var removed = 0
        for url in toDelete where (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        buildMenu()
        infoAlert("Deleted \(removed) call\(removed == 1 ? "" : "s")", "Your Past Calls list has been updated.")
    }

    /// ONE clear entry point for prep. The old menu had "Set Call Prep…" AND "Prep for Call
    /// (Calendar · Slack · Salesforce)…" with no hint what either meant. This explains what prep IS,
    /// then offers the three real paths.
    private func prepareForCall() { CallPrepWindow.shared.show() }

    /// Saved per-customer preps, as a picker rather than a buried submenu.
    private func chooseSavedPrep() {
        let prepsDir = SessionCapture.sessionsDir.appendingPathComponent("prep", isDirectory: true)
        let saved = ((try? FileManager.default.contentsOfDirectory(at: prepsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !saved.isEmpty else {
            infoAlert("No saved preps yet",
                      "Preps are saved per customer once you build one.\n\nTry “Auto-prep from my next meeting” or “Paste my own notes” first.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Use a saved prep"
        alert.informativeText = "These are preps you've built before — one per customer."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        for url in saved { popup.addItem(withTitle: url.deletingPathExtension().lastPathComponent) }
        let active = UserDefaults.standard.string(forKey: "prepActive") ?? ""
        if let idx = saved.firstIndex(where: { $0.deletingPathExtension().lastPathComponent == active }) {
            popup.selectItem(at: idx)
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Use this prep")
        alert.addButton(withTitle: "Clear active prep")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let i = popup.indexOfSelectedItem
            if i >= 0 && i < saved.count { activatePrep(saved[i]) }
        case .alertSecondButtonReturn: clearCallPrep()
        default: break
        }
    }

    @objc private func reloadConfiguration() {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        delegate.reloadConfig()
    }

    @objc private func openConfiguration() {
        let configFile = Config.configFile
        if !FileManager.default.fileExists(atPath: configFile.path) {
            let config = Config.defaultConfig
            try? config.save()
        }
        NSWorkspace.shared.open(configFile)
    }

    private func infoAlert(_ title: String, _ body: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = body
        a.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); a.runModal()
    }

    /// Pick a notes/transcript file (Gong recap, prior notes) to seed the next call.
    private func setCallPrep() {
        let alert = NSAlert()
        alert.messageText = "Set Call Prep"
        alert.informativeText = "Paste notes/context for the next call — or load a file."
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        tv.isEditable = true
        tv.font = NSFont.systemFont(ofSize: 12)
        tv.isRichText = false
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Save")        // .alertFirstButtonReturn
        alert.addButton(withTitle: "Load File…")  // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")      // .alertThirdButtonReturn
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = tv
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let firstLine = text.components(separatedBy: .newlines).first ?? "typed notes"
            savePrep(text: text, name: String(firstLine.prefix(40)))
        case .alertSecondButtonReturn:
            loadPrepFromFile()
        default:
            break
        }
    }

    private func prepSlug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var slug = String(String.UnicodeScalarView(s.unicodeScalars.map { allowed.contains($0) ? $0 : "-" })).lowercased()
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "prep" : String(slug.prefix(50))
    }

    private var prepDir: URL {
        let d = SessionCapture.sessionsDir.appendingPathComponent("prep", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Save a named prep to sessions/prep/<slug>.txt AND make it the active prep (sessions/prep.txt).
    private func savePrep(text: String, name: String) {
        let slug = prepSlug(name)
        let named = prepDir.appendingPathComponent("\(slug).txt")
        let active = SessionCapture.sessionsDir.appendingPathComponent("prep.txt")
        do {
            try text.write(to: named, atomically: true, encoding: .utf8)
            try text.write(to: active, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(name, forKey: "prepName")
            UserDefaults.standard.set(slug, forKey: "prepActive")
            infoAlert("Call prep saved ✓", "Saved “\(name)” and set it active.\n\nStored as:\n~/Documents/sales-copilot/sessions/prep/\(slug).txt\n\nActive prep the coach uses:\n~/Documents/sales-copilot/sessions/prep.txt")
            previewPrep()   // pre-fill and open the session window so you can see the loaded context
        } catch {
            infoAlert("Couldn't save prep", error.localizedDescription)
        }
    }

    /// Make a saved prep the active one.
    private func activatePrep(_ url: URL) {
        let active = SessionCapture.sessionsDir.appendingPathComponent("prep.txt")
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try text.write(to: active, atomically: true, encoding: .utf8)
            let slug = url.deletingPathExtension().lastPathComponent
            UserDefaults.standard.set(slug, forKey: "prepName")
            UserDefaults.standard.set(slug, forKey: "prepActive")
            previewPrep()
        } catch {
            infoAlert("Couldn't load prep", error.localizedDescription)
        }
    }

    private func loadPrepFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick a notes/transcript file (prior notes, a Gong recap, etc.)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            savePrep(text: text, name: url.lastPathComponent)
        } catch {
            infoAlert("Couldn't read that file", error.localizedDescription)
        }
    }

    /// Run the engine's prep pre-fill once (name + known coverage) and open the window to show it.
    private func previewPrep() {
        if LiveHUD.shared.isRunning { ReviewWindow.shared.show(); return } // don't overwrite the live session
        let engineDir = WorkspacePaths.engine
        let script = engineDir.appendingPathComponent("serve.mjs")
        let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        guard let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            ReviewWindow.shared.show(); return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = [script.path, "--framework", "meddic", "--prep-preview"]
        proc.currentDirectoryURL = engineDir
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        proc.terminationHandler = { _ in DispatchQueue.main.async { ReviewWindow.shared.show() } }
        do { try proc.run() } catch { ReviewWindow.shared.show() }
    }

    /// Open Terminal running `ghost auth login` so the user can complete the interactive SSO.
    private func ghostAuthLogin() {
        let ghost = "\(FileManager.default.homeDirectoryForCurrentUser.path)/go/bin/ghost"
        let cmd = "\(ghost) auth login"
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do { try proc.run() } catch {
            infoAlert("Couldn't open Terminal", "Run this yourself:\n\n  ghost auth login")
        }
    }

    /// One unified prep: read the next Outlook meeting, confirm the account, draft from Calendar + Slack.
    private func prepForCall() {
        nextOutlookMeeting { [weak self] subject, when, atts in
            guard let self = self else { return }
            let header = subject.isEmpty ? nil : "Upcoming meeting: \(subject) — \(when). Attendees: \(atts)"
            let info = subject.isEmpty
                ? "No upcoming Outlook meeting found. Enter the account and I'll draft prep from Slack + Salesforce."
                : "Next meeting: \(subject).\nI'll draft prep from your calendar + Slack + Salesforce — edit the account if needed."
            guard let account = self.promptForText("Prep for Call", info, prefill: subject), !account.isEmpty else { return }
            self.runGhostPrep(account, header: header)
        }
    }

    private func promptForText(_ title: String, _ info: String, prefill: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = prefill
        field.placeholderString = "Account or customer name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Prep")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    /// True while an auto-prep is running, so the menu can say so instead of looking inert.
    private var prepping = false

    private func runGhostPrep(_ query: String, header: String? = nil) {
        let engineDir = WorkspacePaths.engine
        let script = engineDir.appendingPathComponent("ghost-prep.mjs")
        let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        guard let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            infoAlert("Couldn't run Ghost prep", "node not found."); return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        var args = [script.path]
        if let header = header { args += ["--header", header] }
        args.append(query)
        proc.arguments = args
        proc.currentDirectoryURL = engineDir
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/go/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")   // ghost lives in ~/go/bin
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        prepping = true
        buildMenu()
        // A prep that stalls used to leave the app looking like the button did nothing: the process
        // never exited, so this handler never ran and no window ever opened. Never wait forever.
        var finished = false
        let finishLock = NSLock()
        let watchdog = DispatchWorkItem { [weak self] in
            finishLock.lock(); let alreadyDone = finished; finishLock.unlock()
            guard !alreadyDone else { return }
            if proc.isRunning { proc.terminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if proc.isRunning { kill(proc.processIdentifier, SIGKILL) } }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.prepping = false; self.buildMenu()
                self.infoAlert("Prep is taking too long",
                               "Stopped after 3 minutes. Slack or Salesforce may not be logged in.\n\nTry: dev-login slack, or use “Paste my own notes”.")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: watchdog)
        proc.terminationHandler = { [weak self] p in
            finishLock.lock(); finished = true; finishLock.unlock()
            watchdog.cancel()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.prepping = false
                self.buildMenu()
                if p.terminationStatus == 0 {
                    let slug = out.components(separatedBy: "slug=").last?.components(separatedBy: .whitespacesAndNewlines).first ?? ""
                    UserDefaults.standard.set(query, forKey: "prepName")
                    if !slug.isEmpty { UserDefaults.standard.set(slug, forKey: "prepActive") }
                    self.previewPrep()   // open the window pre-filled with the drafted prep
                } else {
                    self.infoAlert("Ghost prep didn't run", out.isEmpty ? "No results, or Slack auth expired (run: dev-login slack)." : out)
                }
            }
        }
        do { try proc.run() } catch {
            watchdog.cancel(); prepping = false; buildMenu()
            infoAlert("Couldn't run Ghost prep", error.localizedDescription)
        }
    }

    /// Read the next timed Outlook meeting; completion(subject, when, attendeesShort) on main
    /// (empty subject if none or Outlook access is blocked).
    func nextOutlookMeeting(_ completion: @escaping (_ subject: String, _ when: String, _ attendees: String) -> Void) {
        let script = """
        tell application "Microsoft Outlook"
        set nowD to current date
        set best to missing value
        repeat with e in (calendar events whose start time ≥ nowD)
        set isAllDay to false
        try
        set isAllDay to (all day flag of e)
        end try
        if isAllDay is false then
        if best is missing value then
        set best to e
        else if (start time of e) < (start time of best) then
        set best to e
        end if
        end if
        end repeat
        if best is missing value then return "NONE"
        set atts to ""
        try
        repeat with a in attendees of best
        set ea to email address of a
        set nm to (name of ea)
        if nm is missing value or nm is "" then set nm to (address of ea)
        set atts to atts & nm & "; "
        end repeat
        end try
        return (subject of best) & "||" & ((start time of best) as string) & "||" & atts
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errPipe
        proc.terminationHandler = { [weak self] _ in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.lowercased() ?? ""
            DispatchQueue.main.async {
                if (out.isEmpty || out == "NONE"),
                   err.contains("-1743") || err.contains("not allowed") || err.contains("not authorized") {
                    self?.infoAlert("Allow Outlook access", "Grant SalesPilot permission to control Outlook (System Settings → Privacy & Security → Automation), then try again.")
                }
                if out.isEmpty || out == "NONE" { completion("", "", ""); return }
                let parts = out.components(separatedBy: "||")
                let subject = parts.first ?? ""
                let when = parts.count > 1 ? parts[1] : ""
                let attList = (parts.count > 2 ? parts[2] : "").components(separatedBy: "; ").filter { !$0.isEmpty }
                let attShort = attList.prefix(6).joined(separator: ", ") + (attList.count > 6 ? " (+\(attList.count - 6) more)" : "")
                completion(subject, when, attShort)
            }
        }
        do { try proc.run() } catch { DispatchQueue.main.async { completion("", "", "") } }
    }

    private func clearCallPrep() {
        let f = SessionCapture.sessionsDir.appendingPathComponent("prep.txt")
        let name = UserDefaults.standard.string(forKey: "prepName") ?? "prep"
        try? FileManager.default.removeItem(at: f)
        UserDefaults.standard.removeObject(forKey: "prepName")
        UserDefaults.standard.removeObject(forKey: "prepActive")
        infoAlert("Call prep cleared ✓", "Removed the active prep (“\(name)”). Your next call starts with no seeded context.\n\nYour saved customer preps are kept — reload one anytime from Saved Preps.")
    }

    private func pastCallLabel(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return url.deletingPathExtension().lastPathComponent
        }
        let name = (obj["name"] as? String) ?? "Call"
        let date = String(url.lastPathComponent.prefix(10)) // YYYY-MM-DD from the timestamp prefix
        return "\(name) — \(date)"
    }

    /// Load the bundled example session into the review window (shows coaching + a live doc-answer).
    private func showExample() {
        SessionStore.showExample()
    }


    private func openPastCall(_ url: URL) {
        if LiveHUD.shared.isRunning {
            infoAlert("Live call in progress", "Stop the live call before opening a past one.")
            return
        }
        guard let data = try? Data(contentsOf: url), let call = try? JSONDecoder().decode(SessionData.self, from: data) else { return }
        SessionStore.reviewSelection = call
        SessionStore.showingExample = false
        ReviewWindow.shared.show()
    }

    private func openDocsFolder() {
        let dir = SessionCapture.sessionsDir.appendingPathComponent("docs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// Re-index the knowledge docs (sessions/docs) so live answers can retrieve from them.
    private func indexDocs() {
        if LiveHUD.shared.isRunning {
            infoAlert("Live call in progress", "Re-index after the call — the coach re-indexes changed docs automatically at the start of each call.")
            return
        }
        let engineDir = WorkspacePaths.engine
        let script = engineDir.appendingPathComponent("rag.mjs")
        let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        guard let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              FileManager.default.fileExists(atPath: script.path) else {
            infoAlert("Couldn't index", "node or rag.mjs not found.")
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = [script.path, "index"]
        proc.currentDirectoryURL = engineDir
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.terminationHandler = { _ in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async { self.infoAlert("Knowledge docs indexed", out.isEmpty ? "Done." : out) }
        }
        do { try proc.run() } catch { infoAlert("Couldn't index", error.localizedDescription) }
    }

    /// Global system-audio test (catches browser helper processes). Excludes our own audio.
    private func testSystemAudio() {
        guard #available(macOS 14.4, *) else {
            infoAlert("Needs macOS 14.4+", "System-audio capture uses a Core Audio process tap available on macOS 14.4 and later.")
            return
        }
        infoAlert("Test system audio", "Start playing audio (e.g. a YouTube video), then click OK. I'll listen for 8 seconds.")
        let cap = SystemAudioCapture()
        var peak: Float = 0
        cap.onSamples = { samples in for v in samples { peak = max(peak, abs(v)) } }
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard cap.startGlobal(excluding: [ownPID]) else {
            infoAlert("Couldn't start the tap", "Failed to start a system-audio tap. If macOS prompts for Audio Recording permission, grant it and retry.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            cap.stop()
            if peak > 0.001 {
                let db = Int(20 * log10(peak))
                self.infoAlert("✓ System audio works", "Captured system audio at ~\(db) dB peak. The process tap works — next I'll transcribe the customer's voice from it.")
            } else {
                self.infoAlert("Tapped, but silence", "Heard no system audio during the 8 seconds. Make sure something is playing out loud (volume up, not muted), then retry.")
            }
        }
    }

    /// Isolation test for M3: tap the chosen app for 8s and report the captured level.
    private func testCustomerAudio(pid: pid_t, name: String) {
        guard #available(macOS 14.4, *) else {
            infoAlert("Needs macOS 14.4+", "Customer-audio capture uses a Core Audio process tap available on macOS 14.4 and later.")
            return
        }
        infoAlert("Test \(name)", "Start playing audio in \(name), then click OK. I'll listen for 8 seconds and report the level.")
        let cap = SystemAudioCapture()
        var peak: Float = 0
        cap.onSamples = { samples in for v in samples { peak = max(peak, abs(v)) } }
        guard cap.start(pid: pid) else {
            infoAlert("Couldn't start the tap", "Tried to tap \(name) but failed. If macOS prompts for Audio Recording permission, grant it and retry.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            cap.stop()
            if peak > 0.001 {
                let db = Int(20 * log10(peak))
                self.infoAlert("✓ Customer audio works", "Captured \(name) at ~\(db) dB peak. The process tap is working — next I'll transcribe this as the customer's voice.")
            } else {
                self.infoAlert("Tapped, but silence", "Connected to \(name) but heard nothing. Make sure audio is actually playing in \(name) during the 8 seconds, then retry.")
            }
        }
    }

    /// Toggle the live transcript. Starting a live transcript IS starting a call: with a clean
    /// slate it just begins; with a leftover transcript it asks new-vs-continue so nothing is lost.
    private func toggleLive() { LiveHUD.shared.toggle() }

    /// Open the review window immediately, run the coaching engine, then refresh it in place.
    private func buildAndOpenReview() {
        ReviewWindow.shared.show()
        if LiveHUD.shared.isRunning {
            // A live call already writes latest.json continuously; a second writer would collide.
            infoAlert("Live call in progress", "Coaching is already updating live in this window. Stop the live transcript first to re-analyze the whole call.")
            return
        }
        EngineRunner.analyze(framework: "meddic") {
            NotificationCenter.default.post(name: .reloadSession, object: nil)
        }
    }

    /// Briefly flash a checkmark on the menu-bar icon to confirm a background action fired.
    func flashConfirmation() {
        stopAnimation()
        setIcon(StatusBarController.drawCheckmarkIcon())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateIcon()
        }
    }

    private func updateIcon() {
        stopAnimation()

        switch state {
        case .idle:
            setIcon(StatusBarController.drawLogo(active: LiveState.shared.listening))
        case .recording:
            startRecordingAnimation()
        case .transcribing:
            startTranscribingAnimation()
        case .downloading:
            startDownloadingAnimation()
        case .waitingForPermission:
            setIcon(StatusBarController.drawLockIcon())
        case .copiedToClipboard:
            setIcon(StatusBarController.drawCheckmarkIcon())
        case .error:
            setIcon(StatusBarController.drawWarningIcon())
        }
    }

    // MARK: - Recording animation: wave

    private static let waveFrameCount = 30

    private static func prerenderWaveFrames() -> [NSImage] {
        let count = waveFrameCount
        let baseHeights: [CGFloat] = [4, 8, 12, 8, 4]
        let minScale: CGFloat = 0.3
        let phaseOffsets: [Double] = [0.0, 0.15, 0.3, 0.45, 0.6]

        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)

            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()

                let barWidth: CGFloat = 2.0
                let gap: CGFloat = 2.5
                let radius: CGFloat = 1.5
                let centerX = rect.midX
                let centerY = rect.midY

                let totalWidth = CGFloat(baseHeights.count) * barWidth + CGFloat(baseHeights.count - 1) * gap
                let startX = centerX - totalWidth / 2

                for (i, baseHeight) in baseHeights.enumerated() {
                    let phase = t - phaseOffsets[i]
                    let scale = minScale + (1.0 - minScale) * CGFloat((sin(phase * 2.0 * .pi) + 1.0) / 2.0)
                    let height = baseHeight * scale
                    let x = startX + CGFloat(i) * (barWidth + gap)
                    let y = centerY - height / 2
                    let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                    NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func startRecordingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderWaveFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % StatusBarController.waveFrameCount
            self.setIcon(self.animationFrames[self.animationFrame])
        }
    }

    // MARK: - Transcribing animation: smooth wave dots

    private static let transcribeFrameCount = 30

    private static func prerenderTranscribeFrames() -> [NSImage] {
        let count = transcribeFrameCount
        let maxBounce: CGFloat = 3.0
        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)

            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()

                let dotSize: CGFloat = 3
                let gap: CGFloat = 3.0
                let centerY = rect.midY - dotSize / 2
                let totalWidth = 3 * dotSize + 2 * gap
                let startX = rect.midX - totalWidth / 2

                for i in 0..<3 {
                    let phase = t - Double(i) * 0.15
                    let bounce = maxBounce * CGFloat(max(0, sin(phase * 2.0 * .pi)))
                    let x = startX + CGFloat(i) * (dotSize + gap)
                    let y = centerY + bounce
                    let dotRect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                    NSBezierPath(ovalIn: dotRect).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func startTranscribingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderTranscribeFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % StatusBarController.transcribeFrameCount
            self.setIcon(self.animationFrames[self.animationFrame])
        }
    }

    // MARK: - Downloading: progress ring

    private static let downloadPulseFrameCount = 30

    private static func prerenderDownloadPulseFrames() -> [NSImage] {
        let count = downloadPulseFrameCount
        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)
            let alpha = CGFloat(0.4 + 0.6 * (sin(t * 2.0 * .pi) + 1.0) / 2.0)
            return drawDownloadProgress(0, pulseAlpha: alpha)
        }
    }

    private func startDownloadingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderDownloadPulseFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.downloadPercent > 0 {
                self.setIcon(StatusBarController.drawDownloadProgress(self.downloadPercent))
            } else {
                self.animationFrame = (self.animationFrame + 1) % StatusBarController.downloadPulseFrameCount
                self.setIcon(self.animationFrames[self.animationFrame])
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrames = []
    }

    private func setIcon(_ image: NSImage) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                button.image = image
                button.image?.isTemplate = true
            }
        }
    }

    // MARK: - Custom drawn icons

    static func drawLogo(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()

            let barWidth: CGFloat = 2.0
            let gap: CGFloat = 2.5
            let radius: CGFloat = 1.5
            let centerX = rect.midX
            let centerY = rect.midY

            let heights: [CGFloat] = [4, 8, 12, 8, 4]
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            let startX = centerX - totalWidth / 2

            for (i, height) in heights.enumerated() {
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = centerY - height / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawDownloadProgress(_ percent: Double, pulseAlpha: CGFloat = 1.0) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.5
            let lineWidth: CGFloat = 1.8

            NSColor.black.withAlphaComponent(0.25 * pulseAlpha).setStroke()
            let bgCircle = NSBezierPath()
            bgCircle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            bgCircle.lineWidth = lineWidth
            bgCircle.stroke()

            if percent > 0 {
                NSColor.black.setStroke()
                let progressArc = NSBezierPath()
                let startAngle: CGFloat = 90
                let endAngle = startAngle - CGFloat(percent / 100.0) * 360.0
                progressArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                progressArc.lineWidth = lineWidth
                progressArc.lineCapStyle = .round
                progressArc.stroke()
            }

            NSColor.black.withAlphaComponent(pulseAlpha).setStroke()
            NSColor.black.withAlphaComponent(pulseAlpha).setFill()
            let arrowPath = NSBezierPath()
            arrowPath.move(to: NSPoint(x: center.x, y: center.y + 3))
            arrowPath.line(to: NSPoint(x: center.x, y: center.y - 3))
            arrowPath.lineWidth = 1.5
            arrowPath.lineCapStyle = .round
            arrowPath.stroke()

            let headPath = NSBezierPath()
            headPath.move(to: NSPoint(x: center.x - 2.5, y: center.y - 0.5))
            headPath.line(to: NSPoint(x: center.x, y: center.y - 3.5))
            headPath.line(to: NSPoint(x: center.x + 2.5, y: center.y - 0.5))
            headPath.lineWidth = 1.5
            headPath.lineCapStyle = .round
            headPath.lineJoinStyle = .round
            headPath.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawLockIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let centerX = rect.midX

            let bodyRect = NSRect(x: centerX - 4, y: 2, width: 8, height: 7)
            NSBezierPath(roundedRect: bodyRect, xRadius: 1.5, yRadius: 1.5).fill()

            let shacklePath = NSBezierPath()
            shacklePath.move(to: NSPoint(x: centerX - 2.5, y: 9))
            shacklePath.curve(to: NSPoint(x: centerX + 2.5, y: 9),
                              controlPoint1: NSPoint(x: centerX - 2.5, y: 15),
                              controlPoint2: NSPoint(x: centerX + 2.5, y: 15))
            shacklePath.lineWidth = 1.8
            shacklePath.lineCapStyle = .round
            shacklePath.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawCheckmarkIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()

            let centerX = rect.midX
            let centerY = rect.midY

            let path = NSBezierPath()
            path.move(to: NSPoint(x: centerX - 5, y: centerY + 1))
            path.line(to: NSPoint(x: centerX - 2, y: centerY - 3))
            path.line(to: NSPoint(x: centerX + 5, y: centerY + 4))
            path.lineWidth = 2.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawWarningIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let centerX = rect.midX

            // Triangle outline
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: centerX, y: 16))
            triangle.line(to: NSPoint(x: centerX - 7, y: 3))
            triangle.line(to: NSPoint(x: centerX + 7, y: 3))
            triangle.close()
            triangle.lineWidth = 1.5
            triangle.lineJoinStyle = .round
            triangle.stroke()

            // Exclamation mark
            let stemRect = NSRect(x: centerX - 0.75, y: 7, width: 1.5, height: 5)
            NSBezierPath(roundedRect: stemRect, xRadius: 0.75, yRadius: 0.75).fill()
            let dotRect = NSRect(x: centerX - 1, y: 4.5, width: 2, height: 2)
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

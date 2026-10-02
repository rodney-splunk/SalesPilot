import AppKit
import SwiftUI

final class CallPrepModel: ObservableObject {
    @Published var account = ""
    @Published var goal = ""
    @Published var people = ""
    @Published var notes = ""
    @Published var source = ""
    @Published var reviewed = ""
    @Published var saved: [URL] = []
    @Published var status: String? = nil
    @Published var busy = false
    private var requestID = UUID()
    private let preferences: UserDefaults
    private var draft: CallPrepDraft { CallPrepDraft(account: account, goal: goal, people: people, notes: notes, source: source, reviewed: reviewed) }
    var isEmpty: Bool { draft.isEmpty }
    var savedState: String {
        guard let text = try? String(contentsOf: active, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return isEmpty ? "No context saved" : "Draft · save before starting" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == draft.text.trimmingCharacters(in: .whitespacesAndNewlines) ? "Saved for your next call" : "Unsaved edits · next call still uses the saved copy"
    }
    private var active: URL { SessionCapture.sessionsDir.appendingPathComponent("prep.txt") }
    private var directory: URL { SessionCapture.sessionsDir.appendingPathComponent("prep", isDirectory: true) }
    init(preview: Bool = false, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if preview {
            account = "Buttercup Enterprises"
            goal = "Understand where investigations slow down and agree on a useful next step."
            people = "Dana Reyes, Security Operations; Marcus Chen, Infrastructure"
            notes = "The team checks four consoles during investigations.\n\nExplore the workflow and the effect on triage SLAs. Confirm assumptions with the customer."
        } else {
            if let text = try? String(contentsOf: active, encoding: .utf8) { apply(CallPrepDraft(text: text)) }
            reloadSaved()
        }
    }
    private func apply(_ value: CallPrepDraft) { account = value.account; goal = value.goal; people = value.people; notes = value.notes; source = value.source; reviewed = value.reviewed }
    private func reloadSaved() {
        saved = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func load(_ url: URL) {
        do { apply(CallPrepDraft(text: try String(contentsOf: url, encoding: .utf8))); if source.isEmpty { source = url.lastPathComponent }; status = "Loaded for review. Save when you are ready to use it." }
        catch { status = "Could not read these notes." }
    }
    func importNotes() {
        let picker = NSOpenPanel()
        picker.allowedFileTypes = ["txt", "md", "markdown"]
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        load(url)
    }
    func save() {
        guard !draft.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            reviewed = ISO8601DateFormatter().string(from: Date())
            try draft.text.write(to: directory.appendingPathComponent(draft.slug + ".txt"), atomically: true, encoding: .utf8)
            try draft.text.write(to: active, atomically: true, encoding: .utf8)
            preferences.set(draft.savedName, forKey: "prepName")
            preferences.set(draft.slug, forKey: "prepActive")
            reloadSaved()
            status = LiveState.shared.listening ? "Saved for the next call. The current call keeps the context it started with." : "Saved and ready for your next call. Edit or clear it here before starting."
            NotificationCenter.default.post(name: .callPrepChanged, object: nil)
        } catch { status = "Could not save your context: \(error.localizedDescription)" }
    }
    func clearActive() {
        do {
            if FileManager.default.fileExists(atPath: active.path) { try FileManager.default.removeItem(at: active) }
            preferences.removeObject(forKey: "prepName")
            preferences.removeObject(forKey: "prepActive")
            apply(CallPrepDraft())
            status = "Next-call context cleared. Saved copies and the current call are unchanged."
            NotificationCenter.default.post(name: .callPrepChanged, object: nil)
        } catch { status = "Could not clear the active context." }
    }
    func findMeeting() {
        guard !busy, let controller = (NSApp.delegate as? AppDelegate)?.statusBar else { return }
        busy = true; status = "Looking for your next Outlook meeting…"
        controller.nextOutlookMeeting { [weak self] subject, when, attendees in
            guard let self else { return }
            self.busy = false
            guard !subject.isEmpty else { self.status = "No upcoming meeting found. You can enter the account and people below."; return }
            if self.account.isEmpty { self.account = subject }
            if self.people.isEmpty { self.people = attendees }
            self.status = "Next meeting: \(subject), \(when). Review the account name before looking up context."
        }
    }
    func findAccountContext() {
        let query = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !query.isEmpty else { return }
        let id = UUID(); requestID = id
        busy = true; status = "Finding account context in Slack and Salesforce…"
        let process = Process()
        guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            busy = false; status = "Account lookup is unavailable. You can paste notes below."; return
        }
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [WorkspacePaths.engine.appendingPathComponent("ghost-prep.mjs").path, "--draft", query]
        process.currentDirectoryURL = WorkspacePaths.engine
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = FileManager.default.homeDirectoryForCurrentUser.path + "/go/bin:/opt/homebrew/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + 150) { [weak self] in
                    guard let self, self.requestID == id, self.busy else { return }
                    self.requestID = UUID(); self.busy = false
                    self.status = "Account lookup took too long. Your draft is unchanged; try again or paste notes."
                    if process.isRunning { process.terminate() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                DispatchQueue.main.async {
                    guard let self, self.requestID == id else { return }
                    self.busy = false
                    guard process.terminationStatus == 0, let text = report?["content"] as? String, !text.isEmpty else {
                        self.status = "Could not build account context. Check your connected accounts or paste your notes."; return
                    }
                    let prepared = CallPrepDraft(text: text)
                    self.notes = self.notes.isEmpty ? prepared.notes : self.notes + "\n\nAccount research:\n" + prepared.notes
                    let sources = (report?["sources"] as? [String] ?? []).joined(separator: ", ")
                    self.source = sources.isEmpty ? self.source : sources
                    let missing = (report?["needAuth"] as? [String] ?? []).joined(separator: ", ")
                    self.status = "Draft ready" + (sources.isEmpty ? "." : " from \(sources).") + (missing.isEmpty ? "" : " Could not access \(missing).") + " Review and save to use it."
                }
            } catch {
                DispatchQueue.main.async { guard let self, self.requestID == id else { return }; self.busy = false; self.status = "Account lookup is unavailable. Your notes are unchanged." }
            }
        }
    }
}

struct CallPrepView: View {
    @ObservedObject var model: CallPrepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("CALL CONTEXT", systemImage: "sparkle").font(.system(size: 10, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                    Text("Walk in prepared.").font(.system(size: 27, weight: .medium, design: .rounded))
                    Text("Give the coach the people, purpose, and background for your next conversation.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { CallPrepWindow.shared.close() }.buttonStyle(.bordered)
            }
            HStack(spacing: 10) {
                Button { model.findMeeting() } label: { Label("Use next meeting", systemImage: "calendar") }
                Button { model.findAccountContext() } label: { Label("Find account context", systemImage: "magnifyingglass") }
                    .disabled(model.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { model.importNotes() } label: { Label("Import notes", systemImage: "doc") }
            }.disabled(model.busy)
            VStack(alignment: .leading, spacing: 14) {
                field("ACCOUNT OR CUSTOMER", placeholder: "Who are you meeting?", text: $model.account)
                field("CALL GOAL", placeholder: "What would make this conversation useful?", text: $model.goal)
                field("SOURCE / REFERENCE", placeholder: "Salesforce briefing, prior recap or a source URL", text: $model.source)
                if !model.reviewed.isEmpty { Text("Last reviewed: " + model.reviewed).font(.caption).foregroundStyle(.secondary) }
                field("PEOPLE", placeholder: "Jesse Yang — customer, security director; Rodney White — Splunk, host", text: $model.people)
            }.disabled(model.busy)
            VStack(alignment: .leading, spacing: 8) {
                Text("BACKGROUND & NOTES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                TextEditor(text: $model.notes).font(.system(size: 13)).padding(8)
                    .frame(minHeight: 150).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.16)))
                    .accessibilityLabel("Background and notes").disabled(model.busy)
                Text("Use exact name spellings in People. Names appear in the roster; introductions connect them to voices. Label assumptions in your notes.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !model.saved.isEmpty {
                Menu("Load saved context") {
                    ForEach(model.saved, id: \.path) { file in
                        Button(file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")) { model.load(file) }
                    }
                }.fixedSize().disabled(model.busy)
            }
            if let status = model.status {
                HStack { if model.busy { ProgressView().controlSize(.small) }; Text(status).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Text(model.savedState).font(.system(size: 11, weight: .medium)).foregroundStyle(SalesPilotStyle.accent)
            Divider()
            HStack {
                Button("Clear next-call context") { model.clearActive() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text(LiveState.shared.listening ? "Current call keeps its starting context" : "Saved context is used at call start").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Save for next call") { model.save() }.buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(SalesPilotStyle.buttonFill, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
                    .opacity(model.isEmpty || model.busy ? 0.5 : 1)
                    .disabled(model.isEmpty || model.busy).keyboardShortcut("s", modifiers: .command)
            }.disabled(model.busy)
        }.padding(28).frame(minWidth: 670, minHeight: 650).background(Color(nsColor: .windowBackgroundColor))
    }
    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(.system(size: 13)).accessibilityLabel(label)
        }
    }
}

final class CallPrepWindow {
    static let shared = CallPrepWindow()
    private var window: NSWindow?
    private var model: CallPrepModel?
    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "SalesPilot · Call context"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 700, height: 720)
            let draft = CallPrepModel(); model = draft
            panel.contentView = NSHostingView(rootView: CallPrepView(model: draft))
            panel.center(); window = panel
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func close() { window?.orderOut(nil) }
}

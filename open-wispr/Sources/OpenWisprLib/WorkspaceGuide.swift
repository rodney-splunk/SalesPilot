import SwiftUI
import AppKit

struct WorkspaceGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    private let titles = ["Prepare one useful conversation", "Keep the right voice attached to the words", "Follow the thread, then go deeper", "Check answers and capture the facts", "Review before you share"]
    private let locations = ["Toolbar → Call style · Framework · More → Call context", "People strip → Speaker name and team", "Coach → Next Move · Discovery coverage", "Research → Answers · Competition · Notes", "More → Past calls · Review recap"]
    private let examples = ["Goal: Understand why firewall-log handoffs delay investigations.", "Jesse Yang — Customer, security director. Rodney White — Splunk, host.", "Customer: Our analysts wait six hours for firewall logs.\n\nSay next: When that wait happens, what does it mean for an urgent investigation?", "Customer: We ingest 45 GB of Palo Alto firewall logs daily.\n\nNotes retain the source and quantity. A question about ingestion opens a documentation search.", "Check the recap against the transcript. Edit the draft, copy it or export it when it is ready."]
    private let details = ["Choose Standard for flexible coaching or Discovery only to keep today focused on needs and shape a tailored demo for a next step. Before you join checks permissions, your selected microphone, local models and documentation access without recording. Notify participants and confirm required consent before capture. Add a goal, current-call names and exact spellings. Review the source and date of a saved brief; save deliberately. Unsaved edits do not change the live call.", "Introductions connect names to voices during this call. A mention of Hunter's previous demo does not put Hunter on the call. Correct a speaker's name and team in the people strip; the correction applies to that voice. Overlapping or unresolved speech stays flagged for review. There is no saved people library.", "Next Move follows the current topic and earlier answers. If the customer is still finishing a thought, listen. Click a framework point to see the transcript evidence and what remains open. Explore technical workflow first, then an actual business consequence and personal responsibility when relevant.", "A product question triggers documentation lookup. Competitive comparisons open Research → Competition; the arrow on Coach takes you there. Opportunities shares the Research section. Searching, answer ready and needs confirmation are different states. Read the sources before using an answer. Generated answers remain unresolved until you mark them answered or defer them. Notes preserve customer statements and corrections; In transcript opens their evidence.", "End the call to generate its recap. Past calls sits under More. Check facts, names, agreed actions and unanswered questions. Export is a deliberate local action; nothing is sent to email or Salesforce from this screen. Recovered transcript sections require review."]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("SALESPILOT / QUICK START", systemImage: "waveform.path").font(.system(size: 11, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent); Spacer(); Button("Skip for now") { dismiss() }.buttonStyle(.plain) }
            HStack(spacing: 8) { ForEach(0..<5) { i in Capsule().fill(i <= page ? SalesPilotStyle.accent : SalesPilotStyle.accent.opacity(0.12)).frame(height: 4) } }
            Text(titles[page]).font(.system(size: 27, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(locations[page]).font(.callout.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
            ScrollView { VStack(alignment: .leading, spacing: 20) {
                Text(examples[page]).font(.system(size: 17, weight: .medium, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(SalesPilotStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                Text(details[page]).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Illustrative example · Reopen through More → Quick guide").font(.caption).foregroundStyle(.tertiary)
            } }
            HStack { Text("\(page + 1) of 5").font(.caption).foregroundStyle(.secondary); Spacer(); if page > 0 { Button("Back") { page -= 1 } }; Button(page == 4 ? "Explore the example" : "Next") { if page < 4 { page += 1 } else { dismiss(); DispatchQueue.main.async { SessionStore.showExample() } } }.buttonStyle(.borderedProminent).tint(SalesPilotStyle.buttonFill) }
        }.padding(28).frame(width: 650, height: 620).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PastCallsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var calls: [(URL, SessionData)] {
        let directory = WorkspacePaths.root.appendingPathComponent("sessions/history")
        let urls = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url), let session = try? JSONDecoder().decode(SessionData.self, from: data) else { return nil }
            return (url,session)
        }.filter { query.isEmpty || (($0.1.name ?? $0.1.title) + " " + $0.1.subtitle).localizedCaseInsensitiveContains(query) }
    }
    private func callDate(_ url: URL) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        guard let date = parser.date(from: String(url.deletingPathExtension().lastPathComponent.prefix(19))) else { return "Saved call" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Past calls").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Open a saved call to review its transcript, notes, answers and opportunities.").foregroundStyle(.secondary)
            TextField("Search calls or people", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if calls.isEmpty { Text(query.isEmpty ? "No archived calls yet. Finished calls will appear here." : "No matching calls.").foregroundStyle(.secondary).padding(24) }
                    ForEach(calls, id: \.0) { url, call in
                        Button {
                            guard !LiveState.shared.listening, !LiveState.shared.starting, !LiveState.shared.finishing else { return }
                            SessionStore.reviewSelection = call
                            SessionStore.showingExample = false
                            NotificationCenter.default.post(name: .reloadSession, object: nil)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(call.name ?? call.title).font(.headline)
                                Text(call.subtitle).font(.caption).foregroundStyle(.secondary)
                                Text("\(call.framework) · \(call.turns.count) turns · \(callDate(url))").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(LiveState.shared.listening || LiveState.shared.starting || LiveState.shared.finishing)
                    }
                }
            }
        }.padding(24).frame(width: 600, height: 530)
    }
}

struct RecapReview: View {
    let session: SessionData
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var draft = ""
    @State private var status: String?
    private var original: String {
        var parts = [session.recap ?? ""]
        parts += (session.nextSteps ?? []).map { "Next step: " + $0 }
        parts += (session.followups ?? []).map { "Follow up: " + $0 }
        parts += (session.customerQuestions ?? []).filter { !["answered", "deferred"].contains($0.status) }.map { "Unresolved question (" + $0.speaker + "): " + $0.q }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Review recap").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Review names, facts and agreed actions. Edits affect this sharing draft; the recorded transcript remains the evidence.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $draft).font(.system(size: 13)).padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button(copied ? "Copied" : "Copy recap") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft, forType: .string); copied = true }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Export draft…") { export() }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Restore generated recap") { draft = original; copied = false }
            }
            Text("Nothing is sent to email or Salesforce. Export saves a file you can review and share.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 640, height: 520).background(Color(nsColor: .windowBackgroundColor)).onAppear { draft = original }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedFileTypes = ["md", "txt"]; panel.nameFieldStringValue = "Call recap.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try draft.write(to: url, atomically: true, encoding: .utf8); status = "Draft exported." } catch { status = "Could not export: " + error.localizedDescription }
    }
}

extension Notification.Name {
    static let showPastCalls = Notification.Name("ShowPastCalls")
    static let showRecapReview = Notification.Name("ShowRecapReview")
    static let showSpeakingInsights = Notification.Name("ShowSpeakingInsights")
}

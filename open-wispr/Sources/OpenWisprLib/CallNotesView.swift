import SwiftUI
import AppKit

struct CallNote: Codable, Identifiable {
    var id: String
    var turnId: Int?
    var quote: String
    var categories: [String]
    var speaker: String
    var speakerUnconfirmed: Bool
    var tentative: Bool
    var at: String?
    var startedAt: Double?
    var supersededBy: Int? = nil
    var correctsTurnId: Int? = nil
    var context: String? = nil
    var sourceTurnIds: [Int]? = nil
    var evidenceQuotes: [String]? = nil
    var provenance: String? = nil
    var correction: Bool
}

struct CallNotesView: View {
    let notes: [CallNote]
    var reveal: (String) -> Void
    private let groups = [("technical", "Environment & workflow"), ("business", "Business impact"), ("personal", "People & priorities"), ("outcomes", "Desired outcomes"), ("next_steps", "Next steps discussed")]
    private func group(_ note: CallNote) -> String {
        if note.categories.contains("next_steps") { return "next_steps" }
        if note.categories.contains("personal") { return "personal" }
        if note.categories.contains("outcomes") { return "outcomes" }
        if note.categories.contains("business") { return "business" }
        return "technical"
    }
    private var copyText: String {
        groups.compactMap { id, title in
            let rows = notes.filter { group($0) == id }
            guard !rows.isEmpty else { return nil }
            return title + "\n" + rows.map { "• \($0.quote) [\($0.speaker)\($0.speakerUnconfirmed ? "; team affiliation unconfirmed" : "")\($0.tentative ? "; approximate or uncertain" : "")\($0.context.map { "; context: " + $0 } ?? "")\($0.supersededBy != nil ? "; superseded by a later correction" : "")]" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Captured notes").font(.system(size: 21, weight: .semibold, design: .rounded))
                        Text("Customer statements, collected as the call unfolds.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy notes") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    }.disabled(notes.isEmpty)
                }
                Text("Numbers and units stay as spoken. New corrections remain visible beside earlier statements. Check speaker roles and uncertain details before using these notes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if notes.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "note.text").font(.system(size: 24)).foregroundStyle(SalesPilotStyle.accent)
                        Text("Keep listening. We’ll capture the details.").font(.headline)
                        Text("Environment, current workflow, impact, priorities, and next steps appear here when the customer describes them.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(groups, id: \.0) { id, title in
                    let rows = notes.filter { group($0) == id }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                                Spacer()
                                Text("\(rows.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(rows) { note in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(note.quote).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                    if let context = note.context, !context.isEmpty { Text("Context: " + context).font(.system(size: 11)).foregroundStyle(SalesPilotStyle.accent) }
                                    HStack {
                                        Text(note.speaker).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                        if !note.tentative { Text("Customer-stated").font(.system(size: 10)).foregroundStyle(.secondary) }
                                        if note.speakerUnconfirmed { Text("Team unconfirmed").font(.system(size: 10)).foregroundStyle(.orange) }
                                        if note.tentative { Text("Uncertain statement").font(.system(size: 10)).foregroundStyle(.orange) }
                                        if note.supersededBy != nil { Text("Earlier detail · corrected").font(.system(size: 10)).foregroundStyle(.secondary) }
                                        if note.correction { Text("Correction").font(.system(size: 10)).foregroundStyle(SalesPilotStyle.accent) }
                                        Spacer()
                                        Button { reveal(note.evidenceQuotes?.first ?? note.quote) } label: { Label("In transcript", systemImage: "text.quote") }
                                            .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(SalesPilotStyle.accent)
                                    }
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI

struct CompetitiveResource: Codable, Identifiable {
    var title: String; var url: String; var scope: String; var verifiedAt: String
    var id: String { url }
}
struct CompetitiveSignal: Codable, Identifiable {
    var id: String; var name: String; var quote: String; var speaker: String; var turnId: Int?
    var probe: String; var themes: [String]; var resources: [CompetitiveResource]
}
struct DiscoveryFocusView: View {
    var body: some View {
        CollapsibleSection("Discovery first", detail: "Define what a tailored demo should prove", initialExpanded: false) {
            Text("Acknowledge demo requests, explain today’s discovery purpose, then ask what they need the next demo to prove.").font(.callout).foregroundStyle(.secondary)
            ForEach(["Technical · Walk me through one investigation today.", "Business · What does that delay affect for the team?", "Personal · What does that extra work take you away from?"], id: \.self) { Text($0).font(.system(size: 12)).padding(.top, 5) }
            Text("Use the layer that fits their answer. Product and competitive questions still get sourced answers.").font(.caption).foregroundStyle(.secondary).padding(.top, 7)
        }
    }
}
struct CompetitionView: View {
    let signals: [CompetitiveSignal]
    let current: LiveAnswer?
    let history: [LiveAnswer]
    let questions: [CustomerQuestion]
    let canResolve: Bool
    var onEvidence: (String) -> Void
    private var competitiveAnswers: [LiveAnswer] { history.filter { $0.category == "competition" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label("Competition", systemImage: "point.3.connected.trianglepath.dotted").font(.system(size: 22, weight: .semibold, design: .rounded)); Spacer(); Text("CORE FIRST").font(.system(size: 9, weight: .bold)).foregroundStyle(SalesPilotStyle.accent).padding(7).background(SalesPilotStyle.accent.opacity(0.08), in: Capsule()) }
                Text("A fair comparison, the customer’s criteria, and sources you can check. Competitor mentions are signals to explore—not proof of a weakness.").font(.system(size: 12)).foregroundStyle(.secondary)
                if let current, current.category == "competition" { LiveAnswerCard(answer: current) }
                ForEach(competitiveAnswers.indices.reversed(), id: \.self) { i in
                    if competitiveAnswers[i].q != current?.q { LiveAnswerCard(answer: competitiveAnswers[i]) }
                }
                ForEach(signals) { signal in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(signal.name).font(.headline); Spacer(); Text("Mentioned on call").font(.caption).foregroundStyle(.secondary) }
                        Button { onEvidence(signal.quote) } label: { VStack(alignment: .leading, spacing: 5) { Text(signal.quote).font(.callout).lineLimit(3); Text(signal.speaker + " · open transcript").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                        Divider()
                        Text("VALIDATE THE FIT").font(.system(size: 10, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                        Text(signal.probe).font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                        Text(signal.themes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        CollapsibleSection("Internal enablement", detail: "For your preparation; not customer evidence", initialExpanded: false) {
                            ForEach(signal.resources) { resource in
                                if let url = URL(string: resource.url), url.scheme == "https" {
                                    VStack(alignment: .leading, spacing: 3) { Link(resource.title, destination: url).font(.callout); Text(resource.scope).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 4)
                                }
                            }
                        }
                    }.padding(18).background(SalesPilotStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(SalesPilotStyle.accent.opacity(0.12)))
                }
                let tracked = questions.filter { $0.kind == "competition" }
                ForEach(tracked) { question in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.q).font(.callout); Text(question.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                        if canResolve && ["answered", "deferred"].contains(question.status) { Button("Reopen") { LiveCoach.shared.resolveQuestion(id: question.id, status: "open") }.font(.caption) }
                        else if canResolve { HStack { Button("Answered on call") { LiveCoach.shared.resolveQuestion(id: question.id, status: "answered") }; Button("Defer to follow-up") { LiveCoach.shared.resolveQuestion(id: question.id, status: "deferred") } }.font(.caption) }
                    }.padding(14).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
                if signals.isEmpty && competitiveAnswers.isEmpty && current?.category != "competition" {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Ready for a competitive question", systemImage: "bubble.left.and.bubble.right").font(.headline)
                        Text("“How does Splunk differ from Sumo Logic?” triggers a comparison here, with a shortcut from Coach. A simple mention also captures what the customer said and a question to understand their evaluation.").font(.callout).foregroundStyle(.secondary)
                        Text("We verify both sides. Price, performance and missing-feature claims remain unconfirmed without matching evidence.").font(.caption).foregroundStyle(.secondary)
                    }.padding(22).background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

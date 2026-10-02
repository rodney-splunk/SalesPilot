import SwiftUI
import AppKit

struct OpportunityEvidence: Codable { var quote: String; var turnId: Int?; var who: String; var roleUnconfirmed: Bool }
struct OpportunitySource: Codable { var title: String; var url: String }
struct SolutionOpportunity: Codable, Identifiable {
    var id: String; var name: String; var area: String; var status: String; var capability: String
    var evidence: [OpportunityEvidence]; var question: String; var businessQuestion: String; var personalQuestion: String
    var sources: [OpportunitySource]; var needsValidation: [String]; var ciscoContext: [String]; var ciscoExplanation: String; var contested: Bool
}
struct OpportunitiesView: View {
    let opportunities: [SolutionOpportunity]
    var reveal: (String) -> Void
    @AppStorage("ciscoCounterpartMode") private var ciscoMode = false
    private var handoff: String {
        opportunities.map { item in
            "Explore: \(item.name)\nCustomer evidence:\n" + item.evidence.map { "• \($0.who): \($0.quote)\($0.roleUnconfirmed ? " (speaker role unconfirmed)" : "")" }.joined(separator: "\n")
            + "\nDocumented capability: \(item.capability)\nValidate next: \(item.question)\nOpen points: " + item.needsValidation.joined(separator: " ")
            + "\nSources: " + item.sources.map(\.url).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Solution opportunities").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Start with Splunk Core: the data, search and investigation workflow. Additional applications appear when customer statements support exploring them.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Toggle("Cisco counterpart mode", isOn: $ciscoMode).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    if ciscoMode { Button("Copy handoff") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(handoff, forType: .string) }.disabled(opportunities.isEmpty) }
                }.font(.system(size: 12))
                if opportunities.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Listen for the customer's workflow", systemImage: "lightbulb").font(.headline)
                        Text("A product mention alone does not establish a need. Customer problems, consequences and desired outcomes will help identify capabilities to explore.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(opportunities) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.system(size: 17, weight: .semibold))
                                Text(item.area.capitalized).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.status).font(.system(size: 10, weight: .medium)).foregroundStyle(SalesPilotStyle.accent)
                        }
                        if item.contested { Text("Several capabilities may fit. Discovery has not distinguished them yet.").font(.system(size: 12)).foregroundStyle(.orange) }
                        Text(item.id == "core" && item.evidence.isEmpty ? "STARTING POINT · AWAITING CUSTOMER CONTEXT" : "WHAT WE HEARD").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(item.evidence.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.evidence[i].quote).font(.system(size: 13)).textSelection(.enabled)
                                HStack {
                                    Text(item.evidence[i].who + (item.evidence[i].roleUnconfirmed ? " · role unconfirmed" : "")).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("In transcript") { reveal(item.evidence[i].quote) }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(SalesPilotStyle.accent)
                                }
                            }
                        }
                        Divider()
                        Text("CAPABILITY TO EXPLORE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(item.capability).font(.system(size: 13))
                        if ciscoMode {
                            Text(item.ciscoExplanation).font(.system(size: 12)).foregroundStyle(.secondary)
                            if !item.ciscoContext.isEmpty {
                                Text("Cisco context the customer stated").font(.system(size: 11, weight: .medium))
                                ForEach(item.ciscoContext, id: \.self) { Text($0).font(.system(size: 12)) }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ASK NEXT").font(.system(size: 10, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                            Text(item.question).font(.system(size: 15, weight: .medium))
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(SalesPilotStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        DisclosureGroup("Go deeper when the answer earns it") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Business: " + item.businessQuestion)
                                Text("People: " + item.personalQuestion)
                            }.font(.system(size: 12)).padding(.top, 6)
                        }.font(.system(size: 12))
                        ForEach(item.sources, id: \.url) { source in
                            if let url = URL(string: source.url), url.scheme == "https" { Link(destination: url) { Label(source.title, systemImage: "book.closed") }.font(.system(size: 12)) }
                        }
                        Text(item.needsValidation.joined(separator: " ")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

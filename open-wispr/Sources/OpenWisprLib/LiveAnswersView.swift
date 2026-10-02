import SwiftUI

struct LiveAnswerCard: View {
    let answer: LiveAnswer
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(answer.category == "competition" ? "COMPETITIVE ANSWER" : "LIVE ANSWER", systemImage: "books.vertical").font(.system(size: 11, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                Spacer()
                Text(answer.requestFailed == true ? "Request failed" : answer.status == "searching" ? "Searching docs" : answer.status == "grounded" ? "Sources found" : "Needs confirmation")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(answer.status == "unverified" ? Color.orange : Color.secondary)
            }
            if answer.category == "competition" {
                Text("Documentation comparison · internal CI references are separate").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(answer.q).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if answer.status == "searching" { ProgressView().controlSize(.small) }
            Text(answer.displayAnswer).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            ForEach(answer.sources ?? [], id: \.self) { source in
                if let url = URL(string: source), url.scheme == "https" {
                    Link(destination: url) { Label(answer.sourceTitles?[source] ?? url.host ?? source, systemImage: "arrow.up.right") }.font(.system(size: 12))
                } else { Label(source, systemImage: "doc.text").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(SalesPilotStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SalesPilotStyle.accent.opacity(0.14)))
    }
}

struct LiveAnswersView: View {
    let current: LiveAnswer?
    let history: [LiveAnswer]
    var questions: [CustomerQuestion] = []
    var canResolve = false
    @Binding var category: String
    var signals: [CompetitiveSignal] = []
    var onEvidence: (String) -> Void
    private func includes(_ competitive: Bool) -> Bool { category == "all" || (competitive ? category == "competition" : category == "technical") }
    private var visibleQuestions: [CustomerQuestion] { questions.filter { includes($0.kind == "competition") } }
    private var visibleHistory: [LiveAnswer] {
        var seen = Set<String>()
        return Array(history.reversed().filter {
            let identity = $0.questionId.map { "question:\($0)" } ?? ($0.q + "\n" + $0.answer)
            return includes($0.category == "competition") && seen.insert(identity).inserted
        }.reversed())
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Answers").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Spacer()
                    Menu(category == "competition" ? "Competitive" : category == "technical" ? "Technical" : "All answers") {
                        Button("All answers") { category = "all" }
                        Button("Technical") { category = "technical" }
                        Button("Competitive") { category = "competition" }
                    }.fixedSize(horizontal: true, vertical: false).help("Technical: how a product works. Competitive: comparisons, alternatives and positioning.")
                }
                Text("Technical questions use product documentation. Competitive questions use comparison evidence and CI resources. Both stay here with their sources and open questions.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if !visibleQuestions.isEmpty {
                    CollapsibleSection("Customer questions", detail: "Stay open until answered or deferred", initialExpanded: true) {
                        ForEach(visibleQuestions) { question in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.q).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                Text(question.speaker + " · " + question.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                                if question.status != "searching", let answer = question.answer { Text(answer.displayAnswer).font(.callout).foregroundStyle(.secondary) }
                                if canResolve {
                                    HStack {
                                        if ["answered", "deferred"].contains(question.status) {
                                            Button("Reopen") { LiveCoach.shared.resolveQuestion(id: question.id, status: "open") }
                                        } else {
                                            Button("Answered on call") { LiveCoach.shared.resolveQuestion(id: question.id, status: "answered") }
                                            if question.status == "needs_confirmation" { Button("Retry search") { LiveCoach.shared.retryRequest(id: question.id) } }
                                            Button("Defer to follow-up") { LiveCoach.shared.resolveQuestion(id: question.id, status: "deferred") }
                                        }
                                    }.font(.caption)
                                }
                            }.padding(.vertical, 10)
                        }
                    }
                }
                if let current, includes(current.category == "competition") { LiveAnswerCard(answer: current) }
                ForEach(visibleHistory.indices.reversed(), id: \.self) { i in
                    if !visibleHistory[i].matchesQuestion(current) { LiveAnswerCard(answer: visibleHistory[i]) }
                }
                if category != "technical", !signals.isEmpty {
                    CollapsibleSection("Competitive context", detail: "Customer criteria and internal CI references", initialExpanded: false) {
                        CompetitiveContextCards(signals: signals, onEvidence: onEvidence)
                    }
                }
                if (current == nil || !includes(current?.category == "competition")) && visibleHistory.isEmpty && visibleQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category == "competition" ? "Ready for a competitive question" : "Ready for a product question", systemImage: "bubble.left.and.text.bubble.right").font(.headline)
                        Text(category == "competition" ? "For example: How does Splunk compare with Datadog for our investigation workflow?" : "For example: Can Splunk ingest our firewall logs? You can keep listening while the answer and sources appear.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Pricing comparisons need matching scope and a quote. The coach marks details it cannot verify for follow-up.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import Foundation

struct CallPrepDraft: Equatable {
    var account = ""
    var goal = ""
    var people = ""
    var notes = ""
    var source = ""
    var reviewed = ""
    var isEmpty: Bool { [account, goal, people, notes].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var text: String {
        if isEmpty { return "" }
        var lines: [String] = []
        for (label, value) in [("Account", account), ("Call goal", goal), ("People", people), ("Source", source), ("Reviewed", reviewed)] {
            let clean = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { lines.append("\(label): \(clean)") }
        }
        let context = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("\nContext:\n" + context)
        return lines.joined(separator: "\n") + "\n"
    }
    init(account: String = "", goal: String = "", people: String = "", notes: String = "", source: String = "", reviewed: String = "") {
        self.account = account; self.goal = goal; self.people = people; self.notes = notes; self.source = source; self.reviewed = reviewed
    }
    init(text: String) {
        let parts = text.components(separatedBy: "\nContext:\n")
        if parts.count > 1 {
            for line in parts[0].components(separatedBy: .newlines) {
                if line.hasPrefix("Account: ") { account = String(line.dropFirst(9)) }
                else if line.hasPrefix("Call goal: ") { goal = String(line.dropFirst(11)) }
                else if line.hasPrefix("People: ") { people = String(line.dropFirst(8)) }
                else if line.hasPrefix("Source: ") { source = String(line.dropFirst(8)) }
                else if line.hasPrefix("Reviewed: ") { reviewed = String(line.dropFirst(10)) }
            }
            notes = parts.dropFirst().joined(separator: "\nContext:\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            var lines = text.components(separatedBy: .newlines)
            if let first = lines.first, first.hasPrefix("Account: ") { account = String(first.dropFirst(9)); lines.removeFirst() }
            notes = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    var savedName: String {
        let name = account.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String((notes.components(separatedBy: .newlines).first ?? "Call notes").prefix(50)) : name
    }
    var slug: String {
        let clean = savedName.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let parts = clean.split(separator: "-").joined(separator: "-")
        return String((parts.isEmpty ? "call-notes" : parts).prefix(70))
    }
}

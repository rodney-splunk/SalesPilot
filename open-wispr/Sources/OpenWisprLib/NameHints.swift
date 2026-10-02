import Foundation

enum NameHints {
    static func callNames(_ session: [String: Any]) -> [String] {
        let turns = session["turns"] as? [[String: Any]] ?? []
        let people = session["roster"] as? [[String: Any]] ?? []
        let candidates = turns.filter { ($0["me"] as? Bool) == true }.compactMap { $0["who"] as? String } + people.compactMap { $0["name"] as? String }
        var seen = Set<String>()
        return Array(candidates.filter { name in
            !name.isEmpty && !["You", "Customer", "Mixed speakers", "Unconfirmed speaker", "Uncertain speaker", "Call audio", "Microphone"].contains(name) && !name.hasPrefix("Speaker ") && seen.insert(name.lowercased()).inserted
        }.prefix(8))
    }

    static func names(from prep: String) -> [String] {
        let explicit = #"(?im)^\s*(?:attendees?|on the call|participants?|people)\s*:\s*(.+)$"#
        let lineRE = try! NSRegularExpression(pattern: explicit)
        let ns = prep as NSString
        let lines = lineRE.matches(in: prep, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        let input = lines.isEmpty ? prep : lines.joined(separator: ", ")
        // Unicode names, including accents, internal apostrophes/hyphens and common particles.
        let word = #"\p{Lu}[\p{L}\p{M}]*(?:['’\-][\p{L}\p{M}]+)*"#
        let pattern = "(?<![\\p{L}\\p{M}])" + word + "(?:\\s+(?:(?:de|del|da|van|von|la|bin|al)\\s+)*" + word + "){1,3}"
        let re = try! NSRegularExpression(pattern: pattern)
        let text = input as NSString
        let roleWords: Set<String> = ["security", "operations", "director", "manager", "engineering", "engineer", "infrastructure", "enterprise", "cloud", "platform", "splunk", "cisco"]
        var seen = Set<String>(); var result: [String] = []
        for m in re.matches(in: input, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: m.range)
            let words = name.lowercased().split(separator: " ").map(String.init)
            if words.contains(where: { roleWords.contains($0) }) { continue }
            if seen.insert(name.lowercased()).inserted { result.append(name) }
        }
        return Array(result.prefix(8))
    }
}

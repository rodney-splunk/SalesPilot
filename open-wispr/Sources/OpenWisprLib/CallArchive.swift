import Foundation

enum CallArchive {
    static func preserveCurrent(session: URL, history: URL) throws {
        guard FileManager.default.fileExists(atPath: session.path) else { return }
        let data = try Data(contentsOf: session)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let turns = object["turns"] as? [[String: Any]], !turns.isEmpty else { return }
        let signature = try JSONSerialization.data(withJSONObject: turns, options: .sortedKeys)
        let previous = ((try? FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in previous {
            guard let archivedData = try? Data(contentsOf: file),
                  let archived = (try? JSONSerialization.jsonObject(with: archivedData)) as? [String: Any],
                  let archivedTurns = archived["turns"] as? [[String: Any]],
                  let candidate = try? JSONSerialization.data(withJSONObject: archivedTurns, options: .sortedKeys) else { continue }
            if candidate == signature { return }
        }
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().string(from: Date())
        object["archivedAt"] = now
        if object["name"] == nil { object["name"] = object["customerName"] ?? object["title"] ?? "Previous call" }
        let filename = now.replacingOccurrences(of: ":", with: "-") + "_" + UUID().uuidString.prefix(8) + ".json"
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: history.appendingPathComponent(filename), options: .atomic)
    }
}

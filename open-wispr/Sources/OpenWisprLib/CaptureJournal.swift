import Foundation

/// Independent of the coach: a failed provider or child process cannot discard captured turns.
enum CaptureJournal {
    private static let lock = NSLock()
    static var callID = UUID().uuidString
    static var url: URL { WorkspacePaths.root.appendingPathComponent("sessions/capture-journal.jsonl") }
    static func begin() throws {
        lock.lock(); defer { lock.unlock() }
        callID = UUID().uuidString
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func append(speaker: String, text: String, startedAt: Double?, endedAt: Double?) throws {
        lock.lock(); defer { lock.unlock() }
        var item: [String: Any] = ["callId": callID, "speaker": speaker, "text": text]
        if let startedAt { item["startedAt"] = startedAt }
        if let endedAt { item["endedAt"] = endedAt }
        var data = try JSONSerialization.data(withJSONObject: item); data.append(10)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize()
    }
    static func drop(text: String) {
        lock.lock(); defer { lock.unlock() }
        guard var data = try? JSONSerialization.data(withJSONObject: ["callId": callID, "drop": text]), let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }; data.append(10)
        try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.synchronize()
    }
    static func recover(session: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let raw = try String(contentsOf: url, encoding: .utf8)
        let events = raw.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        var rows: [[String: Any]] = []
        for event in events {
            if let drop = event["drop"] as? String { if let index = rows.lastIndex(where: { $0["text"] as? String == drop }) { rows.remove(at: index) } }
            else if (event["text"] as? String)?.isEmpty == false { rows.append(event) }
        }
        guard let id = rows.first?["callId"] as? String else { return }
        let old = (try? Data(contentsOf: session)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        var value: [String: Any] = old?["callId"] as? String == id ? old! : ["title": "Recovered call", "subtitle": "Recovered transcript · review speaker identities", "framework": "SPIN", "coveragePct": 0, "coverage": [], "nextq": [], "followups": [], "turns": []]
        var turns = value["turns"] as? [[String: Any]] ?? []
        var added = false
        for row in rows {
            let me = row["speaker"] as? String == "you"
            let text = row["text"] as? String ?? ""
            if turns.contains(where: { ($0["me"] as? Bool) == me && ($0["text"] as? String == text || $0["rawText"] as? String == text) && ($0["startedAt"] as? Double) == (row["startedAt"] as? Double) }) { continue }
            var turn: [String: Any] = ["id": (turns.compactMap { $0["id"] as? Int }.max() ?? 0) + 1, "me": me, "who": me ? "Microphone" : "Call audio", "side": "unknown", "text": text, "time": "Recovered", "recovered": true]
            turn["startedAt"] = row["startedAt"]; turn["endedAt"] = row["endedAt"]
            turns.append(turn); added = true
        }
        guard added else { return }
        turns.sort { ($0["startedAt"] as? Double ?? 0) < ($1["startedAt"] as? Double ?? 0) }
        value["turns"] = turns; value["callId"] = id; value["recoveryNotice"] = "Some turns were recovered from capture. Review their speaker identity and notes."
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: session, options: .atomic)
    }
}

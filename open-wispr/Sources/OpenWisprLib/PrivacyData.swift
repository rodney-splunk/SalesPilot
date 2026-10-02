import Foundation

enum ComplianceAudit {
    private static let lock = NSLock()
    static func record(_ event: String, fields: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        let url = SessionCapture.sessionsDir.appendingPathComponent("compliance-audit.jsonl")
        var value = fields.filter { ["processingMode", "noticeVersion", "result"].contains($0.key) }
        value["event"] = event; value["at"] = ISO8601DateFormatter().string(from: Date()); value["callId"] = CaptureJournal.callID
        guard var data = try? JSONSerialization.data(withJSONObject: value) else { return }; data.append(10)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if let handle = try? FileHandle(forWritingTo: url) { defer { try? handle.close() }; try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.synchronize() }
    }
}

struct RetentionPolicy: Codable {
    var days: Int = 0
    var reference: String = ""
    var holds: [String] = []
    var reviewedAt: String = ""
    static var url: URL { SessionCapture.sessionsDir.appendingPathComponent("retention-policy.json") }
    static func load() -> Self { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self() }
    func save() throws { try JSONEncoder().encode(self).write(to: Self.url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path) }
    func needsReview(file: URL, modified: Date) -> Bool {
        days > 0 && !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !holds.contains(file.lastPathComponent) && Date().timeIntervalSince(modified) > Double(days) * 86400
    }
}


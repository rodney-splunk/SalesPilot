// SessionCapture.swift — bridge from dictation to the review pipeline.
// Every finished dictation is appended (as a customer turn) to
// ~/Documents/sales-copilot/sessions/dictation.log, which build-session.mjs turns into
// latest.json for ReviewView. This is the "real mic → engine → review window" seam.

import Foundation

enum SessionCapture {
    static var sessionsDir: URL {
        let dir = WorkspacePaths.root.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }
    static var logURL: URL { sessionsDir.appendingPathComponent("dictation.log") }

    /// Clear the transcript so the next dictation starts a fresh call.
    static func startNewCall() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }

    /// Legacy single-arg append (push-to-talk dictation) — treated as a customer turn.
    static func append(_ text: String) { appendCustomer(text) }
    static func appendYou(_ text: String) { write("me: ", text) }
    static func appendCustomer(_ text: String) { write("cust: ", text) }

    private static func write(_ prefix: String, _ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        guard let data = (prefix + line + "\n").data(using: .utf8) else { return }
        let url = logURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }
}

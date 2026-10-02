// EngineRunner.swift — runs the local coaching engine (build-session.mjs) over the captured
// dictation for a chosen methodology, then calls back so the UI can reload latest.json.

import Foundation

enum EngineRunner {
    /// Run the engine for `framework` (e.g. "meddic", "spin", "challenger"); completion on main.
    /// `live` suppresses the full-screen "Analyzing…" overlay (used for quiet per-turn updates).
    static func analyze(framework: String, live: Bool = false, completion: @escaping () -> Void) {
        if !live { DispatchQueue.main.async { NotificationCenter.default.post(name: .analysisStarted, object: nil) } }

        let engineDir = WorkspacePaths.engine
        let script = engineDir.appendingPathComponent("build-session.mjs")
        let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]

        guard let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              FileManager.default.fileExists(atPath: script.path) else {
            DispatchQueue.main.async { completion() }   // no engine reachable — reload whatever exists
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = [script.path, "--framework", framework]
        proc.currentDirectoryURL = engineDir
        proc.terminationHandler = { _ in DispatchQueue.main.async { completion() } }
        do { try proc.run() } catch { DispatchQueue.main.async { completion() } }
    }
}

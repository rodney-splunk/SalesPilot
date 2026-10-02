// WhisperServerPool.swift — runs persistent whisper-server processes (one per model) so the model
// loads ONCE and every transcription is inference-only. whisper-cli reloads the model on every call
// (~50% of each pass: measured 214ms load + 208ms inference for small.en); a resident server drops
// that to ~140ms total. Fails gracefully: inferenceURL returns nil until a server is ready, so callers
// fall back to whisper-cli in the meantime (or permanently if whisper-server isn't installed).

import Foundation
import Darwin

final class WhisperServerPool {
    static let shared = WhisperServerPool()
    private let lock = NSLock()
    private final class Server {
        let process: Process; let port: Int; var ready = false
        init(process: Process, port: Int) { self.process = process; self.port = port }
    }
    private var servers: [String: Server] = [:]   // model path -> server
    private static func freePort() -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0 else { return nil }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) } }
        return status == 0 ? Int(UInt16(bigEndian: address.sin_port)) : nil
    }

    static func findServerBinary() -> String? {
        for p in ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
        where FileManager.default.fileExists(atPath: p) { return p }
        return nil
    }

    /// A ready `/inference` URL for this model, or nil (launching the server in the background if needed).
    func inferenceURL(forModelPath path: String, threads: Int) -> URL? {
        lock.lock()
        if let s = servers[path], s.process.isRunning {
            let url = s.ready ? URL(string: "http://127.0.0.1:\(s.port)/inference") : nil
            lock.unlock(); return url
        }
        guard let bin = WhisperServerPool.findServerBinary() else { lock.unlock(); return nil }
        servers.removeValue(forKey: path)
        guard let port = Self.freePort() else { lock.unlock(); return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-m", path, "--host", "127.0.0.1", "--port", "\(port)", "-t", "\(threads)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { lock.unlock(); return nil }
        let server = Server(process: p, port: port)
        servers[path] = server
        lock.unlock()
        DispatchQueue.global().async { [weak self] in
            for _ in 0..<60 {   // up to ~30s for a big model to load
                guard p.isRunning else { self?.lock.lock(); if self?.servers[path] === server { self?.servers.removeValue(forKey: path) }; self?.lock.unlock(); return }
                if WhisperServerPool.ping(port: port) {
                    self?.lock.lock(); server.ready = true; self?.lock.unlock(); return
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
            p.terminate()
        }
        return nil
    }

    private static func ping(port: Int) -> Bool {
        guard let u = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: u); req.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] { ok = json["status"] == "ok" }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.2)
        return ok
    }

    /// Start loading these models now, so they're resident before audio flows.
    func prewarm(modelPaths: [String], threads: Int) {
        for p in modelPaths { _ = inferenceURL(forModelPath: p, threads: threads) }
    }

    func shutdownAll() {
        lock.lock(); defer { lock.unlock() }
        for (_, s) in servers { s.process.terminate() }
        servers.removeAll()
    }
}

import Foundation

/// App-lifetime memory only. Serializes concurrent reads; failed reads are never cached.
final class SessionCredentialCache {
    private let lock = NSLock()
    private var cached: Data?
    func read(refresh: Bool = false, loader: () throws -> Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if refresh { cached = nil }
        if let cached { return cached }
        let data = try loader()
        cached = data
        return data
    }
}

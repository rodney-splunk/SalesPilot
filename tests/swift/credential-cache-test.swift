import Foundation
let cache = SessionCredentialCache()
var loads = 0
func load() throws -> Data { loads += 1; return Data("synthetic".utf8) }
assert(try! cache.read(loader: load) == Data("synthetic".utf8))
assert(try! cache.read(loader: load) == Data("synthetic".utf8))
assert(loads == 1)
_ = try! cache.read(refresh: true, loader: load)
assert(loads == 2)
struct Failure: Error {}
do { _ = try cache.read(refresh: true) { throw Failure() }; assertionFailure("Expected failure") } catch {}
_ = try! cache.read(loader: load)
assert(loads == 3)
let concurrent = SessionCredentialCache()
var concurrentLoads = 0
DispatchQueue.concurrentPerform(iterations: 20) { _ in
    _ = try! concurrent.read { concurrentLoads += 1; Thread.sleep(forTimeInterval: 0.005); return Data("synthetic".utf8) }
}
assert(concurrentLoads == 1)
print("PASS app-session credential cache: repeated and concurrent access loads once, refresh invalidates, failure is not cached")

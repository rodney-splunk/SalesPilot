import Foundation
let root = FileManager.default.temporaryDirectory.appendingPathComponent("salespilot-privacy-" + UUID().uuidString)
enum SessionCapture { static var sessionsDir: URL { root } }
enum CaptureJournal { static var callID = "synthetic-current-call" }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
func check(_ name: String, _ value: Bool) { guard value else { print("FAIL " + name); exit(1) }; print("PASS " + name) }
let file = root.appendingPathComponent("synthetic.json"), old = Date().addingTimeInterval(-86400 * 31)
var policy = RetentionPolicy()
check("no invented retention period", !policy.needsReview(file: file, modified: old))
policy.days = 30; policy.reference = "Synthetic policy owner"
check("expired archive is flagged for review", policy.needsReview(file: file, modified: old))
policy.holds = [file.lastPathComponent]
check("held archive excluded from age review", !policy.needsReview(file: file, modified: old))
try policy.save(); check("policy and hold persist", RetentionPolicy.load().holds == policy.holds)
check("retention policy private permissions", (try FileManager.default.attributesOfItem(atPath: RetentionPolicy.url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
ComplianceAudit.record("consent-confirmed", fields: ["processingMode":"local", "noticeVersion":"synthetic", "transcript":"private text", "name":"private name"])
let audit = root.appendingPathComponent("compliance-audit.jsonl")
let value = try JSONSerialization.jsonObject(with: Data(contentsOf: audit)) as! [String:String]
check("audit has current call identity and excludes content", value["callId"] == CaptureJournal.callID && value["transcript"] == nil && value["name"] == nil)
check("audit private permissions", (try FileManager.default.attributesOfItem(atPath: audit.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
print("privacy data: 7/7 passed")

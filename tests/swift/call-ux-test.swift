import Foundation
var failures = 0, total = 0
func check(_ name: String, _ condition: Bool) { total += 1; if condition { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") } }
let ready = CallPresentation(listening: false, starting: false, finishing: false)
let live = CallPresentation(listening: true, starting: false, finishing: false)
check("ready state offers Start", ready.actionTitle == "Start live call" && ready.canToggle)
check("live state offers End even when started from another surface", live.actionTitle == "End live call" && live.canToggle)
check("startup disables duplicate starts", !CallPresentation(listening: true, starting: true, finishing: false).canToggle)
check("finishing takes priority and disables start", CallPresentation(listening: true, starting: true, finishing: true) == .finishing)
let original = CallPrepDraft(account: "Buttercup", goal: "Understand triage", people: "Dana, SecOps", notes: "Known workflow.\n\nAssumption to validate.\nContext:\nNested user notes.")
check("structured prep preserves all fields and multiline notes", CallPrepDraft(text: original.text) == original)
let goalOnly = CallPrepDraft(goal: "Agree on a next step")
check("goal-only prep survives reload", CallPrepDraft(text: goalOnly.text) == goalOnly)
check("empty draft cannot be saved as context", CallPrepDraft().isEmpty && CallPrepDraft().text.isEmpty)
let legacy = CallPrepDraft(text: "Account: Buttercup\n\nExisting account research.")
check("existing auto prep stays readable", legacy.account == "Buttercup" && legacy.notes == "Existing account research.")
check("plain pasted notes stay readable", CallPrepDraft(text: "Prior call notes").notes == "Prior call notes")
check("saved name cannot escape its directory", !CallPrepDraft(account: "../../客户 / Buttercup").slug.contains("/") && !CallPrepDraft(account: "../../客户").slug.isEmpty)
let root = FileManager.default.temporaryDirectory.appendingPathComponent("salespilot-call-ux-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let session = root.appendingPathComponent("latest.json"), history = root.appendingPathComponent("history")
let payload: [String: Any] = ["customerName":"Dana", "turns":[["id":1,"me":false,"text":"Keep this call.","startedAt":1.0]]]
let data = try JSONSerialization.data(withJSONObject: payload)
try data.write(to: session)
try CallArchive.preserveCurrent(session: session, history: history)
check("starting a call preserves an unarchived transcript", (try FileManager.default.contentsOfDirectory(atPath: history.path)).count == 1)
check("preservation leaves the current session untouched", try Data(contentsOf: session) == data)
try CallArchive.preserveCurrent(session: session, history: history)
check("already archived calls are not duplicated", (try FileManager.default.contentsOfDirectory(atPath: history.path)).count == 1)
try Data("{invalid".utf8).write(to: session)
var rejected = false
 do { try CallArchive.preserveCurrent(session: session, history: history) } catch { rejected = true }
check("damaged session blocks destructive replacement", rejected)
print("call UX: \(total-failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)

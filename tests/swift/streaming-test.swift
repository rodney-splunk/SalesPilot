import Foundation

// Stub only the speech model. The buffer, timestamping, WAV lifecycle and stop callbacks below
// exercise the real StreamingMicTranscriber without microphones, speakers or model loading.
final class Transcriber {
    let output: String
    init(_ output: String) { self.output = output }
    func transcribe(audioURL: URL) throws -> String { output }
    func transcribeDetailed(audioURL: URL) throws -> (String, [TimedWord]) { (output, []) }
}
var failures = 0
func check(_ name: String, _ result: Bool) {
    print("\(result ? "PASS" : "FAIL") \(name)")
    if !result { failures += 1 }
}
func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
}
let model = Transcriber("Our analysts investigate alerts in the legacy SIEM.")
let stream = StreamingMicTranscriber(live: model, final: model, speaker: "timing-unit", capturesMic: false)
var events: [String] = []
var capturedStart = 0.0, capturedEnd = 0.0
stream.onTurnFinalized = { text, wav, start, end in
    events.append("turn")
    capturedStart = start; capturedEnd = end
    if let wav = wav { try? FileManager.default.removeItem(atPath: wav) }
}
try stream.start()
let suppliedAt = Date().timeIntervalSince1970
stream.append(Array(repeating: Float(0.05), count: 19_200))
stream.stop { events.append("stopped") }
wait { events.contains("stopped") }
check("final turn delivered before stop completion", events == ["turn", "stopped"])
check("capture timestamps describe supplied audio, not processing completion", abs(capturedStart - (suppliedAt - 1.2)) < 0.2 && abs(capturedEnd - suppliedAt) < 0.2)
let tag = "artifact-unit-" + UUID().uuidString
let artifact = Transcriber("Thanks for watching.")
let silentStream = StreamingMicTranscriber(live: artifact, final: artifact, speaker: tag, capturesMic: false)
var stopped = false, committed = false, cleared = false
silentStream.onTurnFinalized = { _, _, _, _ in committed = true }
silentStream.onUpdate = { committed, provisional in if committed.isEmpty && provisional.isEmpty { cleared = true } }
try silentStream.start()
silentStream.append(Array(repeating: Float(0.05), count: 19_200))
silentStream.stop { stopped = true }
wait { stopped }
let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
check("fully stripped artifacts clear the provisional line", stopped && cleared && !committed)
check("discarded artifacts leave no diarization WAV", !leftovers.contains { $0.hasPrefix("owturn-" + tag + "-") })
check("stopped stream leaves no reusable raw WAV", !leftovers.contains { $0.hasPrefix("owstream-" + tag + "-") })
print("streaming lifecycle: \(5 - failures)/5 passed")
exit(failures == 0 ? 0 : 1)

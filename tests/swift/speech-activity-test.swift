import Foundation
var gate = SpeechActivity()
assert(gate.ingest(rms: 0, at: 100) == nil)
let onset = gate.ingest(rms: 0.04, at: 101)!
assert(onset.active && onset.voicedAt == 101)
assert(gate.ingest(rms: 0.04, at: 101.1) == nil)
assert(gate.ingest(rms: 0.04, at: 101.3)!.active)
assert(gate.ingest(rms: 0, at: 101.5) == nil)
let quiet = gate.ingest(rms: 0, at: 102)!
assert(!quiet.active && quiet.voicedAt == 101.3)
assert(gate.ingest(rms: 0, at: 103) == nil)
assert(gate.ingest(rms: 0.05, at: 104)!.active)
print("PASS audio activity onset, heartbeat, pause hold, quiet transition and resumption")

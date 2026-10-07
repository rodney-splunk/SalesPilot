#!/bin/bash
# Pure endpoint checks: no microphone, playback, credentials or customer files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT
cat > "$TASK_TMP/main.swift" <<'SWIFT'
import Foundation
func expect(_ actual: PracticeTurnGate.Event, _ expected: PracticeTurnGate.Event) { precondition(actual == expected, "Unexpected endpoint transition") }
var gate = PracticeTurnGate()
for _ in 0..<200 { expect(gate.ingest(db: -65, duration: 0.1, playback: false), .none) }
expect(gate.ingest(db: -18, duration: 0.05, playback: false), .none)
expect(gate.ingest(db: -65, duration: 0.1, playback: false), .none)
precondition(!gate.speaking)
expect(gate.ingest(db: -24, duration: 0.1, playback: false), .none)
expect(gate.ingest(db: -24, duration: 0.1, playback: false), .began)
for _ in 0..<9 { expect(gate.ingest(db: -65, duration: 0.1, playback: false), .none) }
expect(gate.ingest(db: -24, duration: 0.1, playback: false), .none)
for _ in 0..<12 { expect(gate.ingest(db: -65, duration: 0.1, playback: false), .none) }
expect(gate.ingest(db: -65, duration: 0.1, playback: false), .ended)
precondition(!gate.speaking)
gate.reset()
for _ in 0..<20 { expect(gate.ingest(db: -60, duration: 0.1, playback: true), .none) }
for _ in 0..<3 { expect(gate.ingest(db: -20, duration: 0.1, playback: true), .none) }
expect(gate.ingest(db: -20, duration: 0.1, playback: true), .began)
gate.reset()
_ = gate.ingest(db: -20, duration: 0.2, playback: false)
var finished = false
for _ in 0..<305 { if gate.ingest(db: -20, duration: 0.2, playback: false) == .ended { finished = true; break } }
precondition(finished)
gate.reset()
for level in [Double.nan, Double.infinity, -Double.infinity] { expect(gate.ingest(db: level, duration: 0.1, playback: false), .none) }
expect(gate.ingest(db: -20, duration: -1, playback: false), .none)
precondition(!gate.speaking)
// Ordinary speech has short unvoiced gaps between syllables. Weak speech must
// survive those gaps rather than requiring one uninterrupted loud vowel.
gate.reset()
var naturalStart = false
for _ in 0..<6 {
    for _ in 0..<4 { if gate.ingest(db: -52, duration: 0.02, playback: false) == .began { naturalStart = true } }
    for _ in 0..<3 { _ = gate.ingest(db: -80, duration: 0.02, playback: false) }
}
precondition(naturalStart, "Quiet natural speech was missed")
var naturalEnd = false
for _ in 0..<70 { if gate.ingest(db: -80, duration: 0.02, playback: false) == .ended { naturalEnd = true } }
precondition(naturalEnd)
gate.reset()
var quietInterrupt = false
for _ in 0..<8 {
    for _ in 0..<4 { if gate.ingest(db: -50, duration: 0.02, playback: true) == .began { quietInterrupt = true } }
    for _ in 0..<3 { _ = gate.ingest(db: -80, duration: 0.02, playback: true) }
}
precondition(quietInterrupt, "Quiet interruption was missed")
print("PASS: silence, transient noise, natural pauses, interruption onset, turn cap and reset")
var progress = PracticeInputProgress()
progress.accept("Dana, what happens while analysts wait?")
precondition(!progress.takeReply(recording: false, muted: false, queued: true))
progress.accept("   \n") // trailing noise must not drop the accepted question
precondition(progress.takeReply(recording: false, muted: false, queued: false))
precondition(!progress.takeReply(recording: false, muted: false, queued: false))
progress.accept("How does that affect your team?")
precondition(!progress.takeReply(recording: true, muted: false, queued: false))
precondition(!progress.takeReply(recording: false, muted: true, queued: false))
progress.reset() // mute/stop invalidates pending replies
precondition(!progress.takeReply(recording: false, muted: false, queued: false))
progress.accept("")
precondition(!progress.takeReply(recording: false, muted: false, queued: false))
print("PASS: accepted question survives queued noise, one reply, recording hold, mute/stop reset and blank-only input")
SWIFT
swiftc "$ROOT/open-wispr/Sources/OpenWisprLib/PracticeTurnGate.swift" "$ROOT/open-wispr/Sources/OpenWisprLib/PracticeInputProgress.swift" "$TASK_TMP/main.swift" -o "$TASK_TMP/check"
"$TASK_TMP/check"

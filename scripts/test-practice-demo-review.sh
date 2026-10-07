#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /private/tmp/salespilot-review-test.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/main.swift" <<'SWIFT'
import Foundation
let turn: [String: Any] = ["text": "<script>alert('x')</script>", "me": false, "coachQ": "What changed?"]
let data = try JSONSerialization.data(withJSONObject: ["turns": Array(repeating: turn, count: 8), "liveAnswer": ["q": "Example", "answer": "Saved", "sources": ["javascript:alert(1)", "https://help.splunk.com/example"]]])
let html = try PracticeDemoReview.render(data)
precondition(!html.contains("<script>")); precondition(html.contains("&lt;script&gt;"))
precondition(!html.contains("javascript:")); precondition(html.contains("https://help.splunk.com/example"))
precondition(html.contains("not a live call")); precondition(html.contains("What changed?"))
do { _ = try PracticeDemoReview.render(JSONSerialization.data(withJSONObject: ["turns": [turn]])); fatalError("Incomplete export accepted") } catch {}
print("PASS demo review: complete snapshot, escaped transcript, safe links, actual cue and honest offline scope")
SWIFT
swiftc open-wispr/Sources/OpenWisprLib/PracticeDemoReview.swift "$fixture/main.swift" -o "$fixture/test"
"$fixture/test"

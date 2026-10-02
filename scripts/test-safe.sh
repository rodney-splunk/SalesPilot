#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for name in discovery-purpose competition purpose-competition-flow dialogue-replay answer-policy docs-transport local-only full-call-continuity demo-checkpoint coach-pacing coverage-evidence opportunities fragment-flow speaker-continuity privacy security-transport runtime prepared-call-flow; do
  node "engine/test-$name.mjs"
done

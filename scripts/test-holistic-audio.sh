#!/bin/bash
# Uses file-only speech synthesis and ASR. Never selects/opens audio input/output devices.
set -euo pipefail
cd "$(dirname "$0")/.."
BINARY="${1:-$HOME/Applications/SalesPilot.app/Contents/MacOS/SalesPilot}"
FIXTURE_DIR=$(mktemp -d /private/tmp/salespilot-holistic-audio.XXXXXX)
mkdir "$FIXTURE_DIR/workspace"
say -r 170 -f tests/fixtures/holistic-call.txt -o "$FIXTURE_DIR/call.aiff"
ffmpeg -loglevel error -y -i "$FIXTURE_DIR/call.aiff" -ar 16000 -ac 1 "$FIXTURE_DIR/call.wav"
SALESPILOT_ROOT="$FIXTURE_DIR/workspace" SALESPILOT_VERIFY_AUDIO_OUTPUT="$FIXTURE_DIR/transcript.txt" "$BINARY" verify-audio-offline "$FIXTURE_DIR/call.wav"
node engine/test-holistic-audio.mjs "$FIXTURE_DIR/transcript.txt"
echo "Fictional test artifacts: $FIXTURE_DIR"

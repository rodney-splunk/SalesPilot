#!/bin/bash
# Swift-side unit checks that do not need XCTest. `swift test` cannot run in this environment
# (XCTest ships with Xcode, not the Command Line Tools), so these compile the real source files
# directly against a small main and assert on them.
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../open-wispr/Sources/OpenWisprLib"
OUT="${TMPDIR:-/tmp}/salespilot-swift-tests"
mkdir -p "$OUT"
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)
fail=0
for t in "$HERE"/*-test.swift; do
  name=$(basename "$t" -test.swift)
  # Top-level statements are only legal in a file called main.swift, so stage it under that name.
  mkdir -p "$OUT/$name.d" && cp "$t" "$OUT/$name.d/main.swift"
  if [ "$name" = "privacy-data" ]; then
    sources=("$SRC/PrivacyData.swift")
  elif [ "$name" = "capture-journal" ]; then
    sources=("$SRC/CaptureJournal.swift" "$SRC/WorkspacePaths.swift")
  elif [ "$name" = "name-hints" ]; then
    sources=("$SRC/NameHints.swift")
  elif [ "$name" = "speech-activity" ]; then
    sources=("$SRC/SpeechActivity.swift")
  elif [ "$name" = "speaker-labels" ]; then
    sources=("$SRC/SpeakerLookup.swift")
  elif [ "$name" = "call-ux" ]; then
    sources=("$SRC/CallPresentation.swift" "$SRC/CallPrepDraft.swift" "$SRC/CallArchive.swift")
  elif [ "$name" = "streaming" ]; then
    sources=("$SRC/SpeechActivity.swift" "$SRC/StreamingMicTranscriber.swift")
  else
    sources=("$SRC/SpeechActivity.swift" "$SRC/StreamingMicTranscriber.swift" "$SRC/Transcriber.swift" "$SRC/NameHints.swift" "$SRC/WorkspacePaths.swift" "$SRC/Config.swift" "$SRC/KeyCodes.swift" "$SRC/WhisperServerPool.swift" "$SRC/TextPostProcessor.swift")
  fi
  if [ "$name" != "name-hints" ] && [ "$name" != "speech-activity" ] && [ "$name" != "speaker-labels" ] && [ "$name" != "call-ux" ]; then sources+=("$SRC/TimedTranscript.swift"); fi
  if ! SDKROOT="$SDK" swiftc -O "${sources[@]}" \
      "$OUT/$name.d/main.swift" -o "$OUT/$name" 2>"$OUT/$name.err"; then
    echo "  FAIL  $name did not compile"; sed -n '1,5p' "$OUT/$name.err"; fail=1; continue
  fi
  "$OUT/$name" | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
done
exit $fail

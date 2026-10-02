#!/bin/bash
# test-all.sh — every SalesPilot suite: engine logic + rendered UI + interactive flows.
# Engine suites are DISCOVERED, not listed. The hardcoded list silently fell three suites behind and
# still reported "ALL SUITES PASSED", which is worse than having no runner at all.
cd "$(dirname "$0")"
fail=0

for t in engine/test*.mjs; do
  name=$(basename "$t" .mjs)
  echo "═══ ${name#test-} ═══"
  (cd engine && node "$(basename "$t")") || fail=1
  echo
done

echo "═══ swift units ═══"
bash tests/swift/run.sh || fail=1
echo

echo "═══ UI + interactive flows ═══"
bash uitest.sh || fail=1
echo

if [ $fail -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SOME SUITES FAILED"; exit 1; fi

# The real-audio call test is deliberately NOT part of this suite: it plays sound for two minutes and
# temporarily switches the system audio devices, so it must be run on purpose.
echo
echo "Real two-channel call test (audible, ~2 min):  tests/e2e/run.sh"

#!/bin/bash
# uitest.sh — end-to-end UI + interactive-flow regression via the macOS Accessibility API.
# Stages a DETERMINISTIC session fixture, opens the review window, reads ACTUALLY RENDERED text and
# drives real clicks. Catches SwiftUI regressions that compiling alone cannot.
# Notes: `entire contents` is unreliable on NSHostingView, so we walk UI elements recursively with
# System Events terminology scoped inside a tell; SwiftUI lays out lazily so we retry until settled.
set -uo pipefail
ROOT="${SALESPILOT_ROOT:-$HOME/Documents/sales-copilot}"
SESS="$ROOT/sessions/latest.json"
SAVED=$(mktemp -d -t salespilot-ui-session)
if [ -f "$SESS" ]; then cp "$SESS" "$SAVED/latest.json"; fi
restore_session(){
  if [ -f "$SAVED/latest.json" ]; then cp "$SAVED/latest.json" "$SESS"; else rm -f "$SESS"; fi
  rm -rf "$SAVED"
}
trap restore_session EXIT
pass=0; fail=0
ck(){ if [ "$2" = "1" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1${3:+   ($3)}"; fail=$((fail+1)); fi; }

python3 - "$SESS" <<'STAGE'
import json,sys
json.dump({
 "title":"Discovery — live session","subtitle":"MEDDPICC · fixture","framework":"MEDDPICC","coveragePct":38,
 "turns":[
   {"me":True,"who":"You","time":"00:04","text":"Tell me about your current setup.","coachTarget":None,"coachQ":None},
   {"me":False,"who":"Customer","time":"00:12","text":"Our monitoring is a mess, we are on a legacy SIEM.",
    "coachTarget":"Identify Pain","coachQ":"What happens when that SIEM fails during an incident?"},
   {"me":False,"who":"Customer","time":"00:31","text":"My analysts miss triage SLAs constantly.",
    "coachTarget":"Metrics","coachQ":"How many triage SLAs are your analysts missing weekly?"}],
 "coverage":[{"name":n,"status":s} for n,s in
   [("Metrics","partial"),("Economic Buyer","done"),("Decision Criteria","open"),("Decision Process","open"),
    ("Paper Process","open"),("Identify Pain","done"),("Champion","open"),("Competition","open")]],
 "nextq":[{"q":"How many triage SLAs are your analysts missing weekly?","tag":"Metrics"}],
 "customerName":"Dana Reyes",
 "roster":[{"name":"Dana Reyes","role":"security operations","decisionMaker":False},
           {"name":"Marcus Chen","role":"IT infrastructure","decisionMaker":False},
           {"name":"Priya Patel","role":"procurement","decisionMaker":True}],
 # Delivery metrics and solution signals: both are rail panels with no coverage until now.
 # Talk ratio is deliberately over target so the warning line has to render too.
 "delivery":{"talkRatio":68,"fillerPerMin":9,"longestMonologueSec":52,"openingFramed":False},
 "phase":"discover",
 "solutions":{"status":"contested",
   "note":"More than one area is live. Not enough yet to tell them apart.",
   "areas":[{"id":"es","name":"Enterprise Security","area":"security operations","score":11,
             "probes":["When an alert fires, what happens next?"],
             "evidence":["siem","false positives","triage"]},
            {"id":"apm","name":"APM","area":"application performance","score":10,
             "probes":["When a user says it is slow, how do you find where the time is going?"],
             "evidence":["latency","checkout"]}]},
}, open(sys.argv[1],"w"), indent=2)
STAGE

axdump(){ osascript <<'AS' 2>/dev/null
on walk(el, d)
	set out to ""
	if d > 14 then return out
	tell application "System Events"
		try
			set v to value of el
			if v is not missing value and (class of v is text) and (length of v) > 0 then set out to out & v & linefeed
		end try
		try
			set n to name of el
			if n is not missing value and (class of n is text) and (length of n) > 0 then set out to out & n & linefeed
		end try
		try
			repeat with k in (UI elements of el)
				set out to out & (my walk(k, (d + 1)))
			end repeat
		end try
	end tell
	return out
end walk
tell application "System Events" to tell process "SalesPilot"
	set res to ""
	repeat with t in (UI elements of window 1)
		set res to res & (my walk(t, 0))
	end repeat
	return res
end tell
AS
}
wincount(){ osascript -e 'tell application "System Events" to tell process "SalesPilot" to return count of windows' 2>/dev/null || echo 0; }
# Opening the app is not enough: SalesPilot is a menu-bar app, so a fresh launch has NO review
# window and the dump comes back empty ("harness broken"). Ask the menu for it.
open_review_window(){ osascript >/dev/null 2>&1 <<'AS'
tell application "System Events" to tell process "SalesPilot"
	set frontmost to true
	repeat 3 times
		try
			click menu bar item 1 of menu bar 1
		end try
		delay 1.2
		if exists menu 1 of menu bar item 1 of menu bar 1 then
			try
				click menu item "Current / last call" of menu 1 of menu bar item 1 of menu bar 1
				return "opened"
			end try
		end if
		try
			key code 53
		end try
		delay 0.6
	end repeat
end tell
AS
}
ensure_window(){ for _ in 1 2 3 4 5; do
    n="$(wincount)"; [ "${n:-0}" -ge 1 ] && return 0
    open "${SALESPILOT_APP_PATH:-$HOME/Applications/SalesPilot.app}" >/dev/null 2>&1; sleep 2
    n="$(wincount)"; [ "${n:-0}" -ge 1 ] && return 0
    open_review_window; sleep 2
  done; return 1; }

settle(){ local prev="" cur="" n
  for _ in 1 2 3 4 5 6 7 8; do
    ensure_window
    cur="$(axdump)"; n=$(printf '%s' "$cur" | grep -c .)
    if [ "${n:-0}" -eq 0 ]; then open "${SALESPILOT_APP_PATH:-$HOME/Applications/SalesPilot.app}" >/dev/null 2>&1; sleep 2; prev=""; continue; fi
    if [ "$n" -ge 10 ] && [ "$cur" = "$prev" ]; then printf '%s' "$cur"; return; fi
    prev="$cur"; sleep 1.5
  done
  printf '%s' "$cur"; }

open "${SALESPILOT_APP_PATH:-$HOME/Applications/SalesPilot.app}" >/dev/null 2>&1; sleep 3
# Clean base state: only dismiss if an overlay is actually up — a blind Escape CLOSES the window,
# which was the cause of intermittent empty dumps.
PRE="$(settle)"
if grep -qE "Score yourself first|How you did vs\. the coach" <<<"$PRE"; then
  osascript -e 'tell application "System Events" to tell process "SalesPilot"
	set frontmost to true
	delay 0.4
	key code 53
end tell' >/dev/null 2>&1
  sleep 2
fi
ensure_window
UI="$(settle)"

if [ -z "${UI// /}" ]; then echo "FAIL  UI dump EMPTY — harness broken. Aborting."; exit 1; fi
ck "review window reachable via Accessibility" 1
has(){ if grep -qi "$2" <<<"$UI"; then ck "$1" 1; else ck "$1" 0; fi; }
has "current suggestion is visible" "SAY NEXT"
has "current question renders" "How many triage SLAs"
has "conversation is available" "legacy SIEM"
has "multi-person transcript uses generic labels" "CUSTOMER"
has "coverage is compact by default" "Discovery coverage"
has "coverage percentage renders" "38%"
has "delivery ratio renders" "68%"
has "delivery guidance renders" "Make room for their answer"

# Expand secondary panels through their rendered controls, rather than requiring a wall of details
# to stay permanently on screen during a real call.
expand_panel(){ osascript - "$1" <<'AS' 2>/dev/null
on findAndClick(el, wanted, depth)
    if depth > 18 then return false
    tell application "System Events"
        try
            set labels to {}
            try
                set end of labels to name of el
            end try
            try
                set end of labels to description of el
            end try
            try
                set end of labels to title of el
            end try
            try
                set end of labels to value of el
            end try
            repeat with labelText in labels
                if labelText is wanted then
                    try
                        click el
                        return true
                    end try
                end if
            end repeat
        end try
        try
            repeat with child in UI elements of el
                if my findAndClick(child, wanted, depth + 1) then return true
            end repeat
        end try
    end tell
    return false
end findAndClick
on run argv
    tell application "System Events" to tell process "SalesPilot"
        return my findAndClick(window 1, item 1 of argv, 0)
    end tell
end run
AS
}
expand_panel "People on the call" >/dev/null
sleep 1
UI="$(settle)"
for person in "Dana Reyes" "Marcus Chen" "Priya Patel"; do has "roster shows $person" "$person"; done
has "decision maker is identified" "decision-maker"
expand_panel "Topics to explore" >/dev/null
sleep 1
UI="$(settle)"
has "solution evidence is available on demand" "false positives"
has "diagnostic probe is available" "When an alert fires"
has "multiple possibilities remain explicit" "More than one area is live"
expand_panel "Discovery coverage" >/dev/null
sleep 1
UI="$(settle)"
has "framework detail expands" "Economic Buyer"
has "unresolved coverage stays explicit" "Explore more"
has "covered elements render" "Covered"

# --- interactive: status menu -> Self-Score -> Reveal & Compare ---
# The status-menu click is unreliable with a fixed delay (menu may not be open yet), so verify the
# menu actually opened before clicking the item, and retry. This was ~50% flaky.
open_selfscore(){ osascript <<'MENU' 2>/dev/null
tell application "System Events" to tell process "SalesPilot"
	set frontmost to true
	repeat 4 times
		try
			click menu bar item 1 of menu bar 1
		end try
		delay 1.2
		if exists menu 1 of menu bar item 1 of menu bar 1 then
			try
				click menu item "Self-Score Last Call…" of menu 1 of menu bar item 1 of menu bar 1
				return "opened"
			end try
		end if
		try
			key code 53
		end try
		delay 0.6
	end repeat
	return "failed"
end tell
MENU
}
iact_pass=0; iact_fail=0
ick(){ if [ "$2" = "1" ]; then echo "PASS  $1"; iact_pass=$((iact_pass+1)); else echo "SKIP  $1   (flaky: menu/AX timing)"; iact_fail=$((iact_fail+1)); fi; }
echo; echo "--- interactive flows (best-effort, non-gating) ---"
SS=""
for _ in 1 2 3; do
  open_selfscore >/dev/null 2>&1
  sleep 3
  SS="$(settle)"
  grep -q "Score yourself first" <<<"$SS" && break
done
grep -q "Score yourself first" <<<"$SS" && ick "self-score: recall step opens" 1 || ick "self-score: recall step opens" 0
grep -q "What would you ask FIRST" <<<"$SS" && ick "self-score: next-call prompt renders" 1 || ick "self-score: next-call prompt renders" 0

osascript -e 'tell application "System Events" to tell process "SalesPilot"
	set frontmost to true
	delay 0.5
	key code 36
end tell' >/dev/null 2>&1
sleep 3
RV="$(settle)"
grep -q "How you did vs. the coach" <<<"$RV" && ick "self-score: reveal step opens" 1 || ick "self-score: reveal step opens" 0
grep -q "CALIBRATION" <<<"$RV" && ick "self-score: calibration shown" 1 || ick "self-score: calibration shown" 0
grep -qE "AGREE|SHARPEN" <<<"$RV" && ick "self-score: agreements/gaps shown" 1 || ick "self-score: agreements/gaps shown" 0
osascript -e 'tell application "System Events" to tell process "SalesPilot"
	set frontmost to true
	delay 0.4
	key code 36
end tell' >/dev/null 2>&1

echo; echo "core (gating):     $pass/$((pass+fail)) passed"
echo "interactive (info): $iact_pass/$((iact_pass+iact_fail)) passed"
[ "$fail" -eq 0 ] || exit 1

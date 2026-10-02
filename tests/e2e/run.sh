#!/bin/bash
# Faithful two-channel end-to-end call test against the shipping app.
#
#   REP  voice -> a player whose PID is EXCLUDED from the global tap -> BlackHole 2ch (default INPUT)
#                 so it reaches the app's microphone only, exactly like a human talking.
#   CUST voice -> a separate, NOT-excluded player -> the real default OUTPUT, so the app's
#                 system-audio tap hears it, exactly like the far end of a Webex call.
#
# The tap is global across devices, so without the PID exclusion the rep's synthetic voice would
# also land on the customer channel and the test would be measuring its own artifact.
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${TMPDIR:-/tmp}/salespilot-e2e"; mkdir -p "$SCRATCH"
AT="$HERE/bin/audiotool"
CONVO="$HERE/convo"
ROOT="${SALESPILOT_ROOT:-$HOME/Documents/sales-copilot}"
export SALESPILOT_ROOT="$ROOT"
SESS="$ROOT/sessions/latest.json"
APP="${SALESPILOT_APP_PATH:-$HOME/Applications/SalesPilot.app}"
SAVED=$(mktemp -d -t salespilot-e2e-session)
for file in latest.json dictation.log; do
  [ ! -f "$ROOT/sessions/$file" ] || cp "$ROOT/sessions/$file" "$SAVED/$file"
done
TIMELINE="$SCRATCH/timeline.txt"
MIC_DEV="BlackHole 2ch"

ORIG_IN="$($AT getin)"; ORIG_OUT="$($AT getout)"
# Never "restore" to the loopback device a previous run left behind.
[ "$ORIG_IN" = "BlackHole 2ch" ] && ORIG_IN="MacBook Pro Microphone"
cleanup(){
  [ -n "$REP_IN" ] && exec 3>&- 2>/dev/null
  [ -n "$CUST_IN" ] && exec 4>&- 2>/dev/null
  kill $REP_PID $CUST_PID $POLLER $APP_PID 2>/dev/null
  $AT setin "$ORIG_IN" >/dev/null 2>&1; $AT setout "$ORIG_OUT" >/dev/null 2>&1
  for file in latest.json dictation.log; do
    if [ -f "$SAVED/$file" ]; then cp "$SAVED/$file" "$ROOT/sessions/$file"; else rm -f "$ROOT/sessions/$file"; fi
  done
  rm -rf "$SAVED"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
echo ">>> devices: out=$ORIG_OUT in=$ORIG_IN -> mic routed through $MIC_DEV"
$AT setin "$MIC_DEV" || exit 1

# Two long-lived players with stable PIDs.
REP_FIFO=$SCRATCH/rep.fifo; CUST_FIFO=$SCRATCH/cust.fifo
rm -f $REP_FIFO $CUST_FIFO; mkfifo $REP_FIFO $CUST_FIFO
"$AT" serve < $REP_FIFO  > $SCRATCH/rep.out  & REP_PID=$!
"$AT" serve < $CUST_FIFO > $SCRATCH/cust.out & CUST_PID=$!
exec 3> $REP_FIFO
exec 4> $CUST_FIFO
sleep 1
echo ">>> rep player pid=$REP_PID (EXCLUDED from tap)   customer player pid=$CUST_PID (tapped)"


echo ">>> restarting app clean"
pkill -f SalesPilot 2>/dev/null; sleep 2
rm -f "$SESS" "$ROOT/sessions/dictation.log"
# Launched directly, with the exclusion in the environment: nothing is written to the app's stored
# preferences, so the hook cannot outlive this test run.
SALESPILOT_TEST_EXCLUDE_PIDS="$REP_PID" \
  "$APP/Contents/MacOS/SalesPilot" > "$SCRATCH/app.log" 2>&1 &
APP_PID=$!
sleep 7

menu_click(){ osascript 2>/dev/null <<MENU
tell application "System Events" to tell process "SalesPilot"
	set frontmost to true
	repeat 5 times
		try
			click menu bar item 1 of menu bar 1
		end try
		delay 1.2
		if exists menu 1 of menu bar item 1 of menu bar 1 then
			try
				click menu item "$1" of menu 1 of menu bar item 1 of menu bar 1
				return "ok"
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

# A process gets a CoreAudio process object only once it has actually rendered audio. Until then
# the tap's PID exclusion resolves to nothing and silently does not apply. Prime the rep player
# (into the loopback device, so nothing is audible and the call has not started yet) so that by the
# time the tap is created the exclusion can actually bind.
echo "$MIC_DEV|$CONVO/r3.wav|0.02" >&3
sleep 4
echo ">>> rep player audio object: $($HERE/bin/pidchk $REP_PID)"

START_RESULT="$(menu_click 'Start live call')"
echo ">>> starting live transcript: $START_RESULT"
[ "$START_RESULT" = "ok" ] || { echo "FAIL: app could not start live capture; check macOS permissions"; exit 1; }
sleep 2
# If a previous transcript survived, toggleLive() raises a modal; answer it so the call proceeds.
osascript 2>/dev/null <<'DLG'
tell application "System Events" to tell process "SalesPilot"
	repeat with w in windows
		try
			click button "Start New Call" of w
		end try
	end repeat
end tell
DLG
sleep 5

: > "$TIMELINE"
T0=$(python3 -c 'import time; print(time.time())')
( while :; do
    python3 - "$SESS" "$T0" >> "$TIMELINE" 2>/dev/null <<'PY'
import json,sys,time
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit()
el=time.time()-float(sys.argv[2])
ts=d.get("turns") or []
print(f'{el:6.1f}  name={d.get("customerName")!r} role={d.get("customerRole")!r} roster={len(d.get("roster") or [])} turns={len(ts)} you={sum(1 for t in ts if t.get("me"))} cust={sum(1 for t in ts if not t.get("me"))}')
PY
    sleep 0.4
  done ) & POLLER=$!

mark(){ python3 -c "import time; print(f'{time.time()-$T0:6.1f}  >>> $1')" >> "$TIMELINE"; }

echo ">>> playing conversation"
dur(){ python3 -c "import os;print(f'{os.path.getsize(\"$1\")/4/16000:.1f}')"; }
for turn in r1 c1 r2 c2 r3 c3 r4 c4 r5 c5; do
  D=$(dur "$CONVO/$turn.wav")
  case "$turn" in
    r*) mark "PLAY REP  $turn (${D}s)"; echo "    REP  $turn  ${D}s"; echo "$MIC_DEV|$CONVO/$turn.wav" >&3 ;;
    c*) mark "PLAY CUST $turn (${D}s)"; echo "    CUST $turn  ${D}s"; echo "$ORIG_OUT|$CONVO/$turn.wav" >&4 ;;
  esac
  python3 -c "import time; time.sleep($D + 2.2)"      # clip length + a pause so the turn finalizes
  # Capture what the REVIEW WINDOW is showing right after the customer introduces herself. This is
  # the "real time, not after the call" requirement, so it has to be read while the call is live.
  if [ "$turn" = "c1" ]; then
    sleep 2
    osascript 2>/dev/null > "$SCRATCH/ui-midcall.txt" <<'AS'
on reveal(el, wanted, d)
    if d > 18 then return false
    tell application "System Events"
        try
            if name of el is wanted or description of el is wanted then
                click el
                return true
            end if
        end try
        try
            repeat with child in UI elements of el
                if my reveal(child, wanted, d + 1) then return true
            end repeat
        end try
    end tell
    return false
end reveal
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
	repeat with w in windows
		my reveal(w, "People on the call", 0)
		my reveal(w, "Transcript", 0)
	end repeat
	delay 1
	-- Walk EVERY window: during a live call the floating HUD is window 1, and the review window
	-- (the one that carries the roster panel) sits behind it.
	repeat with w in windows
		set res to res & "=== window ===" & linefeed
		try
			repeat with t in (UI elements of w)
				set res to res & (my walk(t, 0))
			end repeat
		end try
	end repeat
	return res
end tell
AS
    echo "    [captured review window mid-call]"
  fi
done

echo ">>> finalizing"; sleep 10
kill $POLLER 2>/dev/null
echo ">>> stopping: $(menu_click 'End live call')"
sleep 12

echo
python3 "$HERE/assert-call.py" "$SCRATCH/ui-midcall.txt" "$SCRATCH/timeline.txt"

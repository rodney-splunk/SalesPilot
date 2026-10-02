import json, os, re, sys

SESS = os.path.join(os.environ.get('SALESPILOT_ROOT', os.path.expanduser('~/Documents/sales-copilot')), 'sessions', 'latest.json')
UI   = sys.argv[1] if len(sys.argv) > 1 else ""
TL   = sys.argv[2] if len(sys.argv) > 2 else ""

NUM = {"one":"1","two":"2","three":"3","four":"4","five":"5","six":"6","seven":"7","eight":"8",
       "nine":"9","ten":"10","eleven":"11","twelve":"12","fourteen":"14","twenty":"20","forty":"40"}
def norm(s):
    s = s.lower()
    for w, d in NUM.items(): s = re.sub(rf"\b{w}\b", d, s)
    return re.sub(r"[^a-z0-9 ]", " ", s)

d = json.load(open(SESS))
turns = d.get("turns") or []
ui = open(UI).read() if UI and os.path.exists(UI) else ""
tl = open(TL).read() if TL and os.path.exists(TL) else ""

P = F = 0
def ck(name, ok, detail=""):
    global P, F
    if ok: P += 1; print(f"  PASS  {name}")
    else:  F += 1; print(f"  FAIL  {name}" + (f"   ({detail})" for _ in [0]).__next__() if detail else f"  FAIL  {name}")

def check(name, ok, detail=""):
    global P, F
    if ok: P += 1; print(f"  PASS  {name}")
    else:  F += 1; print(f"  FAIL  {name}{('   (' + detail + ')') if detail else ''}")

# --- speaker attribution: the rep speaks on odd turns, the customer on even ---
expected = ["REP","CUST"] * 5
check("all 10 turns were captured", len(turns) == 10, f"got {len(turns)}")
mis = []
for i, t in enumerate(turns[:10]):
    got = "REP" if t.get("me") else "CUST"
    if got != expected[i]: mis.append(f"turn {i+1} is {got}, should be {expected[i]}")
check("every turn is attributed to the right speaker", not mis, "; ".join(mis))
timed = all(isinstance(t.get('startedAt'), (int, float)) and isinstance(t.get('endedAt'), (int, float)) and t['endedAt'] >= t['startedAt'] for t in turns)
check("captured turns retain real audio timestamps", bool(turns) and timed)
if turns and timed:
    check("turns appear in capture order", all(a['startedAt'] <= b['startedAt'] for a, b in zip(turns, turns[1:])))
check("delivery metrics use audio duration", (d.get('delivery') or {}).get('measurement') == 'audio duration')

# --- no duplicated turn across channels ---
seen = {}
dupes = [t["text"][:40] for t in turns if norm(t["text"]) in seen or seen.setdefault(norm(t["text"]), 1) and False]
check("no utterance appears twice (no cross-channel overlap)", not dupes, "; ".join(dupes))

# --- identity ---
check("customer name extracted", (d.get("customerName") or "").lower().startswith("jessi"), repr(d.get("customerName")))
role = (d.get("customerRole") or "")
check("customer role extracted", "security engineering" in role.lower(), repr(role))
check("role is not a truncated fragment", not re.search(r"\b(?:her|th|engineerin|tea)\b", role.lower()), repr(role))
roster = d.get("roster") or []
check("roster has exactly the one customer", len(roster) == 1 and roster[0]["name"].lower().startswith("jessi"), json.dumps(roster))
check("the rep is NOT on the customer roster", not any("rodney" in (p.get("name","")).lower() for p in roster))

# --- content fidelity: what she actually said has to survive ---
allcust = norm(" ".join(t["text"] for t in turns if not t.get("me")))
allrep  = norm(" ".join(t["text"] for t in turns if t.get("me")))
for phrase in ["14 different security tools", "copying data between consoles", "8 analysts",
               "chief information security officer", "cannot produce them",
               "mean time to detect", "6 hours", "1 hour", "fail our audit again in march", "at risk"]:
    check(f"customer content survived: {phrase!r}", norm(phrase) in allcust)
for phrase in ["end of the year", "who else feels that"]:
    check(f"rep content survived: {phrase!r}", norm(phrase) in allrep)
check("no whisper hallucination in the transcript",
      not re.search(r"see you in the next video|thanks for watching|subscribe", allcust + allrep))

# --- real time: the review window showed name AND role WHILE the call was live ---
if ui:
    check("review window showed the people panel mid-call", "People on the call" in ui)
    check("review window showed the name mid-call", re.search(r"Jessi[e]? Yang", ui) is not None)
    check("review window showed the role underneath mid-call", re.search(r"Security Engineering", ui) is not None)
    check("speaker label mid-call was the name, not 'Customer'", "JESSIE YANG" in ui.upper())

# --- how fast did identity appear? ---
if tl:
    intro_at = None; ident_at = None
    for line in tl.splitlines():
        m = re.match(r"\s*([\d.]+)\s+>>> PLAY CUST c1", line)
        if m and intro_at is None: intro_at = float(m.group(1))
        m2 = re.match(r"\s*([\d.]+)\s+name='", line)
        if m2 and ident_at is None: ident_at = float(m2.group(1))
    if intro_at is not None and ident_at is not None:
        delta = ident_at - intro_at
        check(f"identity appeared within 15s of the intro starting ({delta:.1f}s)", delta <= 15, f"{delta:.1f}s")
        rost = None
        for line in tl.splitlines():
            m3 = re.match(r"\s*([\d.]+)\s+name='.*roster=([1-9])", line)
            if m3: rost = float(m3.group(1)); break
        if rost is not None:
            check(f"roster panel populated within 15s of the intro ({rost - intro_at:.1f}s)", rost - intro_at <= 15)

print(f"\nend-to-end call: {P}/{P+F} passed")
sys.exit(1 if F else 0)

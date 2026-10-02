// Engine regression tests — run: `node test.mjs` from engine/.
// Integration-tests the REAL serve.mjs code path (spawns it, feeds turns, checks latest.json).
// Uses short (<4-word) turns so name cases skip the coaching LLM call → fast and deterministic.
import { spawn } from "child_process";
import { readFileSync } from "fs";
import { tmpdir } from "os";

import os from "node:os";
import { rmSync } from "node:fs";
// Hermetic: never let a prep the user has active change what these tests see.
process.env.PREP_FILE = process.env.PREP_FILE || `${os.tmpdir()}/salespilot-test-prep.txt`;
rmSync(process.env.PREP_FILE, { force: true });   // start every run with no prep

const HERE = new URL(".", import.meta.url).pathname;
// Each spawned engine gets its own session file. Sharing sessions/latest.json meant a slow process
// from an earlier case could still be writing while the next one read, so tests saw each other's data.
let caseNo = 0;
const LATEST = () => `${tmpdir()}/salespilot-test-${process.pid}-${caseNo}.json`;

function run(turns, args = []) {
  return new Promise((resolve) => {
    const p = spawn("node", ["serve.mjs", "--framework", "meddic", ...args], { cwd: HERE, env: { ...process.env, SESSION_FILE: (caseNo++, LATEST()) } });
    p.stderr.on("data", () => {}); // drain
    setTimeout(async () => {
      for (const t of turns) { p.stdin.write(JSON.stringify(t) + "\n"); await new Promise((r) => setTimeout(r, 250)); }
      setTimeout(() => {
        let field = null;
        try { field = JSON.parse(readFileSync(LATEST(), "utf8")); } catch {}
        p.stdin.end();
        resolve(field);
      }, 1200);
    }, 400);
  });
}

const nameCases = [
  { label: 'intro "I\'m Dana"                     -> Dana',        turns: [{ speaker: "customer", text: "I'm Dana" }], want: "Dana" },
  { label: 'intro "I\'m Marcus Chen"              -> Marcus Chen', turns: [{ speaker: "customer", text: "I'm Marcus Chen" }], want: "Marcus Chen" },
  { label: 'false-positive "I\'m thinking"        -> null',        turns: [{ speaker: "customer", text: "I'm thinking" }], want: null },
  { label: 'false-positive "I\'m ready"           -> null',        turns: [{ speaker: "customer", text: "I'm ready" }], want: null },
  { label: 'explicit "This is Dana"               -> Dana',        turns: [{ speaker: "customer", text: "This is Dana" }], want: "Dana" },
  { label: 'correction: "I\'m Bob" then "This is Dana" -> Dana',   turns: [{ speaker: "customer", text: "I'm Bob" }, { speaker: "customer", text: "This is Dana" }], want: "Dana" },
  { label: 'rep greets "Hi Dana"                  -> Dana',        turns: [{ speaker: "you", text: "Hi Dana" }], want: "Dana" },
  // People introduce themselves as "<Name>, <Title>" constantly, with no "I'm" to key on. Requiring
  // a role title after the comma is what keeps "Thanks Rodney, that helps" from being read as a name.
  { label: 'badge "Alec Williams, Director of Data Engineering"',  turns: [{ speaker: "customer", text: "Sure. Alec Williams, Director of Data Engineering." }], want: "Alec Williams" },
  { label: 'badge single name "Dana, VP of Engineering"',          turns: [{ speaker: "customer", text: "Dana, VP of Engineering." }], want: "Dana" },
  { label: 'false-positive "Thanks Rodney, that makes sense"',     turns: [{ speaker: "customer", text: "Thanks Rodney, that makes sense to me." }], want: null },
  { label: 'false-positive "Right, the bigger problem is cost"',   turns: [{ speaker: "customer", text: "Right, the bigger problem is cost." }], want: null },
];

let pass = 0, fail = 0;
console.log("— name extraction —");
for (const c of nameCases) {
  const s = await run(c.turns);
  const got = s?.customerName ?? null;
  const ok = got === c.want;
  console.log(`${ok ? "PASS" : "FAIL"}  ${c.label}   (got ${JSON.stringify(got)})`);
  ok ? pass++ : fail++;
}

// --- cross-channel echo de-duplication ---------------------------------------------------------
// The customer's audio bleeds out the speakers into the mic, so the same utterance lands on BOTH
// channels (seen in real call data). Verify it's removed either ordering, without false positives.
function runTurns(turns) {
  return new Promise((resolve) => {
    const p = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE, env: { ...process.env, SESSION_FILE: (caseNo++, LATEST()) } });
    p.stderr.on("data", () => {});
    (async () => {
      for (const t of turns) { p.stdin.write(JSON.stringify(t) + "\n"); await new Promise((r) => setTimeout(r, 2500)); }
      // Turns are coached on a background queue, so the engine may still be writing. Poll until the
      // session stops changing rather than guessing a fixed delay.
      let prev = -1, stable = 0;
      const poll = setInterval(() => {
        let s = {}; try { s = JSON.parse(readFileSync(LATEST(), "utf8")); } catch {}
        const n = (s.turns || []).length;
        stable = n === prev ? stable + 1 : 0;
        prev = n;
        if (stable >= 3 || stable === -1) {
          clearInterval(poll); p.stdin.end(); resolve(s.turns || []);
        }
      }, 700);
      setTimeout(() => { clearInterval(poll); let s = {}; try { s = JSON.parse(readFileSync(LATEST(), "utf8")); } catch {}; p.stdin.end(); resolve(s.turns || []); }, 20000);
    })();
  });
}
const dC = "Yeah, I'll start. I'm Dylan. I'm a level one security analyst, the one in the SOC who was actually using the product.";
const dY = "Yeah, I'll start. I'm Dylan. I'm a level one secured analyst. I'm the one in the SOC who's actually using it.";

console.log("\n— cross-channel echo de-dup —");
{
  const t = await runTurns([{ speaker: "customer", text: dC }, { speaker: "you", text: dY }]);
  const ok = t.length === 1 && t[0].me === false;
  console.log(`${ok ? "PASS" : "FAIL"}  mic echo AFTER customer is dropped   (kept ${t.length})`);
  ok ? pass++ : fail++;
}
{
  const t = await runTurns([{ speaker: "you", text: dY }, { speaker: "customer", text: dC }]);
  const ok = t.length === 1 && t[0].me === false;
  console.log(`${ok ? "PASS" : "FAIL"}  mic echo BEFORE customer is retracted   (kept ${t.length})`);
  ok ? pass++ : fail++;
}
{
  const t = await runTurns([{ speaker: "you", text: "So walk me through how your team handles security incidents today." },
                            { speaker: "customer", text: "Our analysts miss triage SLAs constantly, hours when it should be minutes." }]);
  const ok = t.length === 2;
  console.log(`${ok ? "PASS" : "FAIL"}  different turns on both channels are KEPT   (kept ${t.length})`);
  ok ? pass++ : fail++;
}

{
  // Verbatim from a real call: the customer's speech reached the mic GARBLED and SPLIT into two
  // fragments (containment 0.67 / 0.69), which slipped past the original 0.70 threshold.
  const t = await runTurns([
    { speaker: "you", text: "Hey, hey, so it's Rodney White here. I'm a solutions engineer over at Splunk and today I kind of just wanted to go through what we have to offer you." },
    { speaker: "you", text: "I have service issues and when they do have the get results , they will be able to get" },
    { speaker: "you", text: "by my provider and most of my friends have switched to my service provider so you see um you know" },
    { speaker: "customer", text: "I have service issues and when they do happen, they get resolved quickly by my provider. Most of my friends have switched to my service provider." },
  ]);
  const you = t.filter((x) => x.me), cust = t.filter((x) => !x.me);
  const ok = you.length === 1 && cust.length === 1 && you[0].text.includes("Rodney White");
  console.log(`${ok ? "PASS" : "FAIL"}  real call: SPLIT bleed fragments removed, rep's own turn kept   (you=${you.length} cust=${cust.length})`);
  ok ? pass++ : fail++;
}

// --- delivery metrics --------------------------------------------------------------------------
// Discovery is scored on HOW you talk. These four numbers are what the rep is graded against, so a
// wrong one is worse than none at all: it would coach the opposite of the right behaviour.
function runDelivery(turns, env = {}) {
  return new Promise((resolve) => {
    const p = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE, env: { ...process.env, ...env, SESSION_FILE: (caseNo++, LATEST()) } });
    p.stderr.on("data", () => {});
    (async () => {
      for (const t of turns) { p.stdin.write(JSON.stringify(t) + "\n"); await new Promise((r) => setTimeout(r, 2500)); }
      // Poll rather than guess. A fixed wait races anything that slows startup (a prep file triggers
      // a seed coach call, for one), and produced a test that passed and failed on the same code.
      const started = Date.now(), read = () => { try { return JSON.parse(readFileSync(LATEST(), "utf8")); } catch { return null; } };
      let s = null;
      while (Date.now() - started < 14000) {
        s = read();
        if (s && (s.turns || []).length >= turns.length) break;
        await new Promise((r) => setTimeout(r, 250));
      }
      await new Promise((r) => setTimeout(r, 1200));   // let the coach land after the turn is on file
      s = read() || {};
      p.stdin.end();
      resolve({ ...(s.delivery || {}), phase: s.phase, nextq: s.nextq || [], customerRole: s.customerRole, customerName: s.customerName });
    })();
  });
}
const FRAMED = "Andrew, thanks for making time. I understand you're running into PII compliance issues in Splunk. Before I show you anything, can I ask you some questions?";
const UNFRAMED = "Hey Andrew, great to meet you, how has your week been going so far, anything exciting happening on your end lately?";

// --- name reconciliation against call prep ----------------------------------------------------
// A real call transcribed "Nilanjana Nair" as "Nalanda Nair". Priming whisper with the expected
// names is the first defence; this is the second, for when the audio defeats it anyway.
console.log("\n— name reconciliation —");
{
  const { writeFileSync, unlinkSync, existsSync } = await import("fs");
  const PREP = process.env.PREP_FILE;   // the pinned test prep, never the user's own
  const had = existsSync(PREP);
  writeFileSync(PREP, "Attendees: Nilanjana Nair, Rodney White\nTopic: PII compliance review\n");
  try {
    const cases = [
      ["distant first name is not overwritten solely by surname", "My name is Nalanda Nair.", "Nalanda Nair"],
      ["already correct, left alone",            "My name is Nilanjana Nair.", "Nilanjana Nair"],
      ["different person is NOT snapped",        "My name is Sarah Chen.", "Sarah Chen"],
    ];
    for (const [label, text, want] of cases) {
      const d = await runDelivery([{ speaker: "customer", text }]);
      const got = d.customerName ?? null;
      const ok = got === want;
      console.log(`${ok ? "PASS" : "FAIL"}  ${label}   (got ${JSON.stringify(got)})`);
      ok ? pass++ : fail++;
    }
  } finally { if (!had) unlinkSync(PREP); }
}

// --- question detection ------------------------------------------------------------------------
// This gates the whole answer-from-docs path: a missed question means the customer asks about SOC 2
// and nothing appears. Measured against realistic phrasings, the original caught 1 of 10, because
// speech-to-text drops the question mark and customers rarely open with a wh-word.
console.log("\n— question detection —");
{
  const { referenceQuestion: isQuestion } = await import("./answer-policy.mjs");
  const yes = ["Are you SOC 2 compliant", "So you guys are SOC 2 compliant right",
    "You support risk based alerting correct", "I am wondering about your data retention limits",
    "Talk to me about pricing", "Any chance this runs on prem", "Curious how long you keep the logs",
    "Give me an idea of what onboarding looks like", "Does that work with Kubernetes"];
  const no = ["We are seeing a lot of alert noise.", "Sure, that makes sense.",
    "Our analysts miss triage SLAs constantly.", "I will do that after the call.",
    "That's right.", "Yeah, correct.", "Exactly, that is the problem.", "We did that last year."];
  const missed = yes.filter((q) => !isQuestion(q));
  const falsePos = no.filter((q) => isQuestion(q));
  let ok = missed.length === 0;
  console.log(`${ok ? "PASS" : "FAIL"}  real customer questions are detected without a question mark   (missed: ${missed.length ? missed.join(" | ") : "none"})`);
  ok ? pass++ : fail++;
  ok = falsePos.length === 0;
  console.log(`${ok ? "PASS" : "FAIL"}  statements and affirmations do NOT trigger an answer   (fired: ${falsePos.length ? falsePos.join(" | ") : "none"})`);
  ok ? pass++ : fail++;
}

// --- reported speech is not an introduction ----------------------------------------------------
// From a real call: a colleague DEMONSTRATED an intro ("So you basically say, 'my name's Rami, I'm
// an SED at Splunk'") and the customer was recorded as Rami, SED at Splunk. Pattern matching cannot
// tell a quotation from an introduction, so the guard has to look for the framing around it.
console.log("\n— reported speech —");
{
  const cases = [
    ['quoted example intro is ignored', `For the ISM is, sometimes you will get that input. So you basically say, "Hey guys, so my name is Rami, I am an SED at Splunk."`, null],
    ['hypothetical intro is ignored',   `You would say something like my name is Dana and I run security.`, null],
    ['a real intro still lands',        `Sure. Alec Williams, Director of Data Engineering.`, 'Alec Williams'],
  ];
  for (const [label, text, want] of cases) {
    const d = await runDelivery([{ speaker: 'customer', text }]);
    const got = d.customerName ?? null;
    const ok = got === want;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}   (got ${JSON.stringify(got)})`);
    ok ? pass++ : fail++;
  }
}

// --- junk names from ordinary speech ------------------------------------------------------------
// A real 250-turn call recorded customerName "Oh" with role "Cool. Okay", from the sentence
// "...the same exact thing. Oh, cool. Okay." ROLE_TITLES contains "coo" (chief operating officer)
// and the role pattern had no trailing word boundary, so "cool" matched "coo" and the whole thing
// looked like an introduction.
console.log("\n— junk name rejection —");
{
  const junk = [
    ["'Oh, cool. Okay.' is not an introduction", "Hi, Eric and I were actually pretty much looking at the same exact thing. Oh, cool. Okay."],
    ["'cooler heads' does not match 'coo'",      "Right, cooler heads prevail here and nobody panics."],
    ["a trailing vocative is not an intro",      "Thank you, William."],
    ["an aside is not an intro",                 "And lastly, we shall be asking with our partners."],
  ];
  for (const [label, text] of junk) {
    const d = await runDelivery([{ speaker: "customer", text }]);
    const got = d.customerName ?? null;
    const ok = got === null;
    console.log(`${ok ? "PASS" : "FAIL"}  ${label}   (got ${JSON.stringify(got)})`);
    ok ? pass++ : fail++;
  }
  // and the real ones must still land
  const d = await runDelivery([{ speaker: "customer", text: "Sure. Alec Williams, Director of Data Engineering." }]);
  const ok = d.customerName === "Alec Williams";
  console.log(`${ok ? "PASS" : "FAIL"}  a real introduction still lands   (${JSON.stringify(d.customerName)})`);
  ok ? pass++ : fail++;
}

// --- role extraction across real phrasings -----------------------------------------------------
// A real call said "I am a global director of security operations" and produced NO role, because the
// prefix list only allowed senior/lead/head of.
console.log("\n— role extraction —");
{
  const cases = [
    ["global director of security operations", "I am a global director of security operations at Apple.", "Global Director of Security Operations"],
    ["plain analyst",                          "I'm a security analyst on the SOC team.",                  "Security Analyst"],
    ["chief information security officer",     "I am the chief information security officer here.",        "Chief Information Security Officer"],
    ["senior manager",                         "I'm a senior manager of platform engineering.",            "Senior Manager of Platform Engineering"],
  ];
  for (const [label, text, want] of cases) {
    const d = await runDelivery([{ speaker: "customer", text }]);
    const got = d.customerRole ?? null;
    const ok = got === want;
    console.log(`${ok ? "PASS" : "FAIL"}  ${label}   (got ${JSON.stringify(got)})`);
    ok ? pass++ : fail++;
  }
  // The prefix is deliberately loose (domain words vary too much to list), so the guard is that a
  // sentence with no title in it must still yield nothing.
  for (const [label, text] of [
    ["no role in an ordinary sentence", "I am really not sure how we would measure that today."],
    ["not a role: 'I am thinking'",     "I am thinking we need to fix the ingest pipeline first."],
  ]) {
    const d = await runDelivery([{ speaker: "customer", text }]);
    const ok = (d.customerRole ?? null) === null;
    console.log(`${ok ? "PASS" : "FAIL"}  ${label}   (got ${JSON.stringify(d.customerRole ?? null)})`);
    ok ? pass++ : fail++;
  }
}

// --- role title casing ------------------------------------------------------------------------
// Roles sit next to a person's name in the UI, so they have to read as titles. Acronyms must survive
// (IT, not It) and the joining words inside a title stay lowercase.
console.log("\n— role titles —");
{
  const d = await runDelivery([{ speaker: "customer", text: "Sure. Alec Williams, director of data engineering." }]);
  const ok = d.customerRole === "Director of Data Engineering";
  console.log(`${ok ? "PASS" : "FAIL"}  spoken role is title-cased, joining words stay lowercase   (${JSON.stringify(d.customerRole)})`);
  ok ? pass++ : fail++;
}

console.log("\n— delivery metrics —");
{
  const d = await runDelivery([{ speaker: "you", text: FRAMED }]);
  const ok = d.openingFramed === true;
  console.log(`${ok ? "PASS" : "FAIL"}  framed opener (names problem + asks permission) is recognised   (got ${d.openingFramed})`);
  ok ? pass++ : fail++;
}
{
  const d = await runDelivery([{ speaker: "you", text: UNFRAMED }]);
  const ok = d.openingFramed === false;
  console.log(`${ok ? "PASS" : "FAIL"}  small-talk opener is flagged as unframed   (got ${d.openingFramed})`);
  ok ? pass++ : fail++;
}
{
  const d = await runDelivery([
    { speaker: "you", text: "So the way we usually think about this is that data governance is really a pipeline problem and most teams discover it far too late in the process." },
    { speaker: "customer", text: "Right, that matches our experience." },
  ]);
  const ok = d.talkRatio >= 75 && d.talkRatio <= 92;
  console.log(`${ok ? "PASS" : "FAIL"}  rep-dominated call reports a high talk ratio   (got ${d.talkRatio}%)`);
  ok ? pass++ : fail++;
}
{
  const d = await runDelivery([
    { speaker: "you", text: "So um, I wanted to uh ask you, you know, about the compliance side of things over there." },
  ]);
  const ok = d.fillerPerMin >= 6;
  console.log(`${ok ? "PASS" : "FAIL"}  filler words are counted (um / uh / you know)   (got ${d.fillerPerMin}/min)`);
  ok ? pass++ : fail++;
}
{
  // Regression: the customer's audio bleeding into the mic used to be banked as the REP's words
  // before it was retracted, inflating the one number the rep is coached on.
  const d = await runDelivery([
    { speaker: "you", text: dY },
    { speaker: "customer", text: dC },
    { speaker: "customer", text: "We have about forty engineers touching these pipelines every single week across three separate business units." },
  ]);
  const ok = d.talkRatio === 0;
  console.log(`${ok ? "PASS" : "FAIL"}  retracted mic echo does NOT inflate the talk ratio   (got ${d.talkRatio}%)`);
  ok ? pass++ : fail++;
}

// --- call phase: frame it, work the gaps, close for the next step -------------------------------
console.log("\n— call phase + closing cue —");
{
  // Without call prep we do not know what this call is about, so the frame cue must be BLANK. A
  // generic "I know you've got challenges you're working through" is filler the rep would never
  // read aloud, and it was the first thing on screen at the start of every call.
  const d = await runDelivery([{ speaker: "customer", text: "Sure, happy to talk through what we're seeing." }]);
  const ok = d.phase === "open" && !d.nextq.some((q) => q.tag === "open the call");
  console.log(`${ok ? "PASS" : "FAIL"}  no prep -> OPEN phase but NO canned frame cue   (phase ${d.phase}, cues ${d.nextq.length})`);
  ok ? pass++ : fail++;
}
{
  // With prep, the opener comes back and names THEIR problem, which is the point of framing.
  const { writeFileSync, unlinkSync, existsSync } = await import("fs");
  const PREP = process.env.PREP_FILE;   // the pinned test prep, never the user's own
  const had = existsSync(PREP);
  writeFileSync(PREP, "PII landing in indexes it should not, and a January audit");
  try {
    const d = await runDelivery([{ speaker: "customer", text: "Sure, happy to talk through what we're seeing." }]);
    const cue = d.nextq.find((q) => q.tag === "open the call");
    const ok = !!cue && /PII landing in indexes/i.test(cue.q);
    console.log(`${ok ? "PASS" : "FAIL"}  with prep -> frame cue names their actual problem   (${cue ? "cued" : "no cue"})`);
    ok ? pass++ : fail++;
  } finally { if (!had) try { unlinkSync(PREP); } catch {} }
}
{
  const d = await runDelivery([{ speaker: "you", text: FRAMED }]);
  const ok = d.phase === "discover" && !d.nextq.some((q) => q.tag === "open the call");
  console.log(`${ok ? "PASS" : "FAIL"}  once framed it advances to DISCOVER and drops the frame cue   (phase ${d.phase})`);
  ok ? pass++ : fail++;
}
{
  const d = await runDelivery([{ speaker: "you", text: FRAMED }], { CLOSE_AFTER_MS: "0" });
  const cue = d.nextq.find((q) => q.tag === "close the call");
  const ok = d.phase === "close" && !!cue && /play back|thirty minutes/i.test(cue.q);
  console.log(`${ok ? "PASS" : "FAIL"}  out of time -> CLOSE phase cues recap + outcome + the ask   (phase ${d.phase})`);
  ok ? pass++ : fail++;
}

// --- mid-call framework switch -----------------------------------------------------------------
// Switching methodology must repaint the rail immediately. It used to await an LLM re-coach before
// writing anything, so the new framework appeared to take ~20s (queue + call) to show up.
function runSwitch(readAfterMs) {
  return new Promise((resolve) => {
    const p = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE, env: { ...process.env, SESSION_FILE: (caseNo++, LATEST()) } });
    p.stderr.on("data", () => {});
    (async () => {
      p.stdin.write(JSON.stringify({ speaker: "customer", text: "We run about forty pipelines across three business units and it's getting hard to govern." }) + "\n");
      await new Promise((r) => setTimeout(r, 900));
      const t0 = Date.now();
      p.stdin.write(JSON.stringify({ cmd: "framework", value: "spin" }) + "\n");
      setTimeout(() => {
        let s = {}; try { s = JSON.parse(readFileSync(LATEST(), "utf8")); } catch {}
        p.stdin.end();
        resolve({ ...s, elapsed: Date.now() - t0 });
      }, readAfterMs);
    })();
  });
}

console.log("\n— mid-call framework switch —");
{
  const s = await runSwitch(600);
  const names = (s.coverage || []).map((c) => c.name);
  const ok = s.framework === "SPIN" && names.includes("Implication") && !names.includes("Paper Process");
  console.log(`${ok ? "PASS" : "FAIL"}  switch repaints within ${s.elapsed}ms, before any LLM re-coach   (${s.framework}: ${names.join(", ")})`);
  ok ? pass++ : fail++;
}

// --- speakerphone detection --------------------------------------------------------------------
// A real call went bad this way: output to desk speakers, input the laptop mic, so BOTH channels
// transcribed BOTH people near-verbatim. De-dup fired 34 times but its "customer copy wins" rule
// then relabelled the rep's own speech as the customer, reporting a 4% talk ratio.
console.log("\n— speakerphone detection —");
{
  const both = [
    "And are you trying to, are you building these alerts by hand or are you using the ones provided by Microsoft?",
    "But it's not connected. We're having trouble connecting some of our more custom data sources to it.",
    "Are you utilizing any automation as part of that workflow?",
    "Just Microsoft endpoint. That's all the alerting we currently have.",
  ];
  const turns = [];
  both.forEach((t, i) => {                      // alternate which channel reports first
    turns.push({ speaker: i % 2 ? "you" : "customer", text: t });
    turns.push({ speaker: i % 2 ? "customer" : "you", text: t });
  });
  const p2 = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE, env: { ...process.env, SESSION_FILE: (caseNo++, LATEST()) } });
  p2.stderr.on("data", () => {});
  for (const t of turns) { p2.stdin.write(JSON.stringify(t) + "\n"); await new Promise((r) => setTimeout(r, 700)); }
  await new Promise((r) => setTimeout(r, 14000));
  let s2 = {}; try { s2 = JSON.parse(readFileSync(LATEST(), "utf8")); } catch {}
  p2.stdin.end();
  const ok = /speakerphone/i.test(s2.audioWarning || "");
  console.log(`${ok ? "PASS" : "FAIL"}  bidirectional bleed is called out as speakerphone   (${s2.audioWarning ? "warned" : "no warning"})`);
  ok ? pass++ : fail++;
}
{
  // The frame is a moment, not a state: a missed opener used to pin the call in OPEN forever, so the
  // frame cue held a Say-Next slot all call and CLOSE could never fire.
  const filler = Array.from({ length: 6 }, (_, i) => ({ speaker: "customer", text: `That is right, and point number ${i} matters to us a great deal here.` }));
  const d = await runDelivery([{ speaker: "you", text: UNFRAMED }, ...filler], { CLOSE_AFTER_MS: "0" });
  const ok = d.openingFramed === false && d.phase !== "open";
  console.log(`${ok ? "PASS" : "FAIL"}  a missed opener does NOT strand the call in the OPEN phase   (phase ${d.phase})`);
  ok ? pass++ : fail++;
}

// --- speaker labelling -------------------------------------------------------------------------
// The name usually lands a few turns in. Turns spoken BEFORE it was known must pick it up too,
// otherwise the top of every transcript says "Customer" for the whole call.
console.log("\n— speaker labels —");
{
  const f2 = `${HERE}/../sessions/latest.json`;
  const p3 = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE });
  p3.stderr.on("data", () => {});
  const seq = [
    { speaker: "customer", text: "Yeah, we ingest about four terabytes a day and it is getting expensive." },
    { speaker: "customer", text: "Sorry, I should introduce myself. Alec Williams, Director of Data Engineering." },
  ];
  for (const t of seq) { p3.stdin.write(JSON.stringify(t) + "\n"); await new Promise((r) => setTimeout(r, 1800)); }
  await new Promise((r) => setTimeout(r, 9000));
  let s3 = {}; try { s3 = JSON.parse(readFileSync(f2, "utf8")); } catch {}
  p3.stdin.end();
  const cust = (s3.turns || []).filter((t) => !t.me);
  const ok = cust.length >= 2 && cust[0].who === "Call audio" && cust[1].who === "Alec Williams";
  console.log(`${ok ? "PASS" : "FAIL"}  speech without voice evidence does not inherit a later introduction   (${cust.map((t) => t.who).join(" | ")})`);
  ok ? pass++ : fail++;
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);

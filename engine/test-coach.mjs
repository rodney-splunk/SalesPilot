// Coaching / identity / correction regression tests — run: `node test-coach.mjs` from engine/.
// Unit-tests the exported core.mjs functions directly (fast; no serve.mjs spawn). Assertions are
// STRUCTURAL/behavioral, never exact strings, since model wording varies run to run.
import { fastTier, extractIdentityAI, correctTranscript, circuitAvailable } from "./core.mjs";
import { PACKS } from "./packs.mjs";

import os from "node:os";
import { rmSync } from "node:fs";
// Hermetic: never let a prep the user has active change what these tests see.
process.env.PREP_FILE = process.env.PREP_FILE || `${os.tmpdir()}/salespilot-test-prep.txt`;
rmSync(process.env.PREP_FILE, { force: true });   // start every run with no prep

let pass = 0, fail = 0;
function check(label, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? `   (${detail})` : ""}`);
  ok ? pass++ : fail++;
}

const pack = PACKS.meddic;
const RICH = `cust: our security monitoring is a mess, legacy SIEM drowning my team
cust: we failed our SOC 2 audit on retention, the board is all over us
cust: analysts miss triage SLAs, hours when it should be minutes
cust: I own the security budget and need improvement by end of Q1
cust: we are also evaluating one other vendor`;

console.log(`— coaching engine —  (CIRCUIT ${circuitAvailable() ? "configured" : "NOT configured → local fallback"})`);

// 1. Coverage must be assessed for EVERY element (the bug: schema made it optional → always empty).
{
  const o = JSON.parse(await fastTier(pack, RICH, ""));
  const ids = Object.keys(o.coverage || {});
  const missing = pack.elements.map((e) => e.id).filter((id) => !ids.includes(id));
  check("coverage returned for every element", missing.length === 0, `missing: ${missing.join(",") || "none"}`);
  const valid = ids.every((k) => ["done", "partial", "open"].includes(o.coverage[k]));
  check("coverage values are done/partial/open", valid);
}

// 2. Goal steering, but only when the LATEST turn supports it. The anchor is validated against the
// customer's most recent turn, so a goal can no longer be welded onto an unrelated statement — that
// is what produced ten consecutive "who owns the budget?" questions on a real call.
{
  // Latest turn is about cost, so a Metrics goal has a natural way in.
  const METRICS_LAST = RICH + `\ncust: triage takes us about six hours per incident and that is costing real money`;
  const guidance = `The goal you have made least progress on is "Metrics" (id "metrics"). Ask about it ONLY if the customer's last turn gives you a natural way in.`;
  const o = JSON.parse(await fastTier(pack, METRICS_LAST, guidance));
  const q = (o.next_questions || [])[0];
  check("goal is honored when the latest turn supports it", q?.targets === "metrics", `got targets=${q?.targets}`);
  check("question text present", !!q?.text && q.text.includes("?"));
}

{
  // The inverse, and the bug this whole change exists for: the latest turn is contentless, so the
  // coach must stay silent rather than mine an earlier turn for something to ask about.
  const NULL_LAST = RICH + `\ncust: right, yeah exactly`;
  const guidance = `The goal you have made least progress on is "Economic Buyer" (id "economic_buyer"). Ask about it ONLY if the customer's last turn gives you a natural way in.`;
  const o = JSON.parse(await fastTier(pack, NULL_LAST, guidance));
  const n = (o.next_questions || []).length;
  check("stays silent when the latest turn has nothing to ask about", n === 0, `got ${n} question(s)`);
}

// 3. Anti-repetition: a question already asked should not come back verbatim.
{
  const asked = "What specific challenges are you facing with the legacy SIEM?";
  const guidance = `Already asked (never repeat or reword): "${asked}".\nChoose a DIFFERENT still-open element.`;
  const o = JSON.parse(await fastTier(pack, RICH, guidance));
  const q = (o.next_questions || [])[0];
  check("does not repeat an already-asked question verbatim",
        (q?.text || "").trim().toLowerCase() !== asked.toLowerCase(), `got: ${q?.text}`);
}

// 4/5. Roster: multi-person extraction, and no hallucination when nobody introduces themselves.
{
  const many = await extractIdentityAI(
    "hi im dana reyes i run security operations. and im marcus chen i head up IT infrastructure. " +
    "hi everyone im priya patel i handle procurement and i sign off on the budget");
  const people = many.people || [];
  check("roster captures multiple people", people.length >= 2, `got ${people.length}`);
  check("roster entries have names", people.every((p) => p.name && p.name.length > 1));
  check("roster flags a decision maker", people.some((p) => p.decision_maker === true));

  const none = await extractIdentityAI("our legacy system is a real mess and we keep missing targets");
  check("no names invented when nobody introduces themselves",
        (none.people || []).length === 0, `got ${JSON.stringify(none.people)}`);
}

// 6/7. Transcript correction: fixes an obvious mishear, leaves clean text substantially intact.
{
  const bad = "we are moving our entire rebuilding operation to a new point of sale system next quarter";
  const fixed = await correctTranscript(bad);
  check("fixes an obvious ASR mishear", /retail/i.test(fixed), `got: ${fixed}`);

  const clean = "our analysts miss triage SLAs by several hours every single week right now";
  const out = await correctTranscript(clean);
  const ratio = out.length / clean.length;
  check("leaves clean text substantially intact", ratio > 0.7 && ratio < 1.4, `len ratio ${ratio.toFixed(2)}`);

  const short = await correctTranscript("yeah ok");
  check("skips too-short turns (no wasted call)", short === "yeah ok");
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);

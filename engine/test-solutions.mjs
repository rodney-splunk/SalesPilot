// Solution-signal tests — run: `node test-solutions.mjs` from engine/.
// The behaviour under test is mostly RESTRAINT: this has to stay quiet until the customer has
// actually told you something, and has to say "still open" rather than pick when two areas are live.
import { solutionSignals } from "./solutions.mjs";

import os from "node:os";
import { rmSync } from "node:fs";
// Hermetic: never let a prep the user has active change what these tests see.
process.env.PREP_FILE = process.env.PREP_FILE || `${os.tmpdir()}/salespilot-test-prep.txt`;
rmSync(process.env.PREP_FILE, { force: true });   // start every run with no prep
let pass = 0, fail = 0;
const ok = (label, cond, detail = "") => {
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}${detail ? `   (${detail})` : ""}`);
  cond ? pass++ : fail++;
};

console.log("— restraint —");
ok("empty transcript surfaces nothing", solutionSignals("").status === "open");
ok("one passing mention of security is NOT a signal",
   solutionSignals("We care about security like everyone does.").status === "open",
   solutionSignals("We care about security like everyone does.").status);
ok("saying SOC nine times is still one fact",
   solutionSignals("SOC. SOC. SOC. SOC. SOC. SOC. SOC. SOC. SOC.").status === "open",
   `score capped`);

console.log("\n— detection —");
{
  const r = solutionSignals(`Our SOC is drowning. The tier one analysts spend the day on false positives
    and we have no real threat detection beyond what came out of the box. Every correlation search we
    wrote fires constantly and nobody trusts the alerts any more.`);
  ok("a real security conversation surfaces security operations",
     r.status === "leaning" && r.areas[0].id === "es", `${r.status}: ${r.areas.map(a => a.id).join(",")}`);
  ok("it shows the evidence that earned it", r.areas[0].evidence.length >= 3, r.areas[0].evidence.slice(0,4).join(", "));
  ok("its probe is diagnostic, not leading",
     r.areas[0].probes.every(q => !/\b(would you|do you want|are you interested|we (have|offer))\b/i.test(q)),
     r.areas[0].probes[0]);
}
{
  const r = solutionSignals(`We ingest about four terabytes a day and the licence cost is out of control.
    Worse, PII keeps landing in indexes it should never reach, and we are masking it after the fact
    by hand. We need to decide what we actually keep.`);
  ok("a data and cost conversation surfaces ingest control",
     r.areas[0]?.id === "data", r.areas.map(a => a.id).join(","));
}

console.log("\n— anti-funnelling —");
{
  // The case the whole design exists for: a call that is genuinely about two things must not be
  // collapsed into one product pitch just because one scored a point higher.
  const r = solutionSignals(`Our SOC is overwhelmed with false positives from the SIEM and the tier one
    analysts cannot keep up. Separately, the checkout page latency is killing us, users abandon the cart
    and we cannot trace where the time goes across those microservices.`);
  const ids = r.areas.map(a => a.id);
  ok("both live areas are shown, not just the winner", ids.includes("es") && ids.includes("apm"), ids.join(","));
  ok("it reports the call as contested rather than picking",
     r.status === "contested" && /more than one/i.test(r.note), `${r.status}`);
}
{
  // The rep's own words must never become evidence. serve.mjs only ever passes customer turns, and
  // this pins the reason why that matters.
  const repTalk = `Enterprise Security gives you risk based alerting and correlation searches and MITRE
    coverage, and the SOC gets notable events with risk scores.`;
  const r = solutionSignals(repTalk);
  ok("NOTE: rep speech would score, which is why callers must pass customer turns only",
     r.status !== "open", `${r.status} — serve.mjs filters t.me before calling`);
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);

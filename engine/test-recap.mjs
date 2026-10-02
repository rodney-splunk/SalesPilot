// End-of-call recap tests — run: `node test-recap.mjs` from engine/.
// The recap runs once, at hang-up, on a path nothing else exercises, and it is the last thing the
// rep sees. Until now it had no coverage at all.
import { spawn } from "child_process";
import { readFileSync } from "fs";
import { tmpdir } from "os";

import os from "node:os";
import { rmSync } from "node:fs";
// Hermetic: never let a prep the user has active change what these tests see.
process.env.PREP_FILE = process.env.PREP_FILE || `${os.tmpdir()}/salespilot-test-prep.txt`;
rmSync(process.env.PREP_FILE, { force: true });   // start every run with no prep

const HERE = new URL(".", import.meta.url).pathname;
let pass = 0, fail = 0;
const ok = (label, cond, detail = "") => {
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}${detail ? `   (${detail})` : ""}`);
  cond ? pass++ : fail++;
};

function runCall(seq, { recap = true } = {}) {
  return new Promise((resolve) => {
    const f = `${tmpdir()}/recap-${process.pid}-${Math.random().toString(36).slice(2)}.json`;
    const p = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE, env: { ...process.env, SESSION_FILE: f } });
    p.stderr.on("data", () => {});
    (async () => {
      await new Promise((r) => setTimeout(r, 1200));
      for (const [spk, text] of seq) { p.stdin.write(JSON.stringify({ speaker: spk, text }) + "\n"); await new Promise((r) => setTimeout(r, 2000)); }
      await new Promise((r) => setTimeout(r, 5000));
      if (recap) p.stdin.write(JSON.stringify({ cmd: "recap" }) + "\n");
      const started = Date.now();
      let s = {};
      while (Date.now() - started < 30000) {
        try { s = JSON.parse(readFileSync(f, "utf8")); } catch {}
        if (!recap || (s.recap && s.nextSteps)) break;
        await new Promise((r) => setTimeout(r, 400));
      }
      p.stdin.end(); resolve(s);
    })();
  });
}

const CALL = [
  ["you", "Thanks for making time. I understand you're running into PII compliance issues. Can I ask you some questions?"],
  ["customer", "Sure. Alec Williams, director of data engineering. We ingest four terabytes a day and PII keeps landing in indexes it should not."],
  ["customer", "My team spends about two days a week cleaning it up by hand, and we have an audit in January."],
  ["you", "What does that cost you in engineering time over a quarter?"],
  ["customer", "Roughly a full headcount. I own the budget for the platform so the decision sits with me."],
];

console.log("— end-of-call recap —");
{
  const s = await runCall(CALL);
  ok("a recap is produced", !!(s.recap && s.recap.length > 40), `${(s.recap || "").length} chars`);
  ok("no unagreed next steps invented", (s.nextSteps || []).length === 0, `${(s.nextSteps || []).length} steps`);
  // The whole point of a recap is that it is about THIS call. A generic one is worse than none.
  const blob = `${s.recap} ${(s.nextSteps || []).join(" ")}`.toLowerCase();
  ok("recap is grounded in what was actually said",
     ["pii", "audit", "headcount", "terabyte", "januar"].some((k) => blob.includes(k)),
     blob.slice(0, 70));
  ok("identity survives to the recap", s.customerName === "Alec Williams", JSON.stringify(s.customerName));
  ok("role survives and stays title-cased", s.customerRole === "Director of Data Engineering", JSON.stringify(s.customerRole));
  ok("the budget owner is marked covered", s.coverage?.find((c) => c.name === "Economic Buyer")?.status === "done",
     s.coverage?.find((c) => c.name === "Economic Buyer")?.status);
}
{
  // No recap requested: the session must still be coherent, with no half-written recap fields.
  const s = await runCall(CALL.slice(0, 2), { recap: false });
  ok("without a recap request, no recap is invented", !s.recap, JSON.stringify(s.recap ?? null));
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);

// Compare coaching quality and cost across providers on identical prompts.
//   PROVIDER=circuit node bench-provider.mjs
//   ANTHROPIC_API_KEY=sk-... PROVIDER=claude node bench-provider.mjs
//
// Same four objective measures used to compare the CIRCUIT models, so results are comparable:
//   on-target   honored the forced coaching element
//   clean Qs    passed the engine's own validator (anchored, one question, <=18 words, no jargon)
//   over-claim  elements marked "done" the transcript does not support (lower is better)
//   latency     median round trip
import { PACKS } from "./packs.mjs";
import { questionIssues, fastTier, MODELS, PROVIDER } from "./core.mjs";

const N = Number(process.env.RUNS || 3);
const pack = PACKS.meddic;
const TRANSCRIPT = `me: Walk me through how alerts reach your team today.
cust: Our SOC is drowning. Tier one analysts spend the whole day on false positives from the SIEM.
me: What happens when a real one comes in?
cust: Honestly it gets lost. We missed a real intrusion last quarter because it looked like the rest.
me: How do you decide what gets worked first?
cust: Whoever shouts loudest. There is no risk scoring, every correlation search fires the same.`;
const norm = (s) => (s || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const TNORM = norm(TRANSCRIPT.split("\n").filter((l) => l.startsWith("cust:")).join(" "));
const UNSUPPORTED = ["economic_buyer","decision_criteria","decision_process","paper_process","champion","competition"];
// Published rates, $ per million tokens. Used only for the rough per-call estimate below.
const PRICE = { "claude-haiku-4-5": [1, 5], "claude-sonnet-5": [2, 10], "claude-opus-5": [5, 25] };

const r = { onTarget: 0, tries: 0, clean: 0, over: [], ms: [], errs: 0 };
for (let i = 0; i < N; i++) {
  for (const targetId of ["metrics", "economic_buyer", "competition"]) {
    const label = pack.elements.find((e) => e.id === targetId).label;
    const guidance = `Your ONE next_question MUST advance "${label}" — set "targets":"${targetId}".`;
    const t0 = Date.now();
    let obj = null;
    try { obj = JSON.parse(await fastTier(pack, TRANSCRIPT, guidance)); } catch { r.errs++; }
    r.ms.push(Date.now() - t0); r.tries++;
    if (!obj) continue;
    const q = (obj.next_questions || [])[0];
    if (q?.targets === targetId) r.onTarget++;
    if (q?.text && questionIssues(q, TNORM, pack.name).length === 0) r.clean++;
    r.over.push(UNSUPPORTED.filter((id) => obj.coverage?.[id] === "done").length);
  }
}
const med = r.ms.sort((a, b) => a - b)[Math.floor(r.ms.length / 2)];
const avgOver = (r.over.reduce((a, b) => a + b, 0) / Math.max(r.over.length, 1)).toFixed(1);
const model = (MODELS[PROVIDER] || MODELS.ollama).fast;
console.log(`\n  provider ${PROVIDER}  (fast tier: ${model})`);
console.log(`  on-target ${r.onTarget}/${r.tries}   clean ${r.clean}/${r.tries}   over-claim ${avgOver}/6   median ${med}ms${r.errs ? `   errors ${r.errs}` : ""}`);
if (PRICE[model]) {
  // A real call is ~65 coaching passes at roughly 1.9k in / 0.5k out.
  const [pin, pout] = PRICE[model];
  const cost = (65 * 1900 / 1e6) * pin + (65 * 500 / 1e6) * pout;
  console.log(`  rough cost for a 146-turn call at this tier: $${cost.toFixed(2)} (before prompt caching)`);
}

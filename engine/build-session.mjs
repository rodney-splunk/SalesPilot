// build-session.mjs — turn a transcript into a review session the native app can load.
// Reads a transcript (lines, optionally prefixed "me:" / "cust:"), runs the REAL engine
// (fastTier: grounded + validated questions) per customer turn, and writes latest.json
// in the schema ReviewView.swift decodes.
//
//   node build-session.mjs --framework meddic --in ../sessions/dictation.log
//   (defaults: framework=meddic, in=../sessions/dictation.log, out=../sessions/latest.json)
//
// Lines with no prefix are treated as CUSTOMER turns (solo-dictation friendly). Prefix a line
// with "me:" to mark it as the seller. Blank lines are ignored.

import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { PACKS } from "./packs.mjs";
import { fastTier } from "./core.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return def;
  const next = process.argv[i + 1];
  return !next || next.startsWith("--") ? true : next;
};

const fw = String(arg("framework", "meddic")).toLowerCase();
const pack = PACKS[fw] || PACKS.meddic;
const inPath = resolve(here, String(arg("in", "../sessions/dictation.log")));
const outPath = resolve(here, String(arg("out", "../sessions/latest.json")));

if (!existsSync(inPath)) {
  console.error(`No transcript at ${inPath}. Dictate first, or pass --in <file>.`);
  process.exit(1);
}

// Parse the transcript into speaker-tagged turns.
const rawLines = readFileSync(inPath, "utf8").split("\n").map((l) => l.trim()).filter(Boolean);
const turns = rawLines.map((line) => {
  const m = line.match(/^(me|you|rep|cust|customer|them)\s*:\s*(.*)$/i);
  if (m) {
    const who = /^(me|you|rep)$/i.test(m[1]) ? "me" : "cust";
    return { me: who === "me", text: m[2] };
  }
  return { me: false, text: line }; // unprefixed → customer
});

const mmss = (sec) => `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(sec % 60).padStart(2, "0")}`;
const labelOf = (id) => pack.elements.find((e) => e.id === id)?.label || id;

const parse = (s) => {
  if (!s) return null;
  const f = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = f ? f[1] : s;
  const a = body.indexOf("{"), b = body.lastIndexOf("}");
  if (a < 0 || b < 0) return null;
  try { return JSON.parse(body.slice(a, b + 1)); } catch { return null; }
};

let rolling = "";
let clock = 3;
let coverage = {};
const outTurns = [];
const nextqDedup = new Map();

for (const t of turns) {
  clock += 4 + Math.round(t.text.split(/\s+/).length / 3); // rough spoken pacing
  const speaker = t.me ? "me" : "cust";
  rolling += `${speaker}: ${t.text}\n`;
  const turnOut = { me: t.me, who: t.me ? "You" : "Customer", time: mmss(clock), text: t.text, coachTarget: null, coachQ: null };

  if (!t.me) {
    process.stderr.write(`· coaching on: "${t.text.slice(0, 48)}..."\n`);
    let obj = null;
    try { obj = parse(await fastTier(pack, rolling.trim())); }
    catch (e) { process.stderr.write(`fast-tier error (is Ollama running?): ${e.message}\n`); }
    if (obj) {
      if (obj.coverage) coverage = { ...coverage, ...obj.coverage };
      const q = Array.isArray(obj.next_questions) ? obj.next_questions[0] : null;
      if (q?.text) {
        turnOut.coachTarget = labelOf(q.targets);
        turnOut.coachQ = q.text;
      }
      for (const nq of obj.next_questions || []) {
        if (nq?.text) nextqDedup.set(nq.text, { q: nq.text, tag: labelOf(nq.targets) });
      }
    }
  }
  outTurns.push(turnOut);
}

// Final coverage over the full framework, in the pack's canonical order.
const covArr = pack.elements.map((e) => ({ name: e.label, status: coverage[e.id] || "open" }));
const score = covArr.reduce((s, c) => s + (c.status === "done" ? 1 : c.status === "partial" ? 0.5 : 0), 0);
const pct = Math.round((score / covArr.length) * 100);

const firstCust = turns.find((t) => !t.me)?.text || "Discovery call";
const session = {
  title: "Discovery — live session",
  subtitle: `${pack.name} · ${firstCust.slice(0, 42)}`,
  framework: pack.name,
  coveragePct: pct,
  turns: outTurns,
  coverage: covArr,
  nextq: [...nextqDedup.values()].slice(0, 3),
};

mkdirSync(dirname(outPath), { recursive: true });
const tmp = `${outPath}.tmp`;
writeFileSync(tmp, JSON.stringify(session, null, 2));
renameSync(tmp, outPath); // atomic
console.error(`\n✓ wrote ${outPath} — ${outTurns.length} turns, ${pct}% ${pack.name} coverage, ${session.nextq.length} questions`);

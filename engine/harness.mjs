#!/usr/bin/env node
// One-shot harness — run the brain against a FULL transcript file (Phase 0 validation).
//   node harness.mjs --framework meddic --transcript ../sample-transcript.md [--strategy]
//   OLLAMA_FAST=qwen2.5:14b node harness.mjs ...          (bigger fast model)
//   node harness.mjs --provider claude ...                 (needs ANTHROPIC_API_KEY)

import { readFile } from "node:fs/promises";
import { PACKS } from "./packs.mjs";
import { PROVIDER, M, fastTier, strategyPanel } from "./core.mjs";

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return def;
  const next = process.argv[i + 1];
  return (!next || next.startsWith("--")) ? true : next;
}

const pack = PACKS[arg("framework", "meddic")];
if (!pack) { console.error(`Unknown framework. Options: ${Object.keys(PACKS).join(", ")}`); process.exit(1); }
const transcript = await readFile(new URL(arg("transcript", "../sample-transcript.md"), import.meta.url), "utf8");

console.log(`\n[provider: ${PROVIDER} · fast=${M.fast} · judge=${M.judge}]`);
console.log(`\n=== ${pack.name} · fast tier ===`);
console.log(await fastTier(pack, transcript));

if (arg("strategy", false)) {
  console.log(`\n=== ${pack.name} · strategy panel (4 agents + judge) ===`);
  const { proposals, judged } = await strategyPanel(pack, transcript);
  for (const p of proposals) console.log(`\n[${p.lens}]\n${p.raw}`);
  console.log(`\n--- JUDGE ---\n${judged}`);
}

// ghost-prep.mjs — draft call prep from internal sources via the Ghost CLI (Slack + Confluence +
// JIRA), summarized by the local model into sessions/prep.txt. An optional --header (e.g. the
// meeting title + attendees from the calendar) is prepended.
//
//   node ghost-prep.mjs "Northwind"
//   node ghost-prep.mjs --header "Meeting: QBR with Northwind" "Northwind"
//
// Slack needs `dev-login slack`; Confluence/JIRA need `ghost auth login`. Sources that aren't
// authed are reported (needAuth=...) so the app can prompt the user to log in.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { callLLM, M } from "./core.mjs";
import { sfdcPrepLines } from "./sfdc.mjs";

const execFileAsync = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const GHOST = `${process.env.HOME}/go/bin/ghost`;

const rawArgs = process.argv.slice(2);
let header = null;
let draftOnly = false;
const rest = [];
for (let i = 0; i < rawArgs.length; i++) {
  if (rawArgs[i] === "--draft") draftOnly = true;
  else if (rawArgs[i] === "--header") header = rawArgs[++i] || null;
  else rest.push(rawArgs[i]);
}
const query = rest.join(" ").trim();
if (!query) { console.error("Usage: node ghost-prep.mjs [--header <text>] <account/customer>"); process.exit(1); }

const used = [];
const needAuth = [];

function extractGeneric(raw, fields, whoField) {
  let data;
  try { data = JSON.parse(raw); } catch { return []; }
  const arr = Array.isArray(data) ? data : (data.results || data.messages || data.issues || data.matches || data.pages || []);
  return arr.map((it) => {
    if (typeof it === "string") return it;
    const who = whoField ? (it[whoField] || "") : "";
    const flat = fields.map((f) => it[f]).filter((v) => typeof v === "string" && v).join(" — ");
    const nested = it.fields ? [it.fields.summary, it.fields.description].filter((v) => typeof v === "string").join(" — ") : "";
    const text = flat || nested;
    return text ? (who ? `${who}: ${text}` : text) : "";
  }).filter(Boolean);
}

async function source(label, args, fields, whoField) {
  try {
    const { stdout } = await execFileAsync(GHOST, args,
      { maxBuffer: 16 * 1024 * 1024, timeout: 30_000, killSignal: "SIGKILL" });
    const items = extractGeneric(stdout, fields, whoField);
    if (items.length) { used.push(label); return items.map((x) => `[${label}] ${x}`); }
    return [];
  } catch (e) {
    // Any failure on Confluence/JIRA is almost always auth (they're behind Atlassian SSO).
    needAuth.push(label);
    return [];
  }
}

const slack = await source("Slack", ["slack", "search", query, "--json", "--limit", "20"], ["text"], "username");

let sfdc = [];
try {
  const lines = await sfdcPrepLines(query);
  if (lines.length) { used.push("Salesforce"); sfdc = lines.map((l) => `[Salesforce] ${l}`); }
} catch { needAuth.push("Salesforce"); }

const all = [...slack, ...sfdc];

let note = "";
if (all.length) {
  const sys =
`You are prepping a sales engineer for a call about "${query}". From these internal notes, write a
SHORT prep note (5-9 lines): the customer's situation, known pain/issues, people involved, current
status, and the open questions to resolve on the call. Plain text, concise, no preamble/markdown.`;
  try {
    note = await callLLM(M.worker, sys, `Internal notes about ${query}:\n\n${all.join("\n---\n").slice(0, 9000)}`, 500);
  } catch (e) {
    console.error(`Summary failed (is Ollama running?): ${e.message}`);
  }
}

if (!all.length && !header) {
  console.error(`No results for "${query}". needAuth=${needAuth.join(",") || "none"} (run: ghost auth login)`);
  process.exit(3);
}

if (all.length && !note.trim()) {
  note = "Source notes for review:\n" + all.slice(0, 8).map(line => line.slice(0, 650)).join("\n");
}
const body = [header ? header.trim() : null, note.trim() || null].filter(Boolean).join("\n\n");
const content = `Account: ${query}\n\n${body}\n`;
if (draftOnly) {
  console.log(JSON.stringify({ content, sources: used, needAuth }));
  process.exit(0);
}
const out = resolve(here, "../sessions/prep.txt");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, content); // active prep

// Also save a named copy so it shows under "Saved Preps" (one per customer).
const prepDir = resolve(here, "../sessions/prep");
mkdirSync(prepDir, { recursive: true });
const slug = query.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 50) || "prep";
writeFileSync(resolve(prepDir, `${slug}.txt`), content);
console.log(`PREP_OK sources=${used.join(",") || "none"} needAuth=${needAuth.join(",") || "none"} slug=${slug}`);
// The prep is on disk and the caller waits on our exit to open the window. A lingering handle from
// a timed-out source must not turn a finished prep into a silent hang, so leave deliberately.
process.exit(0);

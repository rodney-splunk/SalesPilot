// rag.mjs — tiny on-device retrieval over your own docs. Index ~/Documents/sales-copilot/sessions/docs
// (.md/.txt) with local Ollama embeddings, then answer a live question grounded in the top chunks.
// 100% local. Used by serve.mjs to surface answers when the customer asks something mid-call.
//
//   node rag.mjs index      # (re)build the index from sessions/docs
//   node rag.mjs ask "..."  # test a query

import { readFileSync, writeFileSync, renameSync, readdirSync, existsSync, mkdirSync, statSync } from "node:fs";
import { execFile } from "node:child_process";
import {promisify} from "node:util";
const runFile=promisify(execFile);
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const DOCS = process.env.SALESPILOT_DOCS_DIR || resolve(here, "../sessions/docs");
const INDEX = process.env.SALESPILOT_RAG_INDEX || resolve(here, "../sessions/rag-index.json");
const EMBED_MODEL = process.env.OLLAMA_EMBED || "nomic-embed-text";

async function embed(text) {
  const res = await fetch("http://localhost:11434/api/embeddings", {
    signal: AbortSignal.timeout(3000), method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, prompt: text }),
  });
  if (!res.ok) throw new Error(`embed ${res.status}: ${await res.text()}`);
  const vector = (await res.json()).embedding;
  if (!Array.isArray(vector) || !vector.length || !vector.every(Number.isFinite)) throw new Error("Invalid embedding response");
  return vector;
}

function chunk(text, size = 700, overlap = 100) {
  const clean = text.replace(/\s+/g, " ").trim();
  const out = [];
  for (let i = 0; i < clean.length; i += size - overlap) out.push(clean.slice(i, i + size));
  return out.filter((c) => c.trim().length > 0);
}

// Extract plain text from a doc: md/txt directly, docx via textutil, pdf via pdftotext or pypdf.
async function extractText(path, name) {
  try {
    if (/\.(md|markdown|txt)$/i.test(name)) return readFileSync(path, "utf8");
    if (/\.docx$/i.test(name)) {
      return (await runFile("/usr/bin/textutil", ["-convert", "txt", "-stdout", path], { timeout: 20000, maxBuffer: 64 * 1024 * 1024 })).stdout;
    }
    if (/\.pdf$/i.test(name)) {
      for (const cmd of (process.env.SALESPILOT_APPROVED_POPPLER === "1" ? ["/opt/homebrew/bin/pdftotext", "/usr/local/bin/pdftotext"] : [])) {
        try { return (await runFile(cmd, ["-q", path, "-"], { timeout: 20000, maxBuffer: 64 * 1024 * 1024 })).stdout; } catch {}
      }
      const py = `${process.env.HOME}/Documents/sales-copilot/.iconvenv/bin/python`;
      return (await runFile(py, ["-c", "import sys,pypdf;print(chr(10).join((p.extract_text() or '') for p in pypdf.PdfReader(sys.argv[1]).pages))", path], { timeout: 20000, maxBuffer: 64 * 1024 * 1024 })).stdout;
    }
  } catch { /* unreadable/converter missing → skip this file */ }
  return "";
}

const DOC_RE = /\.(md|markdown|txt|pdf|docx)$/i;

function currentFiles() {
  return readdirSync(DOCS).filter((f) => DOC_RE.test(f) && statSync(join(DOCS, f)).isFile())
    .map((f) => ({ name: f, mtime: Math.round(statSync(join(DOCS, f)).mtimeMs) }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export async function index() {
  mkdirSync(DOCS, { recursive: true });
  mkdirSync(dirname(INDEX), { recursive: true });
  const files = currentFiles();
  const records = [];
  const skipped = [];
  let embeddingAvailable = true;
  for (const { name } of files) {
    const text = await extractText(join(DOCS, name), name);
    if (!text.trim()) {
      skipped.push(name);
      console.error(`[rag] no text from ${name} (converter missing, empty, or scanned PDF?)`);
    }
    for (const c of chunk(text)) {
      let vector = null;
      if (embeddingAvailable) {
        try { vector = await embed(c); } catch { embeddingAvailable = false; }
      }
      records.push({ file: name, text: c, embedding: vector });
    }
  }
  const payload = { model: EMBED_MODEL, dim: records[0]?.embedding?.length || 0, files, records };
  const tmp = `${INDEX}.${process.pid}.tmp`; // per-process temp so concurrent indexers can't corrupt each other
  writeFileSync(tmp, JSON.stringify(payload),{mode:0o600});
  renameSync(tmp, INDEX); // atomic
  cache = payload; cacheMtime = statSync(INDEX).mtimeMs;
  return { chunks: records.length, files: files.length, readableFiles: files.length - skipped.length, skipped };
}

// Re-index when the doc SET changes (add/remove/rename/mtime) OR the embed model changes — so deleted
// docs stop being quoted and a model/dim change can't silently kill search.
export async function indexIfStale() {
  if (!existsSync(DOCS)) return { chunks: 0, files: 0, reindexed: false };
  const files = currentFiles();
  const idx = loadIndex();
  const filesChanged = !idx || JSON.stringify(idx.files || []) !== JSON.stringify(files);
  const modelChanged = !idx || idx.model !== EMBED_MODEL;
  if (!filesChanged && !modelChanged) return { chunks: 0, files: files.length, reindexed: false };
  const r = await index();
  return { ...r, reindexed: true };
}

function cosine(a, b) {
  if (!a || !b || a.length !== b.length) return 0;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  const denom = Math.sqrt(na) * Math.sqrt(nb);
  return denom ? dot / denom : 0;
}

let cache = null;       // { model, dim, files, records }
let cacheMtime = 0;

function loadIndex() {
  if (!existsSync(INDEX)) return null;
  const mtime = statSync(INDEX).mtimeMs;
  if (cache && mtime === cacheMtime) return cache;
  try {
    const raw = JSON.parse(readFileSync(INDEX, "utf8"));
    cache = Array.isArray(raw) ? { model: null, files: [], records: raw } : raw; // back-compat with old array format
    cacheMtime = mtime;
  } catch { cache = null; }
  return cache;
}

export async function search(question, k = 3) {
  if (process.env.SALESPILOT_PRACTICE === "1") return []; // fictional practice never reads customer reference indexes
  const idx = loadIndex();
  if (!idx || !idx.records || !idx.records.length) return [];
  let q;
  try { q = idx.records.some(r => r.embedding?.length) ? await embed(question) : null; } catch { q = null; }
  const tokens = [...new Set(question.toLowerCase().match(/[a-z0-9]{3,}/g) || [])].filter(t => !new Set(["what","does","this","that","with","have","your","can","how","the","for","are"]).has(t));
  return idx.records
    .map((r) => ({ file: r.file, text: r.text, score: Math.max(cosine(q, r.embedding), tokens.length ? tokens.filter(t => r.text.toLowerCase().includes(t)).length / tokens.length * 0.7 : 0) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, k)
    .filter((r) => r.score > 0.35);
}

const mode = process.argv[2];
if (mode === "index") {
  index().then((r) => {
    console.log(process.argv.includes("--json") ? JSON.stringify(r) : `Indexed ${r.chunks} chunks from ${r.readableFiles} readable files. ${r.skipped.length} skipped.`);
    if (r.files > 0 && r.chunks === 0) process.exitCode = 2;
  })
    .catch((e) => { console.error(e.message); process.exit(1); });
} else if (mode === "ask") {
  search(process.argv.slice(3).join(" "), 3)
    .then((hits) => console.log(JSON.stringify(hits.map((h) => ({ file: h.file, score: +h.score.toFixed(3) })), null, 2)))
    .catch((e) => { console.error(e.message); process.exit(1); });
}

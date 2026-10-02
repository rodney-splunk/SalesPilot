import {privateText} from './privacy.mjs';
import {completedThought} from './coach-timing.mjs';
import { abortable, recordTiming } from './performance.mjs';
// Shared engine core — used by harness.mjs (one-shot) and serve.mjs (streaming).
import { circuitToken, circuitConfig, circuitCredentials } from "./circuit.mjs";

export const PROVIDER = (process.argv.includes("--provider")
  ? process.argv[process.argv.indexOf("--provider") + 1]
  : process.env.PROVIDER) || "ollama";

// Cisco CIRCUIT / BridgeIT (Azure OpenAI gateway): OAuth token in the `api-key` header, the AppKey
// in the request body's `user` field. Discovered empirically against the live endpoint.
async function callCircuit(model, messages, max_tokens, ac, format) {
  const c = await abortable(circuitCredentials(), ac.signal);
  const token = await abortable(circuitToken(), ac.signal);
  ac.signal.throwIfAborted();
  const endpoint=new URL(c.inference_url);
  if(endpoint.protocol!=='https:'||endpoint.hostname!=='chat-ai.cisco.com'||endpoint.username||endpoint.password)throw Error('Unapproved CIRCUIT inference endpoint');
  const url = `${c.inference_url}/openai/deployments/${model}/chat/completions?api-version=${c.api_version}`;
  const masks=messages.map(m=>privateText(m.content));
  const restore=value=>masks.reduce((text,mask)=>mask.restore(text),value);
  const masked=messages.map((m,i)=>({...m,content:masks[i].text}));
  const payload = { messages:masked, max_tokens, user: JSON.stringify({ appkey: c.app_key }) };
  if (format) payload.response_format = { type: "json_object" }; // gateway supports JSON mode; prompt carries the shape
  const res = await fetch(url, {
    method: "POST", signal: ac.signal, redirect:"error",
    headers: { "api-key": token, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`CIRCUIT request failed (${res.status})`);
  return restore((await res.json()).choices?.[0]?.message?.content || "");
}

/// Streaming variant. The gateway answers text/event-stream, so the cue can be shown as it forms
/// instead of after the whole object lands. onDelta receives the ACCUMULATED text each time.
async function callCircuitStream(model, messages, max_tokens, ac, format, onDelta) {
  const c = await abortable(circuitCredentials(), ac.signal);
  const token = await abortable(circuitToken(), ac.signal);
  ac.signal.throwIfAborted();
  const endpoint=new URL(c.inference_url);
  if(endpoint.protocol!=='https:'||endpoint.hostname!=='chat-ai.cisco.com'||endpoint.username||endpoint.password)throw Error('Unapproved CIRCUIT inference endpoint');
  const url = `${c.inference_url}/openai/deployments/${model}/chat/completions?api-version=${c.api_version}`;
  const masks=messages.map(m=>privateText(m.content));
  const restore=value=>masks.reduce((text,mask)=>mask.restore(text),value);
  const masked=messages.map((m,i)=>({...m,content:masks[i].text}));
  const payload = { messages:masked, max_tokens, stream: true, user: JSON.stringify({ appkey: c.app_key }) };
  if (format) payload.response_format = { type: "json_object" };
  const res = await fetch(url, {
    method: "POST", signal: ac.signal, redirect:"error",
    headers: { "api-key": token, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`CIRCUIT request failed (${res.status})`);
  const reader = res.body.getReader(), dec = new TextDecoder();
  let buf = "", full = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl).trim(); buf = buf.slice(nl + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (!data || data === "[DONE]") continue;
      try {
        const piece = JSON.parse(data).choices?.[0]?.delta?.content;
        if (piece) { full += piece; onDelta?.(restore(full)); }
      } catch { /* a partial SSE frame: the next chunk completes it */ }
    }
  }
  return restore(full);
}

export const MODELS = {
  // Local FALLBACK coach (used when CIRCUIT is unreachable, or COACH_LOCAL=1). Measured: 7b honors a
  // forced coaching target 0/3 — that IS the "same question six times" bug. 14b honors it 3/3 at ~6.2s
  // vs 2.8s. Slower, but a fallback that actually advances the call beats a fast one that loops.
  ollama: { fallback: process.env.OLLAMA_FALLBACK || "qwen2.5:7b", fast: process.env.OLLAMA_FAST || "qwen2.5:14b", worker: process.env.OLLAMA_WORKER || "qwen2.5:7b", judge: process.env.OLLAMA_JUDGE || "qwen2.5:7b" },
  // Tiered on purpose. The live cue is latency-critical, so it gets Haiku with thinking off. Coverage,
  // identity and the recap run where a second or two costs nothing, so they get a stronger model.
  // Model IDs carry no date suffix; appending one is a 404.
  claude: {
    fast:   process.env.CLAUDE_FAST   || "claude-haiku-4-5",   // live cue: fastest tier
    worker: process.env.CLAUDE_WORKER || "claude-sonnet-5",    // coverage, roster, ASR cleanup
    judge:  process.env.CLAUDE_JUDGE  || "claude-opus-5",      // end-of-call recap
  },
  // CIRCUIT = gemini-3.1-flash-lite everywhere: ~0.9s and matched gpt-5-nano's quality on our tasks,
  // while gpt-5-nano (a reasoning model) is ~6x slower for no gain. gpt-5-nano stays reachable via
  // CIRCUIT_FAST/CIRCUIT_WORKER if a task ever needs deeper reasoning and can eat the latency.
  circuit: { fast: process.env.CIRCUIT_FAST || "gemini-3.1-flash-lite", worker: process.env.CIRCUIT_WORKER || "gemini-3.1-flash-lite", judge: "gemini-3.1-flash-lite" },
};
export const M = MODELS[PROVIDER] || MODELS.ollama;

export async function callLLM(model, system, user, max_tokens = 800, timeoutMs = 45000, format = null, options = {}) {
  const masked=privateText(user), maskedSystem=privateText(system);
  const result=await callLLMTransport(model,maskedSystem.text,masked.text,max_tokens,timeoutMs,format,options);
  return maskedSystem.restore(masked.restore(result));
}
async function callLLMTransport(model, system, user, max_tokens = 800, timeoutMs = 45000, format = null, options = {}) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(new DOMException("Model deadline", "TimeoutError")), timeoutMs);
  const parentAbort = () => ac.abort(options.signal.reason);
  options.signal?.addEventListener("abort", parentAbort, {once:true});
  if (options.signal?.aborted) parentAbort();
  const provider = options.provider || PROVIDER;
  try {
    if(process.env.SALESPILOT_LOCAL_ONLY==='1' && provider!=='ollama')throw Error("Local-only processing blocks hosted inference");
    if(!["ollama","circuit"].includes(provider))throw new Error("Only local inference and Cisco CIRCUIT are enabled for this internal tool.");
    ac.signal.throwIfAborted();
    if (provider === "ollama") {
      const res = await fetch("http://localhost:11434/api/chat", {
        method: "POST", headers: { "content-type": "application/json" }, signal: ac.signal,
        body: JSON.stringify({ model, stream: false, keep_alive: "30m", ...(format ? { format } : {}), options: { num_predict: max_tokens, temperature: 0.4 },
          messages: [{ role: "system", content: system }, { role: "user", content: user }] }),
      });
      if (!res.ok) throw new Error(`Local model request failed (${res.status})`);
      return (await res.json()).message.content;
    }
    if (provider === "circuit") {
      return await callCircuit(model, [{ role: "system", content: system }, { role: "user", content: user }], max_tokens, ac, format);
    }
    const key = process.env.ANTHROPIC_API_KEY;
    if (!key) throw new Error("Set ANTHROPIC_API_KEY for --provider claude.");
    const body = {
      model, max_tokens,
      // The coaching system prompt is identical on every call of a session, so cache it. A live call
      // makes ~65 of these; without caching you pay full input price for the same preamble each time.
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: user }],
    };
    // Thinking is on by default on Sonnet 5 and Opus 5, which is right for a recap and wrong for a
    // cue the rep is waiting on. Turn it off for the fast tier only. Haiku has no thinking to disable.
    if (model.startsWith("claude-sonnet-5") && max_tokens <= 600) body.thinking = { type: "disabled" };
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", signal: ac.signal, redirect:"error",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Claude API ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const j = await res.json();
    if (process.env.CLAUDE_USAGE) console.error(`[claude] ${model} in=${j.usage?.input_tokens} cached=${j.usage?.cache_read_input_tokens ?? 0} out=${j.usage?.output_tokens}`);
    return (j.content || []).map((b) => b.text || "").join("");
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener("abort", parentAbort);
  }
}

// Streaming variant — calls onDelta(fullTextSoFar) as tokens arrive so the UI can fill in live.
// Ollama streams NDJSON; other providers fall back to one call (still invokes onDelta once).
export async function callLLMStream(model, system, user, max_tokens = 256, onDelta = null, timeoutMs = 45000) {
  const maskedSystem=privateText(system), maskedUser=privateText(user);
  const restore=value=>maskedSystem.restore(maskedUser.restore(value));
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    if (PROVIDER === "ollama") {
      const res = await fetch("http://localhost:11434/api/chat", {
        method: "POST", headers: { "content-type": "application/json" }, signal: ac.signal,
        body: JSON.stringify({ model, stream: true, keep_alive: "30m", options: { num_predict: max_tokens, temperature: 0.4 },
          messages: [{ role: "system", content: maskedSystem.text }, { role: "user", content: maskedUser.text }] }),
      });
      if (!res.ok) throw new Error(`Local model request failed (${res.status})`);
      let full = "", buf = "";
      const reader = res.body.getReader();
      const dec = new TextDecoder();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let nl;
        while ((nl = buf.indexOf("\n")) >= 0) {
          const line = buf.slice(0, nl).trim(); buf = buf.slice(nl + 1);
          if (!line) continue;
          try { const piece = JSON.parse(line).message?.content || ""; if (piece) { full += piece; onDelta?.(restore(full)); } } catch { /* skip partial line */ }
        }
      }
      return restore(full);
    }
    // non-streaming providers (claude / circuit): one call, single delta.
    const full = await callLLM(model, system, user, max_tokens, timeoutMs);
    onDelta?.(full);
    return full;
  } finally {
    clearTimeout(timer);
  }
}

export function circuitAvailable() {
  if (process.env.SALESPILOT_OFFLINE === "1" || process.env.SALESPILOT_LOCAL_ONLY === "1") return false;
  const c = circuitConfig();
  return !!(c.client_id && (c.client_secret || c.credential_store==='macos-keychain') && c.inference_url);
}

// Identify the customer from their words with a REAL model, not regex — so noisy ASR ("I'm Dahna,
// uh, with Acme") still resolves name + role + authority. Runs async off the live loop, so its
// latency is hidden. Prefers CIRCUIT (a stronger model) when configured; else the local coach model.
export async function extractIdentityAI(customerText) {
  const sys =
`From the CUSTOMER's words on a sales call, list EVERYONE on the customer side who introduced themselves.
Return ONLY JSON:
{ "people": [ { "name": "<name, capitalized>", "role": "<their role/title in a few plain words, else empty>", "decision_maker": true|false } ] }
Include a person if they stated a name as themselves. A plain introduction always counts:
"Sure. Alec Williams, Director of Data Engineering" -> include Alec Williams.
EXCLUDE only introductions that are explicitly being QUOTED or DEMONSTRATED, i.e. where the speaker
is showing what someone else should say. The tell is framing like "you basically say ...",
"you would say ...", "for example ...", or an introduction sitting inside quotation marks:
"So you basically say, 'Hey guys, my name's Rami, I'm an SE at Splunk'" -> include NOBODY.
Absent that framing, treat the introduction as real. Capitalize names properly (e.g. "Dana Reyes").
"decision_maker" is true only if THAT person says they own the budget or make the final call. If nobody
introduced themselves, return { "people": [] }. Never invent a name from ordinary words.`;
  const user = `Customer said:\n${(customerText || "").slice(-1500)}`;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 20000);
  try {
    const raw = circuitAvailable()
      ? await callCircuit(MODELS.circuit.fast, [{ role: "system", content: sys }, { role: "user", content: user }], 400, ac, true)
      : await callLLM(M.fast, sys, user, 400, 20000, "json");   // room for a multi-person roster (was truncating at 120)
    return extractJSON(raw) || {};
  } catch { return {}; } finally { clearTimeout(timer); }
}

// Route a QUALITY task (recap, identity, transcript cleanup — latency not critical, quality is) to the
// best available model: CIRCUIT when configured, else the local worker. NEVER the live coaching loop.
// The live COACH. Prefer CIRCUIT (gemini-flash-lite FOLLOWS the "advance the methodology" guidance the
// local 7b ignores — far less repetition, questions that build on new signals). Falls back to local
// Ollama when CIRCUIT isn't configured/reachable, using the full grammar schema there.
let hostedCoachFailures = 0;
let hostedCoachRetryAt = 0;
export async function warmCoach() {
  // Empty-prompt load of an already installed fallback; no transcript and no download.
  const localModel=circuitAvailable() && !process.env.COACH_LOCAL ? MODELS.ollama.fallback : MODELS.ollama.fast;
  const local=async()=>{
    try {
      const tags=await fetch("http://localhost:11434/api/tags",{signal:AbortSignal.timeout(1500)});
      if(!tags.ok)return;
      const data=await tags.json();
      if(!data.models?.some(m=>m.name===localModel))return;
      const started=performance.now();
      const loaded=await fetch("http://localhost:11434/api/generate",{method:"POST",headers:{"content-type":"application/json"},signal:AbortSignal.timeout(30000),body:JSON.stringify({model:localModel,prompt:"",stream:false,keep_alive:"30m"})});
      recordTiming("localModelWarm",performance.now()-started,loaded.ok?"ok":"error");
    } catch { /* Optional local service. Capture and configured Cisco processing remain independent. */ }
  };
  await Promise.allSettled([local(),circuitAvailable() && !process.env.COACH_LOCAL ? circuitToken() : Promise.resolve()]);
}
export async function callCoach(system, user, max_tokens, schema, onDelta = null, options = {}) {
  const remoteOnly = options.remoteOnly || process.env.CIRCUIT_BENCH_ONLY === "1";
  const parent = options.signal;
  parent?.throwIfAborted();
  const localMs = Number(process.env.COACH_LOCAL_TIMEOUT_MS || 5000);
  if (PROVIDER === "claude") return callLLM(M.fast, system, user, max_tokens, 8000, schema, {signal:parent});
  if (circuitAvailable() && !process.env.COACH_LOCAL && (remoteOnly || Date.now() >= hostedCoachRetryAt)) {
    const ac = new AbortController();
    const cancel = () => ac.abort(parent.reason);
    parent?.addEventListener("abort", cancel, {once:true});
    if(parent?.aborted) cancel();
    const started = performance.now();
    const timer = setTimeout(() => ac.abort(new DOMException("Hosted coach deadline", "TimeoutError")), Number(process.env.COACH_HOSTED_TIMEOUT_MS || (remoteOnly ? 30000 : 5000)));
    try {
      ac.signal.throwIfAborted();
      const messages = [{role:"system",content:system},{role:"user",content:user}];
      const result = await abortable(onDelta
        ? callCircuitStream(MODELS.circuit.fast, messages, max_tokens, ac, true, onDelta)
        : callCircuit(MODELS.circuit.fast, messages, max_tokens, ac, true), ac.signal);
      hostedCoachFailures=0;hostedCoachRetryAt=0;
      recordTiming("hostedCoach",performance.now()-started,"ok",MODELS.circuit.fast);
      return result;
    } catch(error) {
      recordTiming("hostedCoach",performance.now()-started,parent?.aborted?"cancelled":ac.signal.aborted?"timeout":"error",MODELS.circuit.fast);
      if(parent?.aborted || remoteOnly) throw error;
      if(++hostedCoachFailures >= 2) hostedCoachRetryAt=Date.now()+30000;
    } finally {clearTimeout(timer);parent?.removeEventListener("abort",cancel);}
  } else if (remoteOnly) {throw new Error("CIRCUIT unavailable for comparison");}
  parent?.throwIfAborted();
  const started=performance.now();
  const localModel=circuitAvailable() && !process.env.COACH_LOCAL ? MODELS.ollama.fallback : MODELS.ollama.fast;
  try {
    const result=await abortable(callLLM(localModel,system,user,max_tokens,localMs,schema,{signal:parent,provider:"ollama"}),parent);
    recordTiming("localCoach",performance.now()-started,"ok",localModel);return result;
  } catch(error) {recordTiming("localCoach",performance.now()-started,parent?.aborted?"cancelled":"error",localModel);throw error;}
}

export async function callQuality(system, user, max_tokens = 400, format = null, options = {}) {
  const task=options.task || "quality";
  const started=performance.now();
  const workerModel=task === "answer" ? process.env.CIRCUIT_ANSWER || MODELS.circuit.worker
    : task === "recap" ? process.env.CIRCUIT_RECAP || MODELS.circuit.worker : MODELS.circuit.worker;
  let outcome="error";
  try {
    options.signal?.throwIfAborted();
    if(PROVIDER === "claude") {const result=await callLLM(M.worker,system,user,max_tokens,options.timeoutMs || 30000,format,options);outcome="ok";return result;}
    if(circuitAvailable() && !process.env.COACH_LOCAL) {
      const ac=new AbortController();const abort=()=>ac.abort(options.signal.reason);
      options.signal?.addEventListener("abort",abort,{once:true});if(options.signal?.aborted)abort();
      const timer=setTimeout(()=>ac.abort(new DOMException("Background deadline","TimeoutError")),options.timeoutMs||20000);
      try {
        const result=await abortable(callCircuit(workerModel,[{role:"system",content:system},{role:"user",content:user}],max_tokens,ac,format),ac.signal);outcome="ok";return result;
      }catch(error){if(options.signal?.aborted || options.remoteOnly)throw error;}finally{clearTimeout(timer);options.signal?.removeEventListener("abort",abort);}
    }
    if(options.remoteOnly)throw new Error("CIRCUIT unavailable for comparison");
    const result=await abortable(callLLM(MODELS.ollama.worker,system,user,max_tokens,Math.min(options.timeoutMs||15000,15000),format?"json":null,{signal:options.signal,provider:"ollama"}),options.signal);outcome="ok";return result;
  }finally{recordTiming(task,performance.now()-started,options.signal?.aborted?"cancelled":outcome);}
}

// Async ASR cleanup of ONE committed line — fixes obvious mishears ("rebuilding"->"retail") using
// context, verbatim otherwise. Runs on CIRCUIT (network), off the local coach — so it never adds
// live-transcript lag. Guarded against hallucination (rejects a rewrite that changes length too much).
// --- Guards for the ASR cleanup pass -----------------------------------------------------------
// A cleanup step is allowed to fix what the recognizer MIS-HEARD. It is never allowed to change what
// the customer actually said. Observed in a real call: "under one hour" came back as "under a day",
// "by the end of the year" as "by the end of the day", and "puts a contract at risk" as "puts a
// contract on the table". Those reach the coach, the metrics and the recap as fact, so the model's
// instruction not to rephrase is backed by deterministic checks rather than trusted.
// Number words map to their value so that a legitimate normalization ("sock two audit" -> "SOC 2
// audit") is not mistaken for a changed fact, while a real change ("one hour" -> "a day") still is.
const NUMBER_VALUE = {
  zero: "0", one: "1", once: "1", two: "2", twice: "2", three: "3", four: "4", five: "5", six: "6",
  seven: "7", eight: "8", nine: "9", ten: "10", eleven: "11", twelve: "12", thirteen: "13",
  fourteen: "14", fifteen: "15", sixteen: "16", seventeen: "17", eighteen: "18", nineteen: "19",
  twenty: "20", thirty: "30", forty: "40", fifty: "50", sixty: "60", seventy: "70", eighty: "80",
  ninety: "90", hundred: "100", thousand: "1000", million: "1000000", billion: "1000000000",
  dozen: "12", half: "0.5",
};
const NUMBER_WORDS = new Set(Object.keys(NUMBER_VALUE));
const UNIT_WORDS = new Set(["second","seconds","minute","minutes","hour","hours","day","days","week","weeks",
  "month","months","year","years","quarter","quarters","percent","dollar","dollars","cent","cents",
  "gb","tb","pb","mb","k","x"]);

const wordsOf = (s) => (String(s).toLowerCase().match(/[a-z0-9']+/g) || []);

/// Every number, unit and time word, sorted. These must survive a cleanup untouched.
export function factTokens(s) {
  return wordsOf(s)
    .filter((w) => /\d/.test(w) || NUMBER_WORDS.has(w) || UNIT_WORDS.has(w))
    .map((w) => NUMBER_VALUE[w] ?? w.replace(/^0+(?=\d)/, ""))
    .sort()
    .join(" ");
}

function editSimilarity(a, b) {
  if (a === b) return 1;
  const m = a.length, n = b.length;
  if (!m || !n) return 0;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return 1 - prev[n] / Math.max(m, n);
}

/// A real ASR fix replaces a word with one that SOUNDS like it ("consumers" -> "consoles"). A
/// paraphrase replaces it with something that merely means something similar. Reject the latter.
export function substitutionsArePlausible(orig, out, minSim = 0.35) {
  const A = wordsOf(orig), B = wordsOf(out);
  const m = A.length, n = B.length;
  const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = A[i - 1] === B[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }
  // Walk the LCS backwards, collecting the runs that differ.
  let i = m, j = n;
  const gapsA = [], gapsB = [];
  let runA = [], runB = [];
  const flush = () => { if (runA.length || runB.length) { gapsA.push(runA.reverse()); gapsB.push(runB.reverse()); runA = []; runB = []; } };
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && A[i - 1] === B[j - 1]) { flush(); i--; j--; }
    else if (j > 0 && (i === 0 || dp[i][j - 1] >= dp[i - 1][j])) { runB.push(B[j - 1]); j--; }
    else { runA.push(A[i - 1]); i--; }
  }
  flush();
  for (let k = 0; k < gapsA.length; k++) {
    const from = gapsA[k].join(" "), to = gapsB[k].join(" ");
    if (!from || !to) {
      // A pure insertion or deletion. One filler word either way is normal cleanup; more is not.
      if ((gapsA[k].length + gapsB[k].length) > 1) return false;
      continue;
    }
    if (editSimilarity(from, to) < minSim) return false;
  }
  return true;
}

export async function correctTranscript(text) {
  const t = (text || "").trim();
  if (t.split(/\s+/).filter(Boolean).length < 4) return t; // too short to be worth a call / risk
  const sys =
`Fix obvious speech-to-text errors in ONE line of a sales-call transcript, using context to pick the
intended word. Keep the wording verbatim otherwise. Do NOT add, remove, summarize, rephrase, or add
punctuation beyond fixing a clear error.
NEVER change a person's name, a company name, or any other proper noun. An unfamiliar-looking name is
almost certainly correct; leave it exactly as written.
Return ONLY the corrected line, no quotes, no preamble.`;
  // The instruction above is not enough on its own: observed in practice, this step rewrote
  // "Alec Williams, Director of Data Engineering" into "I'm Williams, Director of Data Engineering"
  // and lost the first name. So the guard is deterministic. A rewrite that drops a capitalised word
  // the original had is rejected outright, because a cleanup step must never cost us a name.
  const propers = (t.match(/\b[A-Z][a-z]{2,}\b/g) || []).slice(1);   // skip the sentence-initial word
  try {
    const out = (await callQuality(sys, t, 120)).trim().replace(/^["']|["']$/g, "");
    if (!out || out.length < t.length * 0.5 || out.length > t.length * 1.8) return t; // suspicious rewrite
    const lost = propers.filter((w) => !out.includes(w));
    if (lost.length) return t;   // it dropped a proper noun: keep the original, every time
    if (factTokens(out) !== factTokens(t)) return t;        // changed a number, a unit or a timeframe
    if (!substitutionsArePlausible(t, out)) return t;       // rewrote meaning rather than fixing a mishearing
    return out;
  } catch { return t; }
}

export const elementList = (pack) =>
  pack.elements.map((e) => `- ${e.label} (id: ${e.id}) — covered when: ${e.covered_when}`).join("\n");

// --- Question validator (deterministic gate; regenerate on failure) -------------------------
// Grounding a small model needs is built into the OUTPUT (a required `anchor`), then verified
// here — not left as an instruction the model can drop. Techniques folded in from research:
// mirroring (Voss/Gong), one-question-only + how/what openers (Gong), no methodology jargon.
const BLOCKLIST = ["solution", "leverage", "synergy", "framework", "pain point", "pain points",
  "bandwidth", "ecosystem", "utilize", "meddic", "meddpicc", "spin", "bant", "challenger", "synergies",
  "circle back", "deep dive", "unpack", "double-click"];
// "when you say" was whitelisted here while the prompt bans it outright, and "who" was missing while
// the prompt permits it — so the prompt's own GOOD example ("Who owns the budget for that?") was
// rejected, firing the repair branch and costing a second inference call on the live cue path.
const OPENERS = ["what", "how", "how often", "how long", "who", "walk me through", "what happens",
  "it sounds like", "it seems", "does", "is", "have i", "would", "where", "so", "you mentioned", "earlier", "given", "from what"];
// Constructions that quote the customer back before asking. Banned by the prompt; now enforced.
const ECHO_OPEN = /^\s*(?:when you (?:say|said|mention|mentioned)\b|when you\b|since\b|given that\b|now that\b|you mentioned\b)/i;
const norm = (s) => (s || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

// Words a question may introduce on its own. Everything else concrete in the question — numbers,
// units, product and vendor names — has to have come from the customer.
const QUESTION_SAFE = new Set(["what","how","who","when","where","why","which","walk","me","through","it",
  "sounds","seems","happens","does","do","did","is","are","was","were","the","a","an","and","or","but","to",
  "of","in","on","at","for","with","from","your","you","that","this","those","these","there","their","them",
  "they","if","then","would","will","can","could","should","been","be","being","has","have","had","not","no",
  "most","more","less","about","like","look","looks","looking","today","now","currently","much","many","long",
  "often","take","takes","taking","make","makes","get","gets","go","goes","going","happen","happening","team",
  "teams","people","process","time","times","cost","costs","business","impact","side","part","point","thing",
  "things","one","two","first","next","last","same","different","change","changes","changed","work","works",
  "working","use","uses","using","used","need","needs","see","seen","feel","feels","say","says","said","mean",
  "means","tell","us","we","our","i","my","me","s","t","re","ve","ll","d"]);

/// Flags concrete tokens in the question that the customer never said. On ASR-garbled input the model
/// invents specifics with total confidence: "the the seven i mean" became "How is the seven-year
/// retention requirement impacting your storage costs?", 5 times out of 5. A number or a product name
/// the customer did not say is a fabricated fact in the rep's mouth.
// Deliberately narrow. Only nouns that ASSERT a specific event or programme exists. Words like
// budget, project, review and evaluation had to come out: "Who owns the budget for that?" is the
// prompt's own good example and a blanket ban rejected it. Asking about a thing is fine; claiming
// the customer mentioned one is not, and only this class reliably distinguishes the two.
const RISKY_NOUNS = new Set(["audit","audits","breach","breaches","outage","outages","migration",
  "poc","rfp","rfi","mandate","lawsuit","fine","fines","penalty","incident","incidents"]);
function inventedTerms(text, recentNorm) {
  const said = new Set(recentNorm.split(/\s+/).filter(Boolean));
  const out = [];
  for (const raw of (text || "").split(/\s+/)) {
    const w = raw.replace(/[^A-Za-z0-9-]/g, "");
    if (!w) continue;
    const lower = w.toLowerCase();
    if (QUESTION_SAFE.has(lower) || said.has(lower)) continue;
    // A digit the customer never said, or a capitalised word mid-sentence (a product, vendor, person).
    // Only digits. Lowercase invented noun phrases ("legacy agent", "your current goals") are not
    // reliably separable from the ordinary words a question is allowed to introduce, so those are
    // handled in the prompt and by refusing to coach garbled turns, not here.
    if (/\d/.test(w) && !said.has(lower.replace(/[^0-9]/g, ""))) out.push(w);
    // Business objects a question must not conjure. Measured at 12.5% of output: "during an audit",
    // "security requirements", "the migration", none of which the customer had mentioned.
    else if (RISKY_NOUNS.has(lower)) out.push(w);
  }
  return [...new Set(out)];
}

/// Does the anchor correspond to what the customer just said? Exact substring is too brittle for
/// live speech: "lost two analysts last quarter" failed against "did lose two analysts last quarter"
/// on a one-letter inflection, and the rep got no cue on the most valuable turn in the call. Compare
/// content tokens with a crude stem and require most of them to be present.
const STEM = (w) => w.replace(/(?:ing|ed|es|s)$/, "");
const ANCHOR_STOP = new Set(["the","a","an","of","to","in","on","at","for","and","or","is","are","was","were","we","our","i","my","you","your","that","this","it","did","do","does","have","has","had"]);
function anchorMatches(anchor, transcriptNorm) {
  const want = norm(anchor).split(/\s+/).filter((w) => w && !ANCHOR_STOP.has(w));
  if (!want.length) return false;
  const have = new Set(transcriptNorm.split(/\s+/).filter(Boolean).map(STEM));
  const hit = want.filter((w) => have.has(STEM(w))).length;
  return hit / want.length >= 0.7;
}

/// A CLOSE is not a discovery question and must not be judged as one. It is deliberately long, it
/// deliberately plays their words back, and it says "we" because the rep is offering something.
/// Validating it with the discovery rules rejected it every time: measured 0 of 6 survived, so the
/// per-turn coach was structurally incapable of ever closing a call.
function closeIssues(text) {
  const issues = [];
  const t = (text || "").trim();
  if (!t) return ["empty close"];
  if (!/\?/.test(t)) issues.push("a close has to end in an ask");
  const words = t.split(/\s+/).filter(Boolean).length;
  if (words > 70) issues.push(`${words} words (a close should be under 70)`);
  if (words < 12) issues.push(`${words} words — too thin to be a close`);
  // It still must not invent a meeting that was never discussed, or use jargon.
  const banned = BLOCKLIST.find((w) => new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i").test(t));
  if (banned) issues.push(`banned word/jargon "${banned}"`);
  return issues;
}

export function questionIssues(q, questionTranscriptNorm, packName, evidenceNorm = questionTranscriptNorm) {
  const transcriptNorm = questionTranscriptNorm;
  if (q && q.targets === "close") return closeIssues(q.text);
  const issues = [];
  const text = (q.text || "").trim();
  const anchor = (q.anchor || "").trim();
  if (!text) return ["empty question"];
  if (!anchor) issues.push("missing anchor");
  else if (!anchorMatches(anchor, transcriptNorm)) issues.push(`anchor "${anchor}" not said by customer`);
  const qmarks = (text.match(/\?/g) || []).length;
  if (qmarks !== 1) issues.push(`${qmarks} question marks (need exactly 1 — no stacking)`);
  const words = text.split(/\s+/).filter(Boolean).length;
  if (words > 28) issues.push(`${words} words (keep <=28)`);   // the prompt says 18; this said 20
  const banned = [...BLOCKLIST, (packName || "").toLowerCase()].filter(Boolean)
    .find((w) => new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i").test(text));
  if (banned) issues.push(`banned word/jargon "${banned}"`);
  // A short grounded bridge is natural; invented facts and stacked asks still fail.
  if (!OPENERS.some((o) => text.toLowerCase().startsWith(o))) issues.push("use a natural question or brief grounded bridge");
  if (/\band\s+who\b|\band\s+what\b|\band\s+how\b/i.test(text)) issues.push("two asks joined by 'and' — one question only");
  const vague = text.match(/\b(?:this|that)\s+(?:setup|thing|stuff|situation|area|space|initiative|system|project)\b|\bthe current setup\b/i);
  if (vague) issues.push(`vague pointer "${vague[0]}" — name the specific thing they said`);
  const invented = inventedTerms(text, evidenceNorm);
  if (invented.length) issues.push(`invented "${invented.join(", ")}" — the customer never said that`);
  // The rep reads this out loud, so first person plural is the seller's voice leaking into it.
  if (/\b(?:our|we|us)\b/i.test(text)) issues.push("says 'our/we/us' — the REP reads this aloud, use 'your'");
  return issues;
}

function extractJSON(text) {
  if (!text) return null;
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = fence ? fence[1] : text;
  const s = body.indexOf("{"), e = body.lastIndexOf("}");
  if (s < 0 || e < 0) return null;
  try { return JSON.parse(body.slice(s, e + 1)); } catch { return null; }
}

// Schema-constrained decoding guarantees the coaching SHAPE. Built PER PACK so `coverage` REQUIRES a
// done/partial/open verdict for EVERY element every turn — otherwise the model omits coverage (it's
// not "required"), the coach never learns what's covered, and it re-probes the opening topic forever.
function coachSchema(pack) {
  const covProps = {};
  for (const e of pack.elements) covProps[e.id] = { type: "string", enum: ["done", "partial", "open"] };
  return {
    type: "object",
    properties: {
      coverage: { type: "object", properties: covProps, required: pack.elements.map((e) => e.id) },
      next_questions: {
        type: "array",
        items: {
          type: "object",
          properties: { anchor: { type: "string" }, text: { type: "string" }, targets: { type: "string" }, why: { type: "string" } },
          required: ["anchor", "text", "targets"],
        },
      },
    },
    required: ["coverage", "next_questions"],
  };
}

export async function fastTier(pack, transcript, guidance = "", onDelta = null, opts = {}) {
  const latestCustomer=transcript.split("\n").filter(l=>/^\s*(?:cust|customer|\*\*customer)\b/i.test(l)).at(-1)?.replace(/^\s*(?:cust|customer|\*\*customer)(?:\*\*)?\s*:\s*/i,"").trim();
  const acknowledgement=latestCustomer && /^(?:(?:right|yeah|yes|yep|okay|ok|exactly|sure|mhm|mm[ -]?hmm|uh[ -]?huh|got it|understood|thank you|thanks)[\s,.!—-]*)+$/i.test(latestCustomer);
  // An explicit demo checkpoint may return to earlier evidence; ordinary acknowledgements cannot.
  if((latestCustomer && !completedThought(latestCustomer)) || (acknowledgement && !(Number(opts.anchorWindow)>1 && /mid.demo|checkpoint|closing phase/i.test(guidance)))) {
    const empty=JSON.stringify({coverage:{},next_questions:[]}); onDelta?.(empty); return empty;
  }
  let system =
`You are a top-performing sales engineer on a LIVE discovery call, coaching in real time. You are
privately tracking the ${pack.name} goals below, but you NEVER say the framework's name or its
element names out loud — you just ask great, human questions.

Your job: read the customer's LATEST turn and propose ONE short, natural follow-up that mirrors
their own words and makes them say more. The "text" you write is the EXACT sentence the rep will
say OUT LOUD — it must sound like a calm, confident professional, natural enough to read verbatim.
Never clever, cute, or corny.

Work like an experienced SE: understand their current workflow, find the specific breakdown,
explore its consequence, quantify it when appropriate, then establish what a better outcome would
look like. These are conversational moves, not a checklist. Choose the ONE move that advances
their current thread. A question already asked by the rep needs an answer, not another question.
If the customer asks a technical question, let the rep answer it before probing for more pain.
During a demonstration, compare the capability just shown with their actual workflow.
Use the customer's nouns. Avoid leading them toward Splunk, inventing urgency, or presuming a
problem they have not confirmed. A concrete process question beats a generic cost question.
Examples of the moves, never canned scripts:
  Current workflow: "Walk me through how your analysts investigate a failed login."
  Breakdown: "Where does the investigation slow down?"
  Consequence: "What happens to the incident while they wait?"
  Measure: "How long does that investigation take today?"
  Desired outcome: "What would your team need to do differently?"
Deepen the same issue across technical, business and personal impact when the answer earns it.
Technical: what happens today and where the workflow breaks.
Business: what that means for the outcome, delay, risk or capacity they care about.
Personal: what it takes from this person's or their team's responsibilities, without assuming emotions.
Do not ask all three at once or force a prescribed sequence. Confirm an unclear answer rather than
pivot. A technical detail is not automatically a pain. Ask how it works before asking what it costs.
Use the full-call captured evidence for known facts, quantities and already answered questions.
After showing a capability, invite a comparison with their existing process instead of another
qualification question: "How does this compare with how your team investigates those alerts today?"
Use that form only when the demonstration and earlier workflow are actually in the transcript.

Only mark coverage from customer statements about their own situation. Rep questions, product
claims, demo narration and hypothetical examples are NOT evidence. People on the far-end channel
can be sellers too. Treat screen-driving and product explanation as seller context, not customer
requirements. Uncertain evidence stays open or partial, never done.


HARD RULES — a valid question obeys ALL of these:
1. ANCHOR ON WHAT THE CONVERSATION IS ABOUT. The "anchor" must name something concrete from the
   customer's world: a problem, a number, a process, a deadline, a team, or a system ("the tier one
   analysts", "four terabytes a day", "the January audit", "six hundred aged out"). It is NOT any
   random run of words. Pleasantries, fillers, meeting talk and fragments are NEVER anchors.
   ANCHOR ON THE SUBJECT, NOT THE NEAREST PRODUCT NAME. A vendor or tool named in passing while they
   explain something else is context, not the topic — grabbing it is the classic tell that you were
   pattern-matching rather than listening.
   Example. Thread: alerts pile up, three analysts, six hundred closed last quarter unreviewed.
   Latest turn: "it is. and we pull all of that through Fortinet on the way in, but the volume is
   the problem."
   BAD:  "How is your current Fortinet configuration contributing to the volume?"  (chased the brand)
   GOOD: "What does it cost you when six hundred alerts age out unreviewed?"        (stayed on thread)
2. IF THERE IS NOTHING WORTH ASKING ABOUT, ASK NOTHING. When the customer's latest turn contains no
   concrete thing about their environment or business — they said "sorry for interrupting", "this is
   the score", "yeah exactly", or they are narrating the meeting itself — return
   "next_questions": []. An empty list is a CORRECT answer and is far better than a manufactured
   question. Do not stretch to fill the slot.
3. A brief bridge or confirmation is useful when it connects to what they said. Do not mechanically
   echo their last words before every question. Use their language without a long recap or scripted
   transition. A concise "So..." or "Earlier you mentioned..." can reconnect an earlier fact to the
   current thread. Every factual detail must come from this call. Avoid leading them to agree.
4. ONE question only — exactly one "?". No "and", no stacked or two-part questions. In particular
   NEVER bolt a second clause on to reach a goal ("...what does that look like, and who approves
   the budget?"). That is two questions and it reads as an interrogation.
5. Usually 10-22 words, up to 28 when a useful comparison needs context. Start naturally with What, How, Who, Where, Walk me through, Does, Is, Would, or Have I. A confirming question is welcome when you need to check understanding.
6. Plain English. BANNED: solution, leverage, synergy, framework, pain point, bandwidth, ecosystem,
   utilize, and the name of any sales methodology. Never use an acronym the customer didn't say.
   Flip pronouns when you refer to their things: their "my team" is "your team".
7. Prefer How/What over Why. For a process, use "Walk me through...". If they sound frustrated,
   LABEL it first ("It sounds like...") — never "I think you...". For impact, build on the SPECIFIC
   pain they named, not a generic "what's the cost of X".
8. NO wordplay. Do not extend, pun on, or riff on the customer's metaphor. Refer to their SPECIFIC
   thing by name (the legacy SIEM, the audit findings, the Q1 deadline) — never vague pointers like
   "this setup", "that thing", or "this".
9. NEVER RESOLVE GARBLED SPEECH INTO A FACT. This runs on live speech-to-text, so the latest turn is
   often broken mid-thought, stuttered, or mis-transcribed. If you are not certain what they said, do
   NOT pick the most plausible specific and ask about it as though they had said it.
   BAD:  heard "the retention is uh is it's like the the seven i mean"
         -> "How is the seven-year retention requirement impacting your storage costs?"
         (a seven-year policy was invented out of a fragment)
   BAD:  heard "about four thousand endpoints i think"
         -> "How many of those endpoints run on your legacy agent?"  (no agent was mentioned)
   GOOD: return [] and wait for them to finish, or ask them to say the number again.
   Never introduce a product, vendor, timeframe, policy, team, or project the customer has not named.
10. STAY ON THE THREAD. The question has to make sense as the next thing said in THIS conversation,
    not just as a reaction to the last sentence. Read the recent exchanges, not only the final turn.
    - If the customer has been on one subject for several turns, go deeper on it rather than lurching
      to something they mentioned in passing.
    - A passing mention is not an invitation. If they name a tool while explaining something else,
      the tool is context, not the topic.
    - Never ask something already answered earlier in the call, in any wording.
    - Ask yourself: would a person who had been listening for the last five minutes ask this now? If
      not, pick a different question — one that continues the thread. Sounding like you were not
      listening costs more than saying nothing.
    SILENCE IS FOR EMPTY TURNS, NOT FOR OFF-GOAL TURNS. Return [] only when the latest turn contains
    nothing to ask about at all (an acknowledgement, a pleasantry, meeting talk, broken audio). If
    they said something real and it simply is not about the goal you are tracking, ASK ABOUT WHAT
    THEY SAID. Going quiet on a substantive turn is a miss, not restraint.
11. A goal you are tracking is a direction, not a script. If the customer has not given you anything
   that makes the goal askable yet, return [] and wait. Asking the same goal repeatedly in different
   words is the single worst thing you can do — it is obvious, it annoys the customer, and it
   teaches them you are not listening.

CLOSING PHASE OVERRIDE. If the guidance below says CLOSING PHASE, rules 4 and 5 DO NOT APPLY and
you must NOT return a discovery question. A close is a short statement that ends in an ask, roughly
30 to 60 words, three beats in order:
  (1) play back the two or three problems they actually stated, in their own words;
  (2) connect the next step to the outcome they actually asked for;
  (3) ask for one realistic next step, without inventing a meeting, deadline or commitment.
It is allowed to be long, to repeat their words back, and to say "we" — that is what a close is.
Set "targets":"close".
EXAMPLE of a correct close:
  "You're losing a week a quarter to manual pruning, and you've got the April audit to satisfy. In a
   demo you'd see exactly how those retention rules get automated, and what that gives your engineers
   back. Does Tuesday work?"
Returning another discovery question during CLOSING PHASE is a failure.

Goals you are privately tracking (internal only — do not name these):
${elementList(pack)}
${guidance ? `\nCONVERSATION GUIDANCE:\n${guidance}\n` : ""}
Return ONLY JSON:
{ "next_questions": [ { "anchor": "<customer's exact words>", "text": "<one question, <=28 words>", "targets": "<element_id>", "why": "<=4 words" } ],
  "coverage": { "<element_id>": "done|partial|open" } }
Emit "next_questions" FIRST, before "coverage": the question is shown to the rep as it is generated.
Exactly one next_question at most, advancing the customer's current thread.

EXAMPLES (bad -> good) — the GOOD "text" is exactly what the rep says out loud. These use an
UNRELATED deal on purpose; never copy their wording, generate fresh from THIS customer's words:
Customer: "our data pipeline breaks every couple weeks and nobody really owns it."
BAD: {"text":"What pain points are you seeing in your data ecosystem?"}   (jargon, ignores their words)
GOOD: {"anchor":"data pipeline breaks every couple weeks","text":"What breaks downstream when the data pipeline goes down?","targets":"identify_pain","why":"open the pain"}

Customer: "onboarding a new rep takes us almost three months right now."
BAD: {"text":"How does onboarding affect ramp time and quota and morale?"}   (stacked, three asks)
BAD: {"text":"Three months — are your new reps stuck in the slow lane?"}   (corny — cutesy metaphor)
GOOD: {"anchor":"almost three months","text":"What's making onboarding take almost three months?","targets":"metrics","why":"quantify pain"}

Customer: "finance has to sign off, and they've pushed the timeline twice already."
BAD: {"text":"Who is the economic buyer for this deal?"}   (robotic, names the framework role)
GOOD: {"anchor":"pushed the timeline twice","text":"What's behind finance pushing the timeline twice?","targets":"economic_buyer","why":"find the buyer"}`;

  // Anchors must quote the CUSTOMER's own words — validate against customer lines only, not the rep's.
  const custAll = transcript.split("\n").filter((l) => /^\s*(cust|customer|\*\*customer)/i.test(l));
  // The anchor must come from the turn they JUST said. Validating against the whole call, or even
  // the last two turns, let the model mine a phrase from earlier: a contentless turn ("right",
  // "sorry for interrupting") still produced a confident question about a number mentioned two turns
  // back, 39 times out of 39. Scoping to the latest turn is also the direct fix for the original
  // complaint that the questions did not follow the conversation.
  // Normally the anchor must come from the customer's LATEST turn, which is what stopped the coach
  // inventing questions out of anything ever said. Mid-demo that turn is "okay" or "mm-hmm", so a
  // checkpoint referring back to the need they stated before the demo began had nothing to match
  // and every question was thrown away. Widen the window only for that case.
  const anchorWindow = Math.max(1, opts.anchorWindow || 1);
  const tnorm = norm(custAll.slice(-anchorWindow).join("\n") || transcript);
  const evidenceNorm = norm(opts.evidenceTranscript || custAll.join("\n") || transcript);
  system += "\nFor personal impact, do not assume which work they wish to return to. Unless they named that activity, ask what the delay or extra work takes them away from.";
  const schema = coachSchema(pack);
  let raw = await callCoach(system, `Transcript so far:\n\n${transcript}`, 400, schema, onDelta, opts);
  let obj = extractJSON(raw);
  // Always hand back VALID JSON. Returning raw model text here made the contract inconsistent (callers
  // had to parse leniently or crash); salvage the coverage we did get and drop the unusable questions.
  if (!obj || !Array.isArray(obj.next_questions)) {
    return JSON.stringify({ coverage: obj?.coverage || {}, next_questions: [] }, null, 2);
  }

  const bad = obj.next_questions.map((q) => ({ q, issues: questionIssues(q, tnorm, pack.name, evidenceNorm) })).filter((x) => x.issues.length);
  if (bad.length) {
    const fix =
`Your previous questions broke the rules:
${bad.map((b) => `- "${b.q.text || ""}" -> ${b.issues.join("; ")}`).join("\n")}
Regenerate the JSON. Fix EVERY issue. Keep only questions that quote the customer's exact words
(anchor), ask exactly one thing in <=28 words, and use no banned jargon.`;
    const raw2 = await callCoach(system, `Transcript so far:\n\n${transcript}\n\n${fix}`, 400, schema, null, opts);
    const obj2 = extractJSON(raw2);
    if (obj2 && Array.isArray(obj2.next_questions)) obj = obj2;
  }
  // Before discarding, try to repair deterministically. Measured, the filter was turning mechanical
  // faults into silence on substantive turns: one question died solely for the word "us", another
  // for a verb tense. Pronoun swap and an over-length trim are free and lossless; only go quiet if
  // the question still fails afterwards.
  obj.next_questions = (obj.next_questions || []).map((q) => {
    if (!q?.text || !questionIssues(q, tnorm, pack.name, evidenceNorm).length) return q;
    let t = q.text
      .replace(/\b(our|Our)\b/g, (m) => (m[0] === "O" ? "Your" : "your"))
      .replace(/\bwe\b/gi, "you").replace(/\bus\b/gi, "you").replace(/\bours\b/gi, "yours");
    const words = t.split(/\s+/).filter(Boolean);
    const repaired = { ...q, text: t };
    return questionIssues(repaired, tnorm, pack.name, evidenceNorm).length < questionIssues(q, tnorm, pack.name, evidenceNorm).length ? repaired : q;
  });

  // Final guard. Previously this dropped ONLY anchor problems, so an echo-back opener, a stacked
  // question, an over-length one, or "our/we/us" in the rep's own line all shipped after one failed
  // repair. Everything the validator flags is now disqualifying: showing no cue is an acceptable
  // outcome, showing a bad one is not.
  obj.next_questions = obj.next_questions.filter((q) => questionIssues(q, tnorm, pack.name, evidenceNorm).length === 0);
  return JSON.stringify(obj, null, 2);
}

const LENSES = [
  { id: "coverage", brief: "Find the single biggest framework gap and the one question to close it." },
  { id: "deepen-pain", brief: "Dig into the pain the customer just surfaced; make the implication concrete/quantified." },
  { id: "advance-deal", brief: "Move the deal: champion, economic buyer, decision process, or the next step." },
  { id: "risk", brief: "Surface the unspoken objection, competitor, or do-nothing risk lurking right now." },
];

export async function strategyPanel(pack, transcript) {
  const proposals = await Promise.all(LENSES.map(async (lens) => {
    let system =
`You are the "${lens.id}" lens on a sales-call strategy panel (${pack.name}). Your job: ${lens.brief}
Propose ONE next move grounded in the customer's own words. Return JSON:
{ "lens": "${lens.id}", "move": "...", "why": "one sentence" }`;
    return { lens: lens.id, raw: await callLLM(M.worker, system, `Full transcript:\n\n${transcript}`, 400) };
  }));
  const judgeSystem =
`You are the judge of a ${pack.name} strategy panel. Pick the best 1-2 moves for RIGHT NOW,
ranked by value x naturalness x timing; rewrite in the customer's words if needed. Return JSON:
{ "pick": [ { "text": "...", "targets": "<element_id>", "why_now": "one sentence" } ], "runner_up": "one line" }`;
  const panelText = proposals.map((p) => `[${p.lens}] ${p.raw}`).join("\n\n");
  const judged = await callLLM(M.judge, judgeSystem, `Framework elements:\n${elementList(pack)}\n\nPanel proposals:\n${panelText}`, 600);
  return { proposals, judged };
}

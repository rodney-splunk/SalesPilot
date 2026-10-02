// Speaker diarization bridge. Owns a resident python sidecar that turns a turn's audio into a
// voice-cluster id, so "who spoke" can come from the VOICE rather than from which channel the audio
// happened to arrive on. That distinction matters: on a speakerphone both channels carry both
// people, and channel-based attribution is then simply wrong.
//
// Everything here is best-effort by design. If python, the model, or the sidecar is missing, every
// call resolves to null and the caller keeps its channel-based labels. Diarization is an upgrade to
// attribution, never a dependency of it.
import { spawn } from "child_process";
import { existsSync, unlinkSync } from "fs";
import { createInterface } from "readline";

const HERE = new URL(".", import.meta.url).pathname;
const DIR = `${HERE}../diarize`;
const PY = `${DIR}/.venv/bin/python`;
const SCRIPT = `${DIR}/embed.py`;
const MODEL = `${DIR}/speaker.onnx`;
const REQUEST_TIMEOUT_MS = 8000;

let proc = null, pending = new Map(), seq = 0, started = false, dead = false;

function start() {
  if (started) return;
  started = true;
  if (!existsSync(PY) || !existsSync(SCRIPT) || !existsSync(MODEL)) {
    dead = true;
    console.error("[diarize] not installed — speaker labels stay channel-based");
    return;
  }
  try {
    proc = spawn(PY, [SCRIPT], { cwd: DIR, stdio: ["pipe", "pipe", "pipe"] });
  } catch (e) {
    dead = true; console.error(`[diarize] spawn failed: ${e.message}`); return;
  }
  proc.stderr.on("data", (d) => console.error(`[diarize] ${String(d).trim()}`));
  createInterface({ input: proc.stdout }).on("line", (line) => {
    let r; try { r = JSON.parse(line); } catch { return; }
    const p = pending.get(r?.id);
    if (!p) return;                       // late answer for a turn we already gave up on
    pending.delete(r.id);
    clearTimeout(p.timer);
    p.resolve(r);
  });
  // A dead sidecar must fail every in-flight request rather than leave them hanging forever.
  const die = (why) => {
    dead = true; proc = null;
    console.error(`[diarize] sidecar ${why} — falling back to channel labels`);
    for (const [, p] of pending) { clearTimeout(p.timer); p.resolve({ cluster: null, reason: why }); }
    pending.clear();
  };
  proc.on("exit", (code) => die(`exited (${code})`));
  proc.on("error", (e) => die(e.message));
  // The sidecar is a GRANDCHILD of the app. If this engine goes away without closing the pipe
  // cleanly, python can sit blocked on a read forever; a call a day would leave a trail of them.
  const cleanup = () => { try { proc?.kill("SIGKILL"); } catch {} for(const [,p] of pending){clearTimeout(p.timer);p.resolve({cluster:null,reason:"terminated"});} pending.clear(); };
  process.once("exit", cleanup);
  // Installing a signal listener suppresses Node's default termination. Explicitly exit after
  // stopping the sidecar, otherwise closing the app leaves an engine waiting on stdin forever.
  for (const [sig, code] of [["SIGINT",130],["SIGTERM",143],["SIGHUP",129]]) {
    process.once(sig, () => { cleanup(); process.exit(code); });
  }
}

/// Classify one turn's audio. Always resolves — never rejects, never blocks the live path.
/// The wav is consumed: it is deleted once we are done with it, whatever the outcome.
export function classify(wavPath) {
  start();
  const cleanup = () => { try { if (wavPath && existsSync(wavPath)) unlinkSync(wavPath); } catch {} };
  if (dead || !proc || !wavPath) { cleanup(); return Promise.resolve({ cluster: null, reason: "off" }); }
  const id = `t${++seq}`;
  return new Promise((resolve) => {
    const done = (r) => { cleanup(); resolve(r); };
    const timer = setTimeout(() => {
      pending.delete(id);
      done({ cluster: null, reason: "timeout" });   // a slow embed must not stall coaching
    }, REQUEST_TIMEOUT_MS);
    pending.set(id, { resolve: done, timer });
    try {
      proc.stdin.write(JSON.stringify({ id, wav: wavPath }) + "\n");
    } catch (e) {
      pending.delete(id); clearTimeout(timer); done({ cluster: null, reason: "write_failed" });
    }
  });
}

export function available() { start(); return !dead; }

export function shutdown() {
  if (proc) { try { proc.stdin.end(); proc.kill(); } catch {} }
  proc = null; dead = true;
}

// Speaker diarization tests — run: `node test-diarize.mjs` from engine/.
// Uses macOS `say` to synthesise two distinct voices, so the whole path is exercised for real:
// audio -> embedding -> online clustering -> cluster named by whoever introduced themselves.
// Skips (does not fail) when the TTS voices or the model are unavailable.
import { spawn, execSync } from "child_process";
import { readFileSync, existsSync, copyFileSync, mkdirSync } from "fs";
import { tmpdir } from "os";

import os from "node:os";
import { rmSync } from "node:fs";
// Hermetic: never let a prep the user has active change what these tests see.
process.env.PREP_FILE = process.env.PREP_FILE || `${os.tmpdir()}/salespilot-test-prep.txt`;
rmSync(process.env.PREP_FILE, { force: true });   // start every run with no prep

const HERE = new URL(".", import.meta.url).pathname;
const DZ = `${tmpdir()}/salespilot-dz`;
let pass = 0, fail = 0;

function tts(voice, tag, text) {
  const aiff = `${DZ}/${tag}.aiff`, wav = `${DZ}/${tag}.wav`;
  if (existsSync(wav)) return wav;
  execSync(`say -v ${voice} -o "${aiff}" ${JSON.stringify(text)}`, { stdio: "ignore" });
  execSync(`afconvert -f WAVE -d LEI16@16000 -c 1 "${aiff}" "${wav}"`, { stdio: "ignore" });
  return wav;
}

function run(seq, ms = 15000) {
  return new Promise((resolve) => {
    const f = `${tmpdir()}/dz-${process.pid}-${Math.random().toString(36).slice(2)}.json`;
    const p = spawn("node", ["serve.mjs", "--framework", "meddic"], { cwd: HERE, env: { ...process.env, SESSION_FILE: f } });
    p.stderr.on("data", () => {});
    (async () => {
      await new Promise((r) => setTimeout(r, 1200));
      for (const t of seq) {
        const seg = t.cmd ? { ...t } : { speaker: t.spk, text: t.text };
        if (t.wav) { const d = `${tmpdir()}/dzw-${process.pid}-${Math.random().toString(36).slice(2)}.wav`; copyFileSync(t.wav, d); seg.wav = d; }
        p.stdin.write(JSON.stringify(seg) + "\n");
        await new Promise((r) => setTimeout(r, 2200));
      }
      setTimeout(() => {
        let s = {}; try { s = JSON.parse(readFileSync(f, "utf8")); } catch {}
        p.stdin.end();
        const turns = s.turns || [];
        turns.audioWarning = s.audioWarning || null;      // carried alongside, so callers can assert it
        resolve(turns);
      }, ms);
    })();
  });
}

mkdirSync(DZ, { recursive: true });
let voices = "";
try { voices = execSync("say -v '?'", { encoding: "utf8" }); } catch {}
const haveVoices = ["Daniel", "Albert", "Fred"].every((v) => voices.includes(v));
const haveModel = existsSync(`${HERE}../diarize/speaker.onnx`) && existsSync(`${HERE}../diarize/.venv/bin/python`);

if (!haveVoices || !haveModel) {
  console.log(`SKIP diarization tests (voices:${haveVoices} model:${haveModel})`);
  process.exit(0);
}

const A1 = tts("Daniel", "a1", "Sorry, I should introduce myself. Alec Williams, Director of Data Engineering.");
const B1 = tts("Albert", "b1", "And I am Priya Raman, I look after security for the whole group here.");
const A2 = tts("Daniel", "a2", "We ingest about four terabytes a day from roughly forty different sources.");
const B2 = tts("Albert", "b2", "The compliance team flags the violations and then the engineers clean them up by hand.");
const R1 = tts("Fred",   "r1", "Thanks for making the time today, I want to understand what is happening on your side.");

console.log("— speaker diarization —");
{
  // The headline case: two people on the customer side, each named from their OWN introduction,
  // and still correctly attributed on later turns where no name is spoken.
  const t = await run([
    { spk: "you",      wav: R1, text: "Thanks for making the time today, I want to understand what is happening on your side." },
    { spk: "customer", wav: A1, text: "Sorry, I should introduce myself. Alec Williams, Director of Data Engineering." },
    { spk: "customer", wav: B1, text: "And I am Priya Raman, I look after security for the whole group here." },
    { spk: "customer", wav: A2, text: "We ingest about four terabytes a day from roughly forty different sources." },
    { spk: "customer", wav: B2, text: "The compliance team flags the violations and then the engineers clean them up by hand." },
  ]);
  const who = t.filter((x) => !x.me).map((x) => x.who);
  const ok = who.length === 4 && who[0] === "Alec Williams" && who[1] === "Priya Raman"
          && who[2] === "Alec Williams" && who[3] === "Priya Raman";
  console.log(`${ok ? "PASS" : "FAIL"}  two customer voices are told apart and named   (${who.join(" | ")})`);
  ok ? pass++ : fail++;
}
{
  // No audio at all: diarization simply never fires and channel labels stand. A call must not
  // depend on the sidecar being installed.
  const t = await run([
    { spk: "customer", text: "Hi, I'm Alec Williams and I run the data platform team here." },
    { spk: "customer", text: "We are seeing real problems with how PII lands in the index." },
  ], 9000);
  const who = t.filter((x) => !x.me).map((x) => x.who);
  const ok = who.length === 2 && who[0] === "Alec Williams" && who[1] === "Call audio";
  console.log(`${ok ? "PASS" : "FAIL"}  no audio -> falls back to channel labels, no crash   (${who.join(" | ")})`);
  ok ? pass++ : fail++;
}
{
  // A turn too short to embed must not invent a speaker, and must not break the turns around it.
  const short = tts("Daniel", "short", "Yeah");
  const t = await run([
    { spk: "customer", wav: A1, text: "Sorry, I should introduce myself. Alec Williams, Director of Data Engineering." },
    { spk: "customer", wav: short, text: "Yeah exactly that is right." },
    { spk: "customer", wav: A2, text: "We ingest about four terabytes a day from roughly forty different sources." },
  ]);
  const who = t.filter((x) => !x.me).map((x) => x.who);
  const ok = who.length === 3 && who[0] === "Alec Williams" && who[2] === "Alec Williams";
  console.log(`${ok ? "PASS" : "FAIL"}  un-embeddable short turn does not derail the ones around it   (${who.join(" | ")})`);
  ok ? pass++ : fail++;
}

{
  // Only ONE of two voices introduces itself. The other must NOT inherit that name — it is a
  // different person, and a confidently wrong name is worse than an honest generic one.
  const t = await run([
    { spk: "customer", wav: A1, text: "Sorry, I should introduce myself. Alec Williams, Director of Data Engineering." },
    { spk: "customer", wav: B2, text: "The compliance team flags the violations and then the engineers clean them up by hand." },
    { spk: "customer", wav: A2, text: "We ingest about four terabytes a day from roughly forty different sources." },
  ]);
  const who = t.filter((x) => !x.me).map((x) => x.who);
  const ok = who[0] === "Alec Williams" && who[2] === "Alec Williams" && who[1] !== "Alec Williams";
  console.log(`${ok ? "PASS" : "FAIL"}  an unnamed second voice does not inherit the named one   (${who.join(" | ")})`);
  ok ? pass++ : fail++;
}

{
  // The real-call failure this was built for: ONE person speaking, but their voice reaches the mic
  // via the room as well as the system tap. The texts differ (each channel caught different parts),
  // so text de-dup cannot see it. The same voice on both channels can, and after only two turns.
  const t = await run([
    { spk: "customer", wav: A1, text: "What kind of infrastructure or insight do they need from us today?" },
    { spk: "you",      wav: A2, text: "DataDog is going to look on paper like it is the lowest price." },
  ], 12000);
  const warned = /speakerphone/i.test(t.audioWarning || "");
  console.log(`${warned ? "PASS" : "FAIL"}  one voice on BOTH channels is flagged after two turns   (${t.audioWarning ? "warned" : "no warning"})`);
  warned ? pass++ : fail++;
}

{
  const turns = await run([
    { spk: "customer", wav: A2, text: "We ingest about four terabytes a day from roughly forty different sources." },
    { spk: "customer", wav: B2, text: "The compliance team flags violations and engineers clean them up by hand." },
  ], 9000);
  const clusters = new Set(turns.map(t => t.clusterId).filter(c => c !== null && c !== undefined));
  const ok = turns.length === 2 && clusters.size === 2 && turns.every(t => /^Speaker \d+$/.test(t.who));
  console.log(`${ok ? "PASS" : "FAIL"} unnamed voices remain distinct and persist cluster evidence (${turns.map(t => t.who).join(" | ")})`);
  ok ? pass++ : fail++;
}
{
  const turns = await run([
    { spk: "customer", wav: A2, text: "We ingest about four terabytes a day from roughly forty different sources." },
    { spk: "customer", wav: B2, text: "The compliance team flags violations and engineers clean them up by hand." },
    { cmd: "speaker", clusterId: 0, side: "seller" },
  ], 9000);
  const ok = turns.length === 2 && turns[0].side === "seller" && turns[1].side !== "seller";
  console.log(`${ok ? "PASS" : "FAIL"} marking a colleague updates earlier turns without changing the other voice`);
  ok ? pass++ : fail++;
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);

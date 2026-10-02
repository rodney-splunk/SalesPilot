// Merge a platform transcript's speaker labels into a SalesPilot session.
//
//   node webex-merge.mjs <session.json> <transcript.vtt> [--write] [--me "Rodney White"]
//
// Webex, Zoom and Teams all diarize a recorded meeting for you, and their labels are ground truth in
// a way ours can never be: they come from per-participant audio streams, not from guessing. When a
// call was recorded, this is strictly better than our own diarization, so it wins where it matches.
//
// The two transcripts are DIFFERENT ASR runs over the same audio, so nothing lines up exactly. Turns
// are matched on word containment and only relabelled above a confidence floor; anything ambiguous
// keeps the label it already had. Being unsure is a valid answer here — a wrong name is worse than
// a generic one.
import { readFileSync, writeFileSync } from "fs";

const MATCH_FLOOR = 0.45;   // below this the two texts are not the same utterance
const AMBIGUOUS   = 0.08;   // best and runner-up this close, from different speakers -> don't guess

const words = (t) => (t || "").toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter(Boolean);
function containment(a, b) {
  const A = new Set(words(a)), B = new Set(words(b));
  if (!A.size || !B.size) return 0;
  let n = 0; for (const w of A) if (B.has(w)) n++;
  return n / Math.min(A.size, B.size);
}

/// Parse WebVTT with <v Speaker> voice tags (Webex, Teams) or "Speaker: text" lines (Zoom).
export function parseTranscript(text) {
  const out = [];
  for (const block of text.replace(/\r/g, "").split(/\n\n+/)) {
    const body = block.split("\n").filter((l) => !/^WEBVTT/.test(l) && !/^\d+$/.test(l) && !/-->/.test(l));
    if (!body.length) continue;
    const joined = body.join(" ").trim();
    if (!joined) continue;
    const v = joined.match(/^<v\s+([^>]+)>([\s\S]*?)(?:<\/v>)?$/);
    if (v) { out.push({ speaker: v[1].trim(), text: v[2].trim() }); continue; }
    const z = joined.match(/^([A-Z][A-Za-z.'-]*(?:\s+[A-Z][A-Za-z.'-]*){0,3}):\s+(.*)$/);
    if (z) { out.push({ speaker: z[1].trim(), text: z[2].trim() }); continue; }
    if (out.length) out[out.length - 1].text += " " + joined;   // continuation of the previous cue
  }
  return out.filter((s) => s.text);
}

/// Returns { turns, stats }. Never mutates the input.
export function mergeLabels(session, snippets, mePerson) {
  const stats = { matched: 0, ambiguous: 0, unmatched: 0, speakers: new Set() };
  const turns = (session.turns || []).map((t) => {
    let best = { s: 0, sp: null }, second = { s: 0, sp: null };
    for (const sn of snippets) {
      const s = containment(t.text, sn.text);
      if (s > best.s) { second = best; best = { s, sp: sn.speaker }; }
      else if (s > second.s) second = { s, sp: sn.speaker };
    }
    if (best.s < MATCH_FLOOR) { stats.unmatched++; return t; }
    // Two different people said something this similar: that is a coin flip, so decline it.
    if (second.sp && second.sp !== best.sp && best.s - second.s < AMBIGUOUS) { stats.ambiguous++; return t; }
    stats.matched++; stats.speakers.add(best.sp);
    const isMe = mePerson && best.sp.toLowerCase() === mePerson.toLowerCase();
    return { ...t, who: isMe ? "You" : best.sp, me: isMe ? true : false, labelSource: "platform" };
  });
  stats.speakers = [...stats.speakers];
  return { turns, stats };
}

// Only act as a CLI when run directly. Imported (test-webex.mjs does), reading the HOST program's
// argv as file paths would at best crash it and at worst overwrite a session file it named.
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
const isMainModule = (() => {
  try { return realpathSync(process.argv[1] || "") === realpathSync(fileURLToPath(import.meta.url)); }
  catch { return false; }
})();

const [, , sessionPath, vttPath, ...rest] = isMainModule ? process.argv : [];
if (sessionPath && vttPath) {
  const write = rest.includes("--write");
  const mi = rest.indexOf("--me");
  const mePerson = mi >= 0 ? rest[mi + 1] : null;
  const session = JSON.parse(readFileSync(sessionPath, "utf8"));
  const snippets = parseTranscript(readFileSync(vttPath, "utf8"));
  const { turns, stats } = mergeLabels(session, snippets, mePerson);
  console.log(`transcript cues : ${snippets.length}`);
  console.log(`session turns   : ${(session.turns || []).length}`);
  console.log(`relabelled      : ${stats.matched}   ambiguous: ${stats.ambiguous}   unmatched: ${stats.unmatched}`);
  console.log(`speakers found  : ${stats.speakers.join(", ") || "(none)"}`);
  if (write) {
    writeFileSync(sessionPath, JSON.stringify({ ...session, turns, labelSource: "platform" }, null, 2));
    console.log(`\nwrote ${sessionPath}`);
  } else {
    console.log("\n(dry run — pass --write to apply)");
    for (const t of turns.slice(0, 12)) console.log(`  ${String(t.who).padEnd(16)} | ${t.text.slice(0, 58)}`);
  }
}

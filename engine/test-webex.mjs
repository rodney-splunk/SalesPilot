// Platform-transcript merge tests — run: `node test-webex.mjs` from engine/.
// The two transcripts are different ASR runs over the same audio, so these deliberately use
// DIFFERENT wording on both sides: matching has to survive that or it is useless in practice.
import { parseTranscript, mergeLabels } from "./webex-merge.mjs";

import os from "node:os";
import { rmSync } from "node:fs";
// Hermetic: never let a prep the user has active change what these tests see.
process.env.PREP_FILE = process.env.PREP_FILE || `${os.tmpdir()}/salespilot-test-prep.txt`;
rmSync(process.env.PREP_FILE, { force: true });   // start every run with no prep
let pass = 0, fail = 0;
const ok = (label, cond, detail = "") => {
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}${detail ? `   (${detail})` : ""}`);
  cond ? pass++ : fail++;
};

console.log("— transcript parsing —");
{
  const vtt = `WEBVTT

1
00:00:03.000 --> 00:00:07.000
<v Rodney White>Thanks for making the time today.</v>

2
00:00:08.000 --> 00:00:15.000
<v Alec Williams>Sure, Alec Williams, Director of Data Engineering.</v>`;
  const s = parseTranscript(vtt);
  ok("Webex <v Speaker> voice tags", s.length === 2 && s[0].speaker === "Rodney White" && s[1].speaker === "Alec Williams",
     s.map((x) => x.speaker).join(" | "));
}
{
  const zoom = `Rodney White: Thanks for making the time today.

Alec Williams: Sure, I run the data platform team.`;
  const s = parseTranscript(zoom);
  ok('Zoom "Name: text" lines', s.length === 2 && s[1].speaker === "Alec Williams", s.map((x) => x.speaker).join(" | "));
}

console.log("\n— label merging —");
{
  // Same utterances, different ASR wording on each side, which is the realistic case.
  const session = { turns: [
    { me: true,  who: "You",      text: "Thanks for making the time today, I wanted to understand what's happening on your side" },
    { me: false, who: "Customer", text: "Sure Alec Williams director of data engineering" },
    { me: false, who: "Customer", text: "And I'm Priya Raman I look after security for the group" },
  ] };
  const snippets = parseTranscript(`WEBVTT

1
00:00:01.000 --> 00:00:06.000
<v Rodney White>Thanks for making the time today. I want to understand what is happening on your side.</v>

2
00:00:07.000 --> 00:00:12.000
<v Alec Williams>Sure. Alec Williams, Director of Data Engineering.</v>

3
00:00:13.000 --> 00:00:18.000
<v Priya Raman>And I am Priya Raman, I look after security for the group.</v>`);
  const { turns, stats } = mergeLabels(session, snippets, "Rodney White");
  ok("relabels across differing ASR wording",
     turns[0].who === "You" && turns[0].me === true && turns[1].who === "Alec Williams" && turns[2].who === "Priya Raman",
     turns.map((t) => t.who).join(" | "));
  ok('--me maps the rep to "You"', turns[0].me === true && turns[0].who === "You");
  ok("counts what it did", stats.matched === 3 && stats.unmatched === 0, `matched=${stats.matched}`);
}
{
  // The speakerphone failure mode, but from the platform's side: our channel guess said the REP
  // spoke the customer's words. Platform labels are per-participant audio, so they overrule us.
  const session = { turns: [
    { me: true, who: "You", text: "But it's not connected. We're having trouble connecting some of our custom data sources to it." },
  ] };
  const snippets = parseTranscript(`WEBVTT

1
00:00:01.000 --> 00:00:08.000
<v Alec Williams>But it's not connected, we're having trouble connecting some of our more custom data sources to it.</v>`);
  const { turns } = mergeLabels(session, snippets, "Rodney White");
  ok("corrects a turn our channel attributed to the wrong person",
     turns[0].who === "Alec Williams" && turns[0].me === false, `${turns[0].who}, me=${turns[0].me}`);
}
{
  // Two people saying near-identical things is a coin flip. Declining beats guessing a name wrong.
  const session = { turns: [{ me: false, who: "Customer", text: "Yes absolutely that is right" }] };
  const snippets = parseTranscript(`WEBVTT

1
00:00:01.000 --> 00:00:03.000
<v Alec Williams>Yes absolutely, that's right.</v>

2
00:00:04.000 --> 00:00:06.000
<v Priya Raman>Yes absolutely that's right.</v>`);
  const { turns, stats } = mergeLabels(session, snippets, "Rodney White");
  ok("declines to name an ambiguous turn", turns[0].who === "Customer" && stats.ambiguous === 1, `who=${turns[0].who}`);
}
{
  // A turn the platform never heard (started recording late, or it was our own bleed) keeps its label.
  const session = { turns: [{ me: false, who: "Customer", text: "Completely unrelated sentence about badgers and hedgerows" }] };
  const snippets = parseTranscript(`WEBVTT

1
00:00:01.000 --> 00:00:04.000
<v Alec Williams>We ingest four terabytes a day from forty sources.</v>`);
  const { turns, stats } = mergeLabels(session, snippets, "Rodney White");
  ok("unmatched turn keeps its existing label", turns[0].who === "Customer" && stats.unmatched === 1);
}
{
  const { turns, stats } = mergeLabels({ turns: [{ me: false, who: "Customer", text: "anything" }] }, [], "Rodney White");
  ok("empty transcript is a no-op, not a wipe", turns[0].who === "Customer" && stats.matched === 0);
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);

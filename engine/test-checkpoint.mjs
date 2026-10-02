// The rep is mid-demo: long rep turns, customer barely speaking. The cue must become a CHECKPOINT
// that compares what is on screen to how they do it today — the move a strong SE makes at that
// moment — rather than opening a fresh discovery thread or offering to book a demo.
import { spawn } from "node:child_process";
import { readFileSync, existsSync, rmSync } from "node:fs";

const turns = [
  { speaker: "customer", text: "Right now we have four separate consoles and the team checks each one by hand every morning." },
  { speaker: "you", text: "Understood. Let me show you how this works. I'm going to jump into our search and reporting app here. This is the search bar where you can search with keywords or field value pairs, and these are written in our search language. Next to it we have the time range picker, which is the best way to filter events because every event is tagged with a timestamp." },
  { speaker: "customer", text: "Okay." },
  { speaker: "you", text: "So if we click into this dashboard you can see all of the failed logins across every device in one place. I'll go ahead and click on this user field, and up here you see reports. I'm going to click top values, and notice how it automatically writes the query for me. Then I can change this to a pie chart and we immediately have that breakdown by user." },
  { speaker: "customer", text: "Mm-hmm." },
  { speaker: "you", text: "And then this page here is the security posture page. When you open the app in the morning this is what shows up first, giving you what happened over the past twenty four hours for intrusion alerts, malware, infected hosts, and the accounts being monitored. Every panel on this dashboard drills down, so clicking any number takes you to the raw events behind it." },
  { speaker: "customer", text: "Okay, yeah." },
  { speaker: "you", text: "I'll show you the firewall page as well. This one is populated from your firewall data cross correlated with the rest of your network information, so you are not just looking at firewall logs in isolation. You can filter by blocked or allowed connections, see traffic by action or protocol, and there is a map of where the inbound traffic is coming from." },
];

const OUT = `/tmp/checkpoint-${Date.now()}.json`;
const env = { ...process.env, SESSION_FILE: OUT, CORRECT_MIN_INTERVAL_MS: "-1", PREP_FILE: "/tmp/cp-no-prep.txt" };
rmSync(env.PREP_FILE, { force: true });
const p = spawn("node", ["serve.mjs", "--framework", "meddic"],
                { cwd: new URL(".", import.meta.url).pathname, env, stdio: ["pipe","pipe","pipe"] });
p.stderr.on("data", () => {});
let i = 0;
const tick = setInterval(() => {
  if (i < turns.length) p.stdin.write(JSON.stringify(turns[i++]) + "\n");
  else {
    clearInterval(tick);
    setTimeout(() => {
      p.kill("SIGKILL");
      if (!existsSync(OUT)) { console.log("FAIL: no session"); process.exit(1); }
      const d = JSON.parse(readFileSync(OUT, "utf8"));
      const cues = (d.turns || []).filter((t) => t.coachQ).map((t) => t.coachQ);
      console.log(`cues during the demo: ${cues.length}`);
      for (const c of cues) console.log(`  ${c}`);
      const comparison = cues.filter((c) => /\bcompare|compared to|today\b|right now\b|currently\b|replace\b|how (?:do|does) (?:you|your team)/i.test(c));
      const pitchesDemo = cues.filter((c) => /in a demo|book a demo|schedule a demo|see that in action/i.test(c));
      let ok = 0, bad = 0;
      const ck = (n, c) => { c ? (ok++, console.log(`  PASS  ${n}`)) : (bad++, console.log(`  FAIL  ${n}`)); };
      console.log();
      ck("produced at least one cue during the demo", cues.length >= 1);
      ck("cue compares to how they work today", comparison.length >= 1);
      ck("never offers to book a demo during one", pitchesDemo.length === 0);
      console.log(`${ok}/${ok + bad} passed`);
      process.exit(bad ? 1 : 0);
    }, 18000);
  }
}, 4000);   // slower than the coach round-trip, so the queue actually drains

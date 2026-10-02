#!/usr/bin/env node
import {callPurpose,purposeGuidance,discoverySafeCue} from './call-purpose.mjs';
import {competitors,competitiveSources,competitiveSignals,competitionReferences,competitiveAnswerPrompt,validateCompetitiveAnswer} from './competition.mjs';
const sessionPurpose=callPurpose(process.env.SALESPILOT_CALL_PURPOSE);
import {registerPrivateNames} from './privacy.mjs';
import {attributedFragments} from './speaker-alignment.mjs';
import {continuationCluster} from './speaker-continuity.mjs';
import {addressedName,statedRole,normalizeRepGreeting,prepPeople,reconcilePreparedName} from './call-name-hints.mjs';
import {QuestionLedger,coverageDetails} from './question-ledger.mjs';
const questionLedger = new QuestionLedger();
let coachProgress = {state:'listening',message:'Listening for a complete customer thought.'};
import { recordTiming, performanceSnapshot, abortable } from './performance.mjs';
import { dialoguePlan, discoveryGuidance } from './dialogue-plan.mjs';
import { mentionedPeople } from './mentioned-people.mjs';
// Persistent streaming coach. Reads {speaker,text} JSON lines from stdin and coaches ONLY the
// newest CUSTOMER turn (incremental). Writes latest.json atomically after each update and prints
// "@@updated@@" so the app refreshes live. Seeds from prep.txt, keeps a follow-up list, a running
// recap, and answers customer questions from your docs (local RAG).

import { createInterface } from "node:readline";
import { writeFileSync, renameSync, mkdirSync, readFileSync, existsSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { PACKS } from "./packs.mjs";
import { fastTier, warmCoach, callLLM, callLLMStream, callQuality, correctTranscript, extractIdentityAI, M } from "./core.mjs";
import { search, indexIfStale } from "./rag.mjs";
import { classify as diarize, shutdown as diarizeShutdown } from "./diarize.mjs";
import { solutionSignals } from "./solutions.mjs";
import { searchSplunkDocs } from "./splunkdocs.mjs";
import { referenceRequest, references, groundedAnswer, answerPrompt } from "./answer-policy.mjs";
import { partialEvidence } from "./coverage-evidence.mjs";
import { AudioActivity } from "./audio-activity.mjs";
const audioActivity = new AudioActivity();
import { currentCoachTurn } from "./coach-timing.mjs";
import { callNotes, callContext, valueGuidance } from "./call-memory.mjs";
import { participantIntro } from "./participants.mjs";
import { opportunities } from "./opportunities.mjs";
import { publicPricingSources } from "./public-sources.mjs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const here = dirname(fileURLToPath(import.meta.url));
function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return def;
  const next = process.argv[i + 1];
  return !next || next.startsWith("--") ? true : next;
}

let pack = PACKS[String(arg("framework", "meddic")).toLowerCase()] || PACKS.meddic;
// SESSION_FILE lets tests run against an isolated file; without it, concurrent engines would read
// and overwrite each other's session and the results would be whichever process wrote last.
const outPath = process.env.SESSION_FILE || resolve(here, "../sessions/latest.json");
// PREP_FILE lets a test pin this to a path that does not exist. Without it the suite silently
// picked up whatever prep the user happened to have active, which changes the opening cue and the
// seeded identity, and made 8 tests fail for reasons that had nothing to do with the code.
const prepPath = process.env.PREP_FILE || resolve(here, "../sessions/prep.txt");
const labelOf = (id) => pack.elements.find((e) => e.id === id)?.label || id;

// Cue-fading ladder (backward-faded worked examples, Renkl/Atkinson): full question -> nudge -> gap.
//   autopilot: the verbatim question to ask (best for genuine novices).
//   nudge:     name the MOVE + their trigger words, but withhold the wording (the rep forms it).
//   gap:       name only the uncovered element + their trigger quote (maximum desirable difficulty).
// Every rung derives from fields the model already returns, so switching modes costs no LLM call.
const CUE_MODES = new Set(["autopilot", "nudge", "gap"]);
let cueMode = (() => { const m = String(arg("mode", "autopilot")).toLowerCase(); return CUE_MODES.has(m) ? m : "autopilot"; })();
function renderCue(q) {
  if (!q) return "";
  if (cueMode === "autopilot") return q.text || "";
  const label = labelOf(q.targets);
  const anchor = (q.anchor || "").trim();
  if (cueMode === "gap") {
    return anchor ? `${label} — not covered yet · their words: “${anchor}”` : `${label} — not covered yet`;
  }
  const why = (q.why || "").trim();                 // "nudge"
  const move = why ? why.charAt(0).toUpperCase() + why.slice(1) : `Advance ${label}`;
  return anchor ? `${move} — build on “${anchor}”` : `${move} (${label})`;
}
const mmss = (s) => `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
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
// Coverage is re-judged from scratch on EVERY coaching call, so on a noisy transcript the verdicts
// are close to random. Replaying a real 146-turn call, the raw signal swung 8/8 -> 1/8 -> 8/8 -> 1/8
// and the number on screen was simply whichever sample happened to be last. The live call showed
// 100% for exactly that reason. So the DISPLAYED status is a vote over recent verdicts rather than
// the latest one: an element has to hold its ground to count, which is what "covered" should mean.
const COVERAGE_VOTES = 3;      // how many recent verdicts to consider
const COVERAGE_QUORUM = 2;     // how many of them must agree before it shows
const covHistory = new Map();  // element id -> recent verdicts, newest last

function recordCoverage(verdicts) {
  for (const e of pack.elements) {
    const v = verdicts?.[e.id];
    if (v === undefined) continue;
    const h = covHistory.get(e.id) || [];
    h.push(v);
    if (h.length > COVERAGE_VOTES) h.shift();
    covHistory.set(e.id, h);
  }
}

/// Some elements need evidence, not an opinion. Measured on simulated calls, the model marked
/// champion "done" when no champion had ever been named and economic_buyer "done" six turns before
/// the buyer was mentioned. That inflation tipped the call into the close phase early AND told the
/// coach "already established, do not re-probe" about ground that was never covered. Without the
/// evidence, the best an element can settle at is "partial".
function hasEvidenceFor(id) {
  if (id === "economic_buyer" || id === "champion") {
    // Somebody on their side has to have been named at all before we can claim to know who decides.
    return !!customerName || roster.some((p) => p.name);
  }
  if (id === "metrics") {
    // Metrics means a quantity they actually said, not a feeling that something is expensive.
    return HARD_NUMBER.test(customerEvidence());
  }
  return true;
}

/// Settled status for one element: the strongest level that COVERAGE_QUORUM of the recent verdicts
/// support. One confident-sounding outlier can no longer promote an element on its own.
function settledCoverage(id) {
  if (confirmed.has(id)) return "done";          // a fact we established deterministically
  const h = covHistory.get(id) || [];
  const evidenceFloor=partialEvidence(turns,turnSide)[id] ? "partial" : "open";
  if (!h.length) return coverage[id] && coverage[id]!=="open" ? coverage[id] : evidenceFloor;
  for (const level of ["done", "partial"]) {
    const rank = { open: 0, partial: 1, done: 2 };
    if (h.filter((v) => (rank[v] ?? 0) >= rank[level]).length >= COVERAGE_QUORUM) {
      return level === "done" && !hasEvidenceFor(id) ? "partial" : level;
    }
  }
  return evidenceFloor;
}
const confirmed = new Set();      // coverage elements confirmed deterministically (never regress)
const turns = [];
const nextqDedup = new Map();
/// Exact-match dedup missed the real problem: the coach reworded the same ask every turn
/// ("Who signs off on that spend?" / "Who holds authority to approve that spend?" / "Who has final
/// say on that spend?"). To the rep that is the same cue three times. Reject anything that is mostly
/// the same words as something already on screen.
const QUESTION_DUP_SIM = 0.5;   // erring toward one good cue over three rewordings of it
function isNearDuplicateQuestion(text) {
  const words = (t) => new Set((t || "").toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter((w) => w.length > 3));
  const a = words(text);
  if (a.size < 3) return false;
  for (const v of nextqDedup.values()) {
    const b = words(v.raw?.text || v.q);
    if (!b.size) continue;
    let inter = 0; for (const w of a) if (b.has(w)) inter++;
    if (inter / Math.min(a.size, b.size) >= QUESTION_DUP_SIM) return true;
  }
  return false;
}
const followupsSet = new Set();
const followups = [];
let recap = null;
let nextSteps = [];
let firstCust = null;
let sinceRecap = 0;
let custTurns = 0;
let recapInFlight = false;
let answerInFlight = false;
let activeAnswerController = null;
let questionSeq = 0;
let pendingQ = null;
let customerName = null;
let customerRole = null;
let roster = [];   // everyone on the customer side who introduced themselves (dynamically extracted, never hardcoded)

// --- Delivery coaching -------------------------------------------------------------------------
// Discovery is scored on HOW you talk, not just what you ask: talk ratio, filler words, monologue
// length, and whether you framed the call up front. We hear both channels separately, so we can
// measure all four live. Counted AFTER echo de-dup, so speaker bleed never inflates your own share.
const callStart = Date.now();
let youWords = 0, custWords = 0, fillerCount = 0, longestYouWords = 0;
let openingFramed = null;   // null until the rep's first substantive turn is seen
const FILLERS = ["um","uh","er","ah","hmm","mmm","you know","i mean","sort of","kind of","basically","literally"];
function countFillers(text) {
  const t = " " + text.toLowerCase().replace(/[^a-z\s]/g, " ").replace(/\s+/g, " ") + " ";
  return FILLERS.reduce((n, f) => n + (t.split(" " + f + " ").length - 1), 0);
}
/// A good open names WHY you're calling and asks permission to run discovery. Both, or it doesn't count.
function looksFramed(text) {
  const t = text.toLowerCase();
  const purpose = /(understand|you'?re (running into|having|experiencing)|i know you|reached out|reason for)/.test(t);
  const permission = /(can i ask|mind if i|is it ok|before i show|walk me through|couple of questions|some questions)/.test(t);
  return purpose && permission;
}
function delivery() {
  const total = Math.max(youWords, 0) + custWords;
  const mins = Math.max((Date.now() - callStart) / 60000, 0.5);
  const duration = t => Number.isFinite(t.startedAt) && Number.isFinite(t.endedAt) ? Math.max(0, t.endedAt - t.startedAt) : null;
  const timed = turns.length > 0 && turns.every(t => duration(t) !== null);
  const yourSeconds = turns.filter(t => t.me).reduce((sum,t) => sum + (duration(t) || 0), 0);
  const allSeconds = turns.reduce((sum,t) => sum + (duration(t) || 0), 0);
  return {
    talkRatio: timed && allSeconds > 0 ? Math.round(yourSeconds / allSeconds * 100) : (total > 0 ? Math.round(Math.max(youWords,0) / total * 100) : 0),
    measurement: timed ? "audio duration" : "word estimate",
    fillerPerMin: Math.round(Math.max(fillerCount, 0) / mins),
    longestMonologueSec: timed ? Math.round(Math.max(0, ...turns.filter(t=>t.me).map(t=>duration(t)))) : Math.round(longestYouWords / 2.5),
    openingFramed,
  };
}
let liveAnswer = null;
const answerHistory = [];
function saveAnswer(answer) {
  liveAnswer = answer;
  if(answer.status==='unverified')coachProgress={state:'failed',message:'Could not verify the product answer. Keep it open or defer explicitly.'};
  if(answer.questionId)questionLedger.lookup(answer.questionId,answer.status === "grounded" ? "ready" : "needs_confirmation",answer);
  answerHistory.push({...answer, receivedAt: Date.now()});
}
let engineError = null;   // set when the model is unreachable, so the app can warn the rep

const ROLE_TITLES = "ceo|cto|cio|ciso|cfo|coo|vp|vice president|director|head|manager|founder|owner|architect|engineer|analyst|president|administrator|officer|specialist|consultant|scientist|developer|lead";
// Seniority and scope words that sit in front of a title. A real call said "global director of
// security operations" and came back with no role at all, because only senior/lead/head-of were
// allowed here. Up to two, so "global senior director" also lands.
const ROLE_PREFIX = `(?:[a-z][a-z-]{1,14}\\s+){0,3}`;
const NAME_STOP = new Set(["there", "so", "much", "everyone", "really", "great", "ready", "sorry", "just",
  "well", "okay", "yeah", "actually", "today", "now", "here", "looking", "thanks", "good", "fine",
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
  // common "I'm X" / "I am X" completions that aren't names (guards the soft trigger)
  "thinking", "going", "trying", "working", "doing", "hoping", "wondering", "curious", "interested",
  "confident", "excited", "glad", "happy", "afraid", "worried", "familiar", "aware", "responsible",
  "calling", "reaching", "based", "done", "sure", "not", "still", "pretty", "kind", "honestly",
  "currently", "definitely", "probably", "super", "gonna", "gunna", "hearing", "seeing", "assuming"]);
const isName = (w) => !!w && /^[A-Z][a-z]+$/.test(w) && !NAME_STOP.has(w.toLowerCase()) &&
  !new RegExp(`^(${ROLE_TITLES})$`, "i").test(w);
const stripTail = (s) => s
  // "of X" is part of the title ("Director OF Security Operations") and stays. "at/for/on the X" is
  // where they work or sit, and does not belong in a role.
  .replace(/\s+\b(?:at|for|with|within|over at)\s+[A-Za-z][\w&.' -]{1,40}$/i, "")     // "... at Apple"
  .replace(/\s+\b(?:on|in)\s+(?:the\s+)?[A-Za-z][\w&.' -]{1,40}$/i, "")              // "... on the SOC team"
  .replace(/\s+\b(?:but|so|because|which|where|when|while|although)\b\s+.*$/i, "")   // new clause
  .replace(/\s+\band\s+(?:we|i|our|they|it|then)\b.*$/i, "")                          // "...and we also..."
  .replace(/\s+\b(?:we|they)\b\s+.*$/i, "")                                           // "...team we handle..."
  .replace(/\s+(here|now|today|currently|for us|at the moment)$/i, "")
  .trim();

// Role titles are displayed next to a person's name, so they read as titles: "Security Operations",
// not "security operations". Existing all-caps stays as-is so IT, SOC, VP and CISO are not mangled
// into "It" and "Soc", and the small joining words inside a title stay lowercase.
const ROLE_MINOR = new Set(["of", "the", "and", "for", "at", "in", "on", "to", "a", "an", "with"]);
function titleCaseRole(s) {
  // Roles are sliced out of a spoken sentence, so they arrive carrying its punctuation.
  const t = String(s || "").trim().replace(/[.,;:!?]+$/, "").trim();
  if (!t) return t;
  return t.split(/\s+/).map((w, i) => {
    if (/^[A-Z0-9&/.-]{2,}$/.test(w)) return w;                      // IT, SOC, VP, CISO, R&D
    const lower = w.toLowerCase();
    if (i > 0 && ROLE_MINOR.has(lower)) return lower;
    return lower.charAt(0).toUpperCase() + lower.slice(1);
  }).join(" ");
}

// Pull the customer's name + role from what's said; stated authority fills Economic Buyer.
/// True when an introduction in this text is REPORTED rather than real: someone quoting an example,
/// coaching a script, or speaking hypothetically. A real call produced
///   "So you basically say, 'Hey guys, so my name's Rami, I'm an SED at Splunk.'"
/// and the customer was recorded as Rami, SED at Splunk, from a line demonstrating what the REP
/// should say. Pattern matching had no way to tell; meaning is the only thing that separates them.
const REPORTED_SPEECH = /\b(you(?:'d| would| could|'ll| will)? (?:basically |just |then |usually )?say|say(?:ing)? something like|for example|e\.?g\.?|imagine|pretend|let'?s say you|i would say|they(?:'d| would) say|as in|like,? ["“])/i;
function isReportedIntro(text) {
  if (REPORTED_SPEECH.test(text)) return true;
  // An introduction sitting inside quotation marks is a quotation, not an introduction.
  const quoted = text.match(/["“‘']([^"”’']{10,200})["”’']/);
  return !!(quoted && /\b(my name'?s?|my name is|this is|i'?m|i am)\b/i.test(quoted[1]));
}

function extractIdentity(text, isMe) {
  // Names, in confidence order:
  //  strong — "my name is X" / "this is X": unambiguous, so it may CORRECT an earlier bad guess.
  //  soft   — "I'm X" / "I am X": the COMMON way people introduce themselves ("Hi, I'm Dana"), so we
  //           honor it, but only fill an EMPTY slot and only when X passes isName (capitalized proper
  //           noun, not a stopword/role) — which rejects "I'm thinking / ready / sorry / going".
  //  greet  — the rep greeting them by name ("Hi Dana"): often the cleanest signal; fills if empty.
  const strong = !isMe && text.match(/\b(?:my name'?s|my name is|this is)\s+([A-Za-z]+)(?:\s+([A-Za-z]+))?\b/i);
  const soft   = !isMe && text.match(/\bi(?:'?m| am)\s+([A-Za-z]+)(?:\s+([A-Za-z]+))?\b/i);
  const greet  = isMe  && text.match(/\b(?:hi|hey|hello|nice to meet you|great to meet you)[,!]?\s+([A-Za-z]+)\b/i);
  // badge — "Alec Williams, Director of Data Engineering": people introduce themselves this way
  // constantly and there is no "I'm" to key on. Requiring a role title right after the comma keeps
  // it precise, so "Thanks Rodney, that makes sense" can't trip it.
  const lead = text.replace(/^(?:(?:sure|yeah|yes|yep|ok|okay|hi|hello|hey|thanks|so|well)[,.!]?\s+)*/i, "");
  // Anchored at any sentence boundary, not just the start of the turn: "Sorry, I should introduce
  // myself. Alec Williams, Director of Data Engineering." is a completely normal way to do it.
  // Every candidate is tried, because the FIRST one to fit the shape is often not the name
  // ("Sorry, I should..." fits it too) — the role title after the comma is what settles it. The
  // trailing text is a lookahead so one candidate does not swallow the boundary before the next.
  // \b after the alternation is load-bearing: ROLE_TITLES contains "coo", "cio", "vp" and friends,
  // and without a boundary "cool" matches "coo". A real call turned "Oh, cool. Okay." into
  // customerName "Oh" with role "Cool. Okay".
  const roleRe = new RegExp(`^(?:the\\s+|a\\s+|an\\s+)?${ROLE_PREFIX}(?:${ROLE_TITLES})\\b`, "i");
  let badge = null;
  if (!isMe) {
    for (const m of lead.matchAll(/(?:^|[.!?]\s+)([A-Z][a-z]+)(?:\s+([A-Z][a-z]+))?\s*,\s*(?=(.{3,44}))/g)) {
      if (isName(m[1]) && roleRe.test(m[3])) { badge = m; break; }
    }
  }
  let selfIntroduced = null;
  // Someone quoting an example introduction is not introducing themselves.
  if (!isMe && isReportedIntro(text)) return null;
  if (badge) {
    const nextName = isName(badge[2]) ? `${badge[1]} ${badge[2]}` : badge[1];
    if (customerName !== nextName) customerRole = null;
    customerName = isName(badge[2]) ? `${badge[1]} ${badge[2]}` : badge[1];
    selfIntroduced = customerName;
    if (!customerRole) customerRole = titleCaseRole(stripTail(badge[3].trim()));
  } else if (strong && isName(strong[1])) {
    const nextName = isName(strong[2]) ? `${strong[1]} ${strong[2]}` : strong[1];
    if (customerName !== nextName) customerRole = null;
    customerName = isName(strong[2]) ? `${strong[1]} ${strong[2]}` : strong[1];
    selfIntroduced = customerName;
  } else if (soft && isName(soft[1])) {
    // Reported even when a name is already known: on a multi-person call the SECOND person to
    // introduce themselves is a different voice, and gating this on an empty slot made them
    // permanently anonymous.
    selfIntroduced = isName(soft[2]) ? `${soft[1]} ${soft[2]}` : soft[1];
    if (!customerName) customerName = selfIntroduced;
  } else if (!customerName && greet && isName(greet[1])) {
    customerName = greet[1];   // the rep's voice, not the customer's — never names a cluster
  }
  if (!isMe) {
    if (/\b(?:i (?:own the budget|sign off|approve|have (?:the )?final say)|i am (?:the )?budget owner)\b/i.test(text)) {
      customerRole = customerRole || "decision-maker";
      confirmed.add("economic_buyer");
      coverage.economic_buyer = "done";
    }
    const rm = text.match(new RegExp(`\\bi(?:'?m| am)\\s+(?:the\\s+|a\\s+|an\\s+)?(${ROLE_PREFIX}(?:${ROLE_TITLES})\\b[a-z ]*)`, "i"));
    if (rm && rm[1] && !customerRole) customerRole = titleCaseRole(stripTail(rm[1].trim()));
    const runm = text.match(/\bi\s+(?:run|lead|head|manage|own)\s+(?:the\s+)?([a-z][a-z ]{2,60})/i);
    if (runm && runm[1] && !customerRole) customerRole = titleCaseRole(`leads ${stripTail(runm[1].trim())}`);
  }
  return selfIntroduced;
}

/// Add or update one person on the customer side, keyed by name. Never drops someone already
/// there, and never overwrites a known role with a blank one: the regex sees the intro first and
/// the LLM refines it a few turns later, so both have to be able to contribute.
function upsertRoster(name, role = null, decisionMaker = null) {
  const clean = (name || "").trim();
  if (!clean) return;
  const existing = roster.find((p) => p.name.toLowerCase() === clean.toLowerCase());
  if (existing) {
    if (role && role.trim()) existing.role = role.trim();
    if (decisionMaker !== null) existing.decisionMaker = !!decisionMaker;
    return;
  }
  roster.push({ name: clean, role: (role || "").trim(), decisionMaker: !!decisionMaker, side:"unknown" });
}

// Seed prior context (call prep / a Gong recap). Capped so it doesn't blow up every prompt.
let prepContext = null;
if (existsSync(prepPath)) {
  const prep = readFileSync(prepPath, "utf8").trim().slice(0, 4000);
  if (prep) { prepContext = prep; rolling += `context (known before the call): ${prep}\n`; }
}

// --- Cross-channel echo de-duplication --------------------------------------------------------
// The customer's audio plays out the laptop speakers and the MIC picks it up, so the SAME utterance
// lands on both channels (confirmed in real call data: Dylan's intro appeared as both YOU and CUST).
// macOS voice processing can't cancel it — it only cancels what this app itself renders, and the
// customer audio comes from the conferencing app. So de-duplicate in software. The system-audio copy
// is authoritative for the customer; the mic copy is bleed and gets dropped.
const ECHO_WINDOW_MS = 12000;
// Real bleed measured at 0.67 / 0.69 containment — the mic hears a GARBLED, often SPLIT version of
// what the speakers played, so it never matches cleanly. 0.55 catches those while a rep legitimately
// mirroring the customer ("So you're saying you have service issues?") measures ~0.40.
// Compared with bleedSimilarity below, which is ORDER-aware. A set-based score could not separate
// real bleed (0.67 on verbatim call data) from two people independently using the call's vocabulary
// at the same moment (0.58), and tuning the number either deleted the rep's own question or let
// the customer's words through labelled "You".
const ECHO_SIM = 0.5;
const MIN_ECHO_WORDS = 5;   // don't let short turns ("okay", "right") trip the comparison
// Backchannels are the most common turn in a call and were exempt from the echo test entirely, so
// a customer's "Exactly." bleeding into the mic showed up as a second line labelled You. Short
// turns are still compared, but only on an EXACT match landing within a couple of seconds, which
// is bleed rather than the rep happening to agree a moment later.
const SHORT_ECHO_MS = 2500;
/// The rep deliberately playing back what the customer just said is a standard discovery move, and
/// lexically it is indistinguishable from bleed. The giveaway is the frame they wrap around it.
const MIRROR_FRAME = /\b(?:did i get that right|is that right|have i got that right|am i hearing|so you'?re saying|what i'?m hearing|let me play (?:that|it) back|to play that back|so if i understand)\b/i;
let recentTurns = [];   // { me, text, at }
let echoMicCopy = 0, echoCustCopy = 0, turnsSeen = 0;

// --- Speaker diarization -------------------------------------------------------------------------
// A voice cluster is who ACTUALLY spoke; the channel is only where the audio arrived. They differ
// whenever the room bleeds. Clusters land asynchronously (an embedding takes ~100ms and must never
// sit in front of the transcript), so nothing here is baked into a turn: labels are derived at write
// time and every map below is allowed to fill in late.
let turnSeq = 0;
const clusterOfTurn = new Map();    // turn id  -> voice cluster
const channelsOfCluster = new Map();// cluster  -> { mic, sys }: which channels this VOICE arrived on
const sideOfCluster = new Map();
const clusterName   = new Map();    // cluster  -> the name that cluster introduced itself as
const participantByTurn = new Map();
const organizationOfCluster = new Map();
const manualClusters = new Set();
const conflictedClusters = new Set();
const introByTurn   = new Map();
let addressedIdentity = null;    // turn id  -> name self-introduced in that turn
const micByCluster  = new Map();    // cluster  -> how often it spoke on the mic channel
let repCluster = null;
const clusterEvidenceCounts = new Map();
const clusterDisplayNumbers = new Map();
const sysByCluster = new Map();
function supportedCluster(c){return turns.filter(t=>clusterOfTurn.get(t.id)===c&&!['mixed','ambiguous'].includes(t.speakerStatus)).length;}
function displayCluster(c) {
 if(c===undefined)return null;
 if(!clusterDisplayNumbers.has(c) && supportedCluster(c)>=2)clusterDisplayNumbers.set(c,clusterDisplayNumbers.size+1);
 return clusterDisplayNumbers.has(c)?`Speaker ${clusterDisplayNumbers.get(c)}`:null;
}

function turnSide(turn) {
  const cluster = clusterOfTurn.get(turn.id);
  if (cluster !== undefined && manualClusters.has(cluster)) return sideOfCluster.get(cluster) || "unknown";
  if (["mixed","ambiguous"].includes(turn.speakerStatus)) return "unknown";
  if (turn.presentationNarration && sideOfCluster.get(cluster)!=='seller') return 'presenter';
  if (cluster !== undefined && sideOfCluster.has(cluster)) return sideOfCluster.get(cluster);
  if (turn.me) return participantByTurn.get(turn.id)?.side || "seller";
  if (cluster !== undefined && conflictedClusters.has(cluster)) return "unknown";
  if (cluster !== undefined && cluster === repCluster) return "seller";
  return sideOfCluster.get(cluster) || turn.side || "unknown";
}
function rebuildTranscript() {
  rolling = (prepContext ? `context (known before the call): ${prepContext}\n` : "")
    + turns.map(t => `${t.me ? "me" : (turnSide(t) === "seller" ? "seller" : (turnSide(t) === "presenter" ? "presenter" : "cust"))}: ${t.text}\n`).join("");
}
function customerEvidence() {
  return turns.filter(t => !["mixed", "ambiguous"].includes(t.speakerStatus) && !["seller", "presenter"].includes(turnSide(t))).map(t => t.text).join("\n");
}
/// The rep is whichever voice dominates the mic channel. Needs real evidence and a clear margin,
/// because guessing this wrong would rename the customer to "You" for the whole call.
function inferRepCluster() {
  let top = null, topN = 0, second = 0;
  for (const [c, n] of micByCluster) {
    if (n > topN) { second = topN; top = c; topN = n; }
    else if (n > second) second = n;
  }
  repCluster = (topN >= 3 && topN > second && topN >= 2*(sysByCluster.get(top)||0)) ? top : null;
}

/// Attach a voice cluster to a turn once the sidecar answers. Safe to call for a turn that has since
/// been retracted as echo — the id simply no longer resolves to anything on screen.
function attachCluster(turnId, cluster, wasMic) {
  if (cluster === null || cluster === undefined || !turns.some(t=>t.id===turnId)) return;
  clusterOfTurn.set(turnId, cluster);
  clusterEvidenceCounts.set(cluster,(clusterEvidenceCounts.get(cluster)||0)+1);
  if(!wasMic)sysByCluster.set(cluster,(sysByCluster.get(cluster)||0)+1);
  if (conflictedClusters.has(cluster)) { const t = turns.find(t=>t.id===turnId); if (t) t.speakerStatus = "ambiguous"; }
  const ch = channelsOfCluster.get(cluster) || { mic: false, sys: false };
  if (wasMic) ch.mic = true; else ch.sys = true;
  channelsOfCluster.set(cluster, ch);
  if (wasMic) micByCluster.set(cluster, (micByCluster.get(cluster) || 0) + 1);
  const attached = turns.find(t=>t.id===turnId);
  if(attached?.presentationNarration && !manualClusters.has(cluster) && !sideOfCluster.has(cluster))sideOfCluster.set(cluster,'presenter');
  inferRepCluster();
  rebuildTranscript();
  const name = introByTurn.get(turnId);
  // Only a SELF-introduction names a cluster. The rep saying "great to meet you Alec" must never
  // label the rep's own voice as Alec.
  const participant = participantByTurn.get(turnId);
  const response=turns.find(t=>t.id===turnId);
  const remoteClusters=new Set(turns.filter(t=>!t.me).map(t=>clusterOfTurn.get(t.id)).filter(c=>c!==undefined));
  if(!wasMic && !name && addressedIdentity && remoteClusters.size===1 && !clusterName.has(cluster) && !conflictedClusters.has(cluster) && !['mixed','ambiguous'].includes(response?.speakerStatus) && Date.now()-addressedIdentity.at<90000 && /\b(?:thank you|nice meeting|i(?:’|'| a)m|i(?:’|')ve been)\b/i.test(response?.text||'')) {
    clusterName.set(cluster,addressedIdentity.name);
    customerName=addressedIdentity.name;
    const role=statedRole(response.text)||'';
    upsertRoster(customerName,role);const entry=roster.find(p=>p.name===customerName);if(entry){entry.side='unknown';entry.nameEvidence='Addressed by the rep; role affiliation unconfirmed';}
    if(role)customerRole=role;
  }
  if (name && !manualClusters.has(cluster)) {
    const existing = clusterName.get(cluster);
    if (existing && existing !== name && !name.toLowerCase().startsWith(existing.toLowerCase()+' ') && !existing.toLowerCase().startsWith(name.toLowerCase()+' ')) {
      displayCluster(cluster); // retain the same anonymous voice ID while identity is reviewed
      conflictedClusters.add(cluster);
      for (const t of turns) if (clusterOfTurn.get(t.id) === cluster) t.speakerStatus = "ambiguous";
      clusterName.delete(cluster);
      sideOfCluster.set(cluster, "unknown");
    } else if (!conflictedClusters.has(cluster)) { clusterName.set(cluster, name); }
  }
  if (participant && !manualClusters.has(cluster) && !conflictedClusters.has(cluster)) {
    if (participant.side !== "unknown") sideOfCluster.set(cluster, participant.side);
    if (participant.organization) organizationOfCluster.set(cluster, participant.organization);
  }
  writeSession();
}
// Successfully removed duplicate copies are diagnostic information, not a routing failure.
const echoEvents=[];let echoNoticeTimer=null;
function recordEcho(direction){echoEvents.push({direction,at:Date.now()});while(echoEvents.length>100)echoEvents.shift();clearTimeout(echoNoticeTimer);echoNoticeTimer=setTimeout(()=>writeSession(),31000);echoNoticeTimer.unref();}
function audioWarning() {
 // Neither shared voice clusters nor successful duplicate removal establishes an unresolved
 // capture problem. Actual device/capture failures retain their separate native error state.
 return null;
}
const normWords = (t) => (t || "").toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter(Boolean);
/// How much of the shorter turn appears in the longer one IN THE SAME ORDER. Speaker bleed is one
/// utterance transcribed twice, so even a garbled mic copy keeps the word order of the customer's
/// audio. Two people talking about the same subject reuse the same vocabulary but not the sequence,
/// which is what tells the two cases apart.
function bleedSimilarity(a, b) {
  const A = normWords(a), B = normWords(b);
  if (!A.length || !B.length) return 0;
  const dp = Array.from({ length: A.length + 1 }, () => new Array(B.length + 1).fill(0));
  for (let i = 1; i <= A.length; i++) {
    for (let j = 1; j <= B.length; j++) {
      dp[i][j] = A[i - 1] === B[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }
  return dp[A.length][B.length] / Math.min(A.length, B.length);
}

function similarity(a, b) {
  const A = new Set(normWords(a)), B = new Set(normWords(b));
  if (!A.size || !B.size) return 0;
  let inter = 0;
  for (const w of A) if (B.has(w)) inter++;
  return inter / Math.min(A.size, B.size);   // containment — tolerates one side being truncated
}

// Windowed transcript for the model — keep the prep seed + the most recent context, bounded.
function coachTranscript() {
  return callContext(turns, callNotes(turns, turnSide), prepContext, turnSide);
}

// Deterministically drive advancement: a small model fixates on the opening topic even when told to
// move on, so the ENGINE picks the next element to cover (first still-open in methodology order, else
// the first partial to deepen) and FORCES the question's target. The model only phrases it.
let lastForcedTarget = null, forcedTargetRuns = 0;
const FORCED_TARGET_LIMIT = 1;   // one attempt, then follow the customer. Three burned the disclosure.

// Cadence, measured against a real 231-turn demo call run by a strong SE: he asked about 24
// questions, roughly one per capability block. The coach fired 127 on that same call, a cue on more
// than half of all turns, which reads as an interrogation and buries the good ones. So hold after
// each cue — unless the customer just said something worth reacting to immediately, which is what a
// person listening would do.
const CUE_HOLD_TURNS = 3;
let turnsSinceCue = 99;
/// The last few cues actually put on screen. isNearDuplicateQuestion guards the nextq LIST but was
/// never applied to the per-turn cue, which is how one closing paragraph rendered eight times.
const shownCues = [];
function isRepeatOfShownCue(text) {
  const words = (t) => new Set((t || "").toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter((w) => w.length > 3));
  const a = words(text);
  if (a.size < 3) return false;
  for (const prev of shownCues.slice(-6)) {
    const b = words(prev);
    if (!b.size) continue;
    let inter = 0; for (const w of a) if (b.has(w)) inter++;
    if (inter / Math.min(a.size, b.size) >= 0.6) return true;
  }
  return false;
}

let frameworkEpoch = 0;

// Serial turn queue. The readline loop stays a fast dispatcher; this drains it in the background so
// control commands (framework / mode / recap) are always handled the moment they arrive.
const turnQueue = [];
let draining = false;
async function drainTurns() {
  if (draining) return;
  draining = true;
  try {
    while (turnQueue.length) {
      try { await handleTurn(turnQueue.shift()); }
      catch (e) { console.error(`[serve] turn error: ${e.message}`); }
    }
  } finally { draining = false; }
}
const COV_RANK = { open: 0, partial: 1, done: 2 };
/// Upgrade-only merge. A background re-coach reasons about an older transcript than the live turn
/// loop, so it may fill gaps but must never walk coverage backwards.
function mergeCoverage(into, add) {
  for (const [k, v] of Object.entries(add || {})) {
    if ((COV_RANK[v] ?? 0) >= (COV_RANK[into[k] || "open"] ?? 0)) into[k] = v;
  }
  return into;
}

// Pull the question out of a JSON object that is still being written. The value arrives a character
// at a time, so the closing quote usually is not there yet; this grabs whatever exists so far.
const PARTIAL_Q = /"text"\s*:\s*"((?:[^"\\]|\\.)*)/;
let livePartialCue = null;
function onCoachDelta() {
  // The visible suggestion is published only after grounding and validation complete.
}

// Names expected on this call, from call prep. Priming whisper with these is the first line of
// defence; this is the second, for when the audio was bad enough that it mis-heard anyway.
function preparedPeople(){return prepPeople(prepContext);}
function expectedNames() {
  return preparedPeople().map(p=>p.name);
}

/// Snap a mis-heard name onto the one we were told to expect, but only on strong evidence: an exact
/// surname match with the same number of parts. "Nalanda Nair" becomes "Nilanjana Nair"; an unrelated
/// person who happens to be on the call is left alone.
function reconcileName(heard) {
  return reconcilePreparedName(heard,preparedPeople());
}

// A turn has to contain something about THEIR world before it is worth coaching on. Without this,
// "Sorry for interrupting, Liam." (4 words) produced "When you say sorry for interrupting, who
// ultimately manages the budget for this RBA project?"
//
// Tuned against 461 real customer turns from sessions/history. The failure that matters here is the
// FALSE NEGATIVE: dropping a real answer means the rep gets no coaching at the moment it counted.
// Three findings drove this shape:
//   - Meeting-narration phrases must be anchored, not matched anywhere. An unanchored "that's it"
//     pattern was eating "The problem is that it takes three weeks to onboard a log source."
//   - Real discovery answers are SHORT. "Our SIEM is Splunk." and "About four terabytes a day."
//     carry more signal than most long turns, so a raw word count cannot be the only test.
//   - Apostrophes must be stripped before tokenising, or "it's, it's, it's" counts five words.
const ACK_ONLY = /^(?:(?:yeah|yes|yep|yup|no|nope|right|ok|okay|alright|all right|sure|exactly|correct|absolutely|totally|agreed|true|gotcha|mm+|hm+|mhm+|uh[- ]?huh|mm[- ]?hmm|got it|of course|for sure|makes sense|sounds good|fair enough|no problem|one hundred percent|a hundred percent|100 percent|hundred percent|thank you|thanks|awesome|cool|nice|great|perfect|sorry|oh|um|uh|well|so|and|but)\b[\s,.!?-]*)+$/i;

// Narration ABOUT the meeting, only when it opens or is the whole turn. "let's ..." is deliberately
// absent: "Okay, let's go with Splunk Enterprise Security then" is a buying decision, not narration.
const META_OPEN = /^(?:\W*(?:so|ok|okay|alright|all right|well|and|but|now)\b[\s,]*)*(?:sorry for interrupting|next (?:slide|section|part)|welcome (?:back|everyone)|let me (?:pull up|find|share|show)|give you (?:all )?a second|take a break|any questions(?: about this)?\??$|back to you|over to you)/i;
const META_END = /(?:^|[.!?]\s*)that'?s (?:it|all)[\s.!?]*$/i;
// Pleasantries and known speech-to-text hallucinations. Whisper emits the "watching/subscribe"
// family on silence, and it reached the coaching prompt on a real call.
const PLEASANTRY = /\b(?:thank(?:s| you)(?: (?:you|all|both))? (?:so much )?for (?:watching|joining|listening|your time|participating)|don'?t forget to subscribe|please subscribe|can (?:you|everyone) hear me|share your screen|see you (?:later|in the next one))\b/i;

const FILLER_WORDS = new Set(["the","a","an","and","or","but","so","is","are","was","were","be","been","am",
  "to","of","in","on","at","it","its","this","that","we","i","you","they","he","she","me","us","them",
  "our","my","your","their","have","has","had","there","here","what","can","all","about","for","with","from",
  "yeah","like","just","really","very","kind","sort","were","would","will","do","does","did"]);
// Signals that a SHORT turn is still a real answer: a number, a time or size unit, or a proper noun
// that is not just the first word of the sentence (a product, vendor, or person).
const HAS_ENTITY = /\b\d|\b(?:tb|gb|mb|terabytes?|gigabytes?|days?|weeks?|months?|quarters?|years?|q[1-4]|k|m|million|thousand)\b/i;

// Speech-to-text output that is visibly broken: stuttered repeats ("the the", "is uh is"), a
// trailing hedge ("i mean", "or something"), or a high density of disfluency. Coaching on these is
// where the model invents specifics — "the the seven i mean" became a confident question about a
// seven-year retention policy, five times out of five.
const STUTTER = /\b(\w+)\s+\1\b/i;                       // "the the", "is is"
const TRAILING_HEDGE = /\b(?:i mean|or something|something like that|you know what i mean|i think)\s*[.?!]?\s*$/i;
const DISFLUENCY = /\b(?:uh|um|er|ah)\b/gi;
// Mid-sentence self-correction. Combined with a hedge it means the speaker is unsure of their own
// number, and that is precisely when the model fabricates a confident specific from it.
const SELF_CORRECTION = /\b(?:no sorry|sorry no|wait no|actually no|scratch that|i mean no|or was it)\b/i;
function isGarbled(text) {
  const t = (text || "").trim();
  if (!t) return true;
  const words = t.split(/\s+/).filter(Boolean);
  if (words.length < 3) return false;
  const fillers = (t.match(DISFLUENCY) || []).length;
  if (fillers / words.length > 0.15) return true;            // one in seven words is a disfluency
  if (STUTTER.test(t) && TRAILING_HEDGE.test(t)) return true; // stuttered AND hedged: low confidence
  if (fillers >= 2 && STUTTER.test(t)) return true;
  if (SELF_CORRECTION.test(t) && TRAILING_HEDGE.test(t)) return true;
  return false;
}

function isSubstantive(text) {
  const t = (text || "").trim();
  if (!t) return false;
  if (ACK_ONLY.test(t)) return false;
  if (PLEASANTRY.test(t)) return false;
  if (META_OPEN.test(t) || META_END.test(t)) return false;
  if (isGarbled(t)) return false;   // don't let the model resolve broken audio into invented facts
  const words = t.split(/\s+/);
  const properNoun = words.slice(1).some((w) => /^[A-Z][A-Za-z.&-]{1,}$/.test(w.replace(/[^\w.&-]/g, "")));
  const content = t.toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/).filter((w) => w && !FILLER_WORDS.has(w));
  // A short turn still counts when it names something concrete.
  if (content.length >= 2 && (properNoun || HAS_ENTITY.test(t))) return true;
  return content.length >= 3;
}

// Markers that the customer just said the thing they came to say. On these turns a tracked goal is
// actively harmful: measured, the customer said "the bigger problem isn't the bill" and got asked
// who chairs the meeting, and said "two hundred grand in lost orders" and got asked about brand
// damage. When one of these fires, no goal is passed at all and the coach probes what they said.
const SALIENCE = /\b(?:honestly|frankly|to be honest|the (?:bigger|real|actual|main) (?:problem|issue|thing)|what (?:keeps me up|worries me|scares me)|(?:actual|real) reason (?:i|we)|reason (?:i|we) (?:took|wanted|am on|are on)\\b|biggest (?:problem|issue|pain)|kills us|killing us|we got burned|blew up|cost us)\b/i;
// Live speech spells numbers out far more often than it writes them: "two hundred grand",
// "three analysts", "four hundred alerts a day". A digits-only pattern misses nearly all of them.
const NUM_WORD = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|couple|dozen";
const UNIT = "k\\b|m\\b|million|thousand|grand|dollars?|percent|%|hours?|days?|weeks?|months?|quarters?|years?|terabytes?|tb\\b|gb\\b|fte|headcount|people|analysts?|engineers?|alerts?|incidents?|tickets?|servers?|endpoints?|sources?|seats?|users?";
const HARD_NUMBER = new RegExp(`\\b(?:\\$\\s?\\d|\\d[\\d,.]*\\s?(?:${UNIT})|(?:${NUM_WORD})\\s+(?:\\w+\\s+){0,2}?(?:${UNIT}))`, "i");
function isHighSignal(text) { const t = text || ""; return SALIENCE.test(t) || HARD_NUMBER.test(t); }

/// Is the rep mid-demo? Several long rep turns with the customer barely speaking means they are
/// presenting, not discovering. The right cue then is not a fresh probe but a CHECKPOINT: get a
/// reaction to what is on screen and compare it to how they do it today. Modelled on a real demo
/// call where the SE stopped after every capability block and asked exactly that.
function repIsPresenting() {
  const recent = turns.slice(-8);
  if (recent.length < 4) return false;
  const wc = (t) => t.text.split(/\s+/).filter(Boolean).length;
  const repWords = recent.filter((t) => t.me && ["seller","presenter"].includes(turnSide(t))).reduce((n, t) => n + wc(t), 0);
  const custWords = recent.filter((t) => !["seller", "presenter"].includes(turnSide(t))).reduce((n, t) => n + wc(t), 0);
  return repWords >= 120 && custWords < 45;
}

/// Is a demo under way, whoever is driving it? Channel alone cannot tell you: on a call where the
/// rep is the listener, the demo narration arrives on the customer channel. Screen-driving language
/// is the reliable signal, and it decides one thing only: never offer to book a demo during one.
const DEMO_NARRATION = /\b(?:i'?ll (?:show|jump|pull)|let me show you|i'?m going to show|i want to show you|if (?:we|i) click|go ahead and click|on my screen|this dashboard|these dashboards|this page|jump into (?:our|the)|walk you through (?:our|the))\b/i;
let demoSeen = false;
function demoInProgress() {
  // Latches. By the end of a call the last turns are scheduling chatter, so a sliding window says
  // "no demo" again — and the close went straight back to offering one to people who had just sat
  // through it. Once they have seen it, the next step is never another demo.
  if (!demoSeen && turns.slice(-12).filter((t) => DEMO_NARRATION.test(t.text)).length >= 2) demoSeen = true;
  return demoSeen;
}

function coachGuidance() {
  const covered = pack.elements.filter((e) => settledCoverage(e.id) !== "open").map((e) => e.label);
  const asked = [...shownCues.slice(-8), ...turns.filter(t => turnSide(t) === "seller" && /\?/.test(t.text)).slice(-6).map(t => t.text)].slice(-10);
  const parts = [purposeGuidance(sessionPurpose), valueGuidance(callNotes(turns, turnSide))];
  parts.push(discoveryGuidance());
  if (repIsPresenting()) {
    // Observed on a real demo: the coach kept generating fresh discovery probes while the rep was
    // mid-feature, and even pitched "in a demo you'll see..." during the demo. What a strong SE
    // actually does at that moment is stop and ask how this compares to what they do today.
    parts.push(`THE REP IS MID-DEMO. They have been presenting and the customer has barely spoken.`
      + ` The customer's last turn is a backchannel ("okay", "mm-hmm"). Mid-demo that is EXPECTED and is`
      + ` NOT a reason to stay silent — the silence rule does not apply here. Return exactly one question.`
      + ` Anchor it on what they told you EARLIER in the call, before the demo began.`
      + ` Do NOT open a new discovery thread and do NOT offer to book a demo — one is happening.`
      + ` Your next_question is a CHECKPOINT on what is on screen right now. Ask how it COMPARES to`
      + ` the way they do it today: "How does this compare to the way you search logs now?",`
      + ` "How does your team handle that today?", "What would this replace in your current process?".`
      + ` Ask for their reaction to what they just saw, not for new facts.`
      + ` Avoid a yes/no check ("does this seem helpful?") — on a real call those returned "yes, it`
      + ` would definitely help" and nothing more, while the comparison form drew out how they work today.`);
  }
  if (covered.length) parts.push(`Already established (do not re-probe): ${covered.join(", ")}.`);
  if (asked.length) parts.push(`Already asked (never repeat or reword): ${asked.map((q) => `"${q}"`).join("  ")}.`);
  if (phase() === "close") {
    const demoing = repIsPresenting() || demoInProgress();
    parts.push(`CLOSING PHASE. Do NOT ask another discovery question. Your ONE next_question is the CLOSE, in three beats: (1) play back the two or three problems they actually stated, in their own words; (2) preview what ${demoing ? "the next step" : "the demo"} gives their team back; (3) ask for the ${demoing ? "next step" : "meeting"} directly. Set "targets":"close".`
      + (demoing ? ` A demo is ALREADY HAPPENING on this call. Never say "in a demo you'll see" or offer to book one — propose the real next step instead (a sizing exercise, a scoped trial, a follow-up with the people who have to approve it).` : ""));
    return parts.join("\n");
  }
  const d = delivery();
  const lastCust = [...turns].reverse().find((t) => !t.me)?.text;
  if (lastCust && d.talkRatio <= 55 && !repIsPresenting()) {
    parts.push(`BRIDGE: stay with their current thread. Use their concrete nouns directly in the question, without a quoted preamble or "You mentioned" opener. Their last words: "${lastCust.slice(0, 200)}".`);
  }
  if (d.talkRatio > 55 && youWords + custWords > 60) {
    parts.push(`DELIVERY: you are talking ${d.talkRatio}% of the time; the target is under 44%. Keep the next question concise and give them space to answer. Do not sacrifice relevance or a natural sentence just to meet a word count.`);
  }
  return parts.join("\n");
}

/// Until you have actually framed the call, the ONLY thing on screen is how to frame it. Four beats:
/// greet, name their problem back to them, say why you are asking before pitching, get permission.
/// Deterministic on purpose: this is the highest-value fifteen seconds of the call, and it is the
/// one thing reps reliably skip under nerves.
// A discovery call has three jobs in order: frame it, work the gaps, close for the next step. The
// phase is derived, never guessed, so the cue on screen is always the one that fits where you are.
// CLOSE_AFTER_MS is overridable so the phase transition is testable without waiting out a real call.
const CLOSE_AFTER_MS = Number(process.env.CLOSE_AFTER_MS || 11 * 60 * 1000);
function coveragePct() {
  const score = pack.elements.reduce((n, e) => {
    const st = settledCoverage(e.id);
    return n + (st === "done" ? 1 : st === "partial" ? 0.5 : 0);
  }, 0);
  return Math.round((score / pack.elements.length) * 100);
}
const OPEN_GRACE_MS = 120000;
function phase() {
  if (openingFramed !== true && Date.now() - callStart < OPEN_GRACE_MS && turns.length < 6) return "open";
  const explicitClose = turns.slice(-4).some((t) => /\b(?:wrap (?:up|this up)|before we (?:go|finish)|(?:agree on|confirm|discuss|land on|let\'s talk about) (?:the )?next steps|schedule (?:a|the|our) (?:meeting|call|follow.up|sizing)|out of time|have to (?:go|drop))\b/i.test(t.text));
  if (explicitClose || (process.env.CLOSE_AFTER_MS && Date.now() - callStart >= CLOSE_AFTER_MS)) return "close";
  return "discover";
}

/// The close is three beats and reps routinely drop the middle one: recap what they said, preview
/// what the demo will SHOW them, then ask. The outcome preview is what converts an agreement to
/// meet into an agreement to meet about something.
function closingCue() {
  return [{
    q: "Let me play back the priorities you shared so we can agree on the next step. What should we resolve together next?",
    tag: "close the call",
  }];
}

function openingCue() {
  if (phase() !== "open") return [];
  const problem = (prepContext || "").trim();
  // No prep means we do not know what this call is about, and a generic "I know you've got
  // challenges you're working through" is filler the rep would never read aloud. Show nothing.
  // With prep, the opener names THEIR problem back to them, which is the whole point of framing.
  if (!problem) return [];
  const who = customerName ? `${customerName}, ` : "";
  return [{
    q: `${who}thanks for making time. I understand you're running into ${problem.replace(/\.$/, "").slice(0, 160)}.`
     + ` Before I show you anything I want to understand what's happening on your side, so I don't waste your time on the wrong thing.`
     + ` Can I ask you questions for about ten minutes, then we'll land on next steps together?`,
    tag: "open the call",
  }];
}

/// A role has to look like a role. The LLM roster is extracted from a noisy transcript and will
/// happily stitch adjacent words into one: a real call produced "Nice Emailist" from the fragment
/// "...I see John on the line in IT and then if it's nice, like...". Requiring a recognisable title,
/// or a leading verb for descriptive roles ("runs security"), throws that away without losing
/// legitimate phrasings.
const ROLE_VERB = /^(?:runs?|leads?|heads?|manages?|owns?|oversees?|looks after)\b/i;
function plausibleRole(r) {
  const t = String(r || "").trim();
  if (t.length < 3 || t.length > 60) return "";
  if (ROLE_VERB.test(t)) return t;
  return new RegExp(`\\b(?:${ROLE_TITLES})\\b`, "i").test(t) ? t : "";
}

function microphoneName() {
  const names = new Set();
  for (const t of turns) {
    if (!t.me) continue;
    const c = clusterOfTurn.get(t.id);
    if (["mixed", "ambiguous"].includes(t.speakerStatus) || conflictedClusters.has(c)) continue;
    const name = introByTurn.get(t.id) || (c === repCluster ? clusterName.get(c) : null);
    if (name) names.add(name);
  }
  return names.size === 1 ? [...names][0] : null;
}

function custLabel(turn) {
  if (turn?.speakerStatus === "mixed") return "Mixed speakers";
  // A turn in which someone introduced themselves IS that person, whatever the diarizer managed.
  // This is the only attribution that still works with no voice embeddings at all, and without it a
  // second person's own introduction was rendered under the FIRST person's name.
  const manualCluster = turn && clusterOfTurn.get(turn.id);
  if (manualClusters.has(manualCluster) && clusterName.has(manualCluster)) return clusterName.get(manualCluster);
  if (turn?.speakerStatus === "ambiguous") return displayCluster(manualCluster) || (turn?.me ? "Microphone" : "Call audio");
  const intro = turn && turn.id !== undefined ? introByTurn.get(turn.id) : undefined;
  if (intro) return intro;
  const c = turn && turn.id !== undefined ? clusterOfTurn.get(turn.id) : undefined;
  if (c !== undefined && conflictedClusters.has(c)) return displayCluster(c) || (turn?.me ? "Microphone" : "Call audio");
  if (c !== undefined && clusterName.has(c)) return clusterName.get(c);   // this voice named itself
  // A different voice from one we HAVE named is, by definition, a different person. Falling through
  // to customerName here would put the named person's name on somebody else's words.
  if (c !== undefined && (clusterName.size > 0 || [...channelsOfCluster.values()].filter((ch) => ch.sys).length > 1)) return displayCluster(c) || "Call audio";
  return turn?.me ? (microphoneName() || preparedPeople().filter(p=>p.side==='seller' && /\b(?:rep|host|me|myself)\b/i.test(p.role)).map(p=>p.name).filter((n,i,a)=>a.length===1)[0] || "Microphone") : (displayCluster(c) || "Call audio");
}

function writeSession() {
  registerPrivateNames([...preparedPeople().map(p=>p.name),...roster.map(p=>p.name),...clusterName.values(),...introByTurn.values()]);
  questionLedger.reconcile(turns.map(t=>({...t,who:custLabel(t)})),turnSide);
  const covArr = pack.elements.map((e) => ({ name: e.label, status: settledCoverage(e.id) }));
  const score = covArr.reduce((s, c) => s + (c.status === "done" ? 1 : c.status === "partial" ? 0.5 : 0), 0);
  const session = {
    callId: process.env.SALESPILOT_CALL_ID || null,
    callPurpose: sessionPurpose,
    competition: competitiveSignals(turns.map(t=>({...t,who:custLabel(t)})),turnSide),
    consent: process.env.SALESPILOT_CONSENT_CONFIRMED_AT ? {confirmedAt:process.env.SALESPILOT_CONSENT_CONFIRMED_AT,method:"operator attestation; not proof of customer consent",noticeVersion:"2026-10-01",processingMode:process.env.SALESPILOT_CALL_PROCESSING_MODE || (process.env.SALESPILOT_LOCAL_ONLY==='1'?'local':'circuit')} : null,
    title: "Discovery — live session",
    subtitle: customerName
      ? `${pack.name} · ${customerName}${customerRole ? ` — ${customerRole}` : ""}`
      : `${pack.name} · ${(firstCust || (prepContext ? "Prepared for your next call" : "live call")).slice(0, 42)}`,
    framework: pack.name,
    coveragePct: Math.round((score / covArr.length) * 100),
    // Label the speaker at WRITE time, not when the turn was created. The name usually arrives a few
    // turns after someone starts talking, and baking "Customer" into each turn left every earlier
    // line saying "Customer" for the rest of the call. Deriving it here relabels the whole
    // transcript retroactively the moment the name is known. Two or more people on their side and we
    // genuinely cannot tell who spoke, so it stays "Customer".
    turns: turns.map((t) => ({ ...t, side: turnSide(t), clusterId: clusterOfTurn.get(t.id) ?? null, who: custLabel(t), ...(t.voiceFragments?{voiceFragments:t.voiceFragments.map(f=>({...f,who:f.cluster!=null?clusterName.get(f.cluster)||displayCluster(f.cluster)||"Call audio":"Overlapping or uncertain speech"}))}:{}) })),
    coverage: covArr,
    performance: performanceSnapshot(),
    coverageEvidence: partialEvidence(turns,turnSide),
    coverageDetails: coverageDetails(pack,settledCoverage,partialEvidence(turns,turnSide)),
    customerQuestions: questionLedger.items,
    coachProgress: questionLedger.open.some(q=>q.status==='searching') ? {state:'searching',message:'Searching documentation for a customer question.'} : coachProgress,
    nextq: (() => {
      const outstanding = questionLedger.open;
      if(outstanding.length && !(turns.at(-1)?.coachQ && !turns.at(-1)?.questionId)){const latest=outstanding.at(-1);return [{q:latest.kind==='clarify' ? 'Clarify: '+(turns.find(t=>t.questionId===latest.id)?.coachQ||latest.q) : latest.status==='searching'?'Searching documentation for: '+latest.q:latest.status==='ready'?'A sourced answer is ready for: '+latest.q:latest.status==='needs_confirmation'?'Needs confirmation: '+latest.q:'Unanswered: '+latest.q,tag:'Customer question',reason:`${outstanding.length} unresolved. Review in Answers; mark answered or defer explicitly.`}];}
      const latestCustomer = [...turns].reverse().find(t => !['seller','presenter'].includes(turnSide(t)));
      if (latestCustomer?.coachIntent === 'answer' && !latestCustomer.questionId && liveAnswer) {
        return [{q: liveAnswer.status === 'searching' ? 'Answer their product question first. Searching official documentation…' : liveAnswer.status === 'grounded' || liveAnswer.status === 'answered' ? 'Answer their product question using the sourced answer below.' : 'Resolve their product question first. Check the answer and source status below.',tag:'Answer',reason:'Do not pivot into discovery while their question is unresolved.'}];
      }
      if (livePartialCue && !audioActivity.blocked(turns.at(-1))) return [{ q: livePartialCue, tag: "…" }];
      const ph = phase();
      const live = [...nextqDedup.values()].filter((v) => {
        const t = v.raw?.targets;
        return !t || settledCoverage(t) !== "done";   // drop cues for ground already covered
      });
      // Three rewordings of one question is noise, not choice. Keep the newest, then only cues that
      // are genuinely different from the ones already on screen.
      const coached = [];
      for (const v of live.slice().reverse()) {
        if (coached.length >= 1) break;
        if (coached.some((c) => similarity(c.q, v.q) >= 0.6)) continue;
        coached.push({ q: v.q, tag: v.tag, reason: v.raw?.why || null });
      }
      if (ph === "open") return coached.length ? coached : openingCue();
      if (ph === "close") return coached.length ? coached : closingCue();
      return coached;
    })(),
    phase: phase(),
    followups,
    notes: callNotes(turns.map(t => ({...t, who: custLabel(t),clusterId:clusterOfTurn.get(t.id)??null})), turnSide),
    recap,
    nextSteps,
    customerName,
    customerRole,
    roster: [
      ...roster.map(p => ({...p, side: p.side || "customer"})),
      ...[...participantByTurn.values()].filter(p => p.side === "seller").filter((p,i,a)=>a.findIndex(x=>x.name===p.name)===i),
    ],
    mentionedPeople: mentionedPeople(turns.map(t => ({...t, who: custLabel(t)})), [...roster, ...participantByTurn.values()]),
    speakers: [...channelsOfCluster].filter(([c])=>clusterName.has(c)||manualClusters.has(c)||supportedCluster(c)>=2).map(([clusterId]) => ({
      clusterId, needsReview:conflictedClusters.has(clusterId), label: conflictedClusters.has(clusterId) ? (displayCluster(clusterId) || "Call audio") : (clusterName.get(clusterId) || displayCluster(clusterId) || "Unconfirmed speaker"), organization: organizationOfCluster.get(clusterId) || "", side: clusterId === repCluster ? "seller" : (sideOfCluster.get(clusterId) || "unknown")
    })),
    delivery: delivery(),
    audioWarning: audioWarning(),
    audioDiagnostics:{duplicatesRemoved:echoMicCopy+echoCustCopy,recentDuplicates:echoEvents.filter(e=>Date.now()-e.at<30000).length},
    // Scored over the CUSTOMER's words only. What the rep says is not evidence of anything: an SE
    // who mentions Enterprise Security four times would otherwise generate a signal for it.
    solutions: solutionSignals(customerEvidence()),
    opportunities: opportunities(turns.map(t=>({...t,who:custLabel(t)})), turnSide),
    liveAnswer,
    answerHistory,
    engineError,
  };
  mkdirSync(dirname(outPath), { recursive: true });
  const tmp = `${outPath}.tmp`;
  writeFileSync(tmp, JSON.stringify(session, null, 2), {mode:0o600});
  renameSync(tmp, outPath); // atomic for the app's reader
  process.stdout.write("@@updated@@\n");
}

const execFileAsync = promisify(execFile);
const GHOST = `${process.env.HOME}/go/bin/ghost`;

// Serialize local-LLM work so calls don't thrash one Ollama — but keep TWO lanes: coaching/recap
// on one, customer-question answers on the other, so an answer never waits behind an in-flight
// coaching turn or recap. (With a hosted provider the lanes run truly in parallel.)
let coachChain = Promise.resolve();
let answerChain = Promise.resolve();
function serialLLM(fn, lane = "coach") {
  const prev = lane === "answer" ? answerChain : coachChain;
  const run = prev.then(fn, fn);
  const settled = run.then(() => {}, () => {});
  if (lane === "answer") answerChain = settled; else coachChain = settled;
  return run;
}

// Detect a question by MEANING, not punctuation. Speech-to-text drops the question mark constantly,
// and real customers rarely open with an interrogative. Measured against ten realistic customer
// questions, the original (a "?" or a sentence-initial wh-word) caught one of them. The misses were
// tag questions ("...right"), embedded ones ("curious how long..."), imperative requests ("talk to me
// about pricing"), and "does THAT" (the auxiliary list only had it/your/the).
// Resolve only the latest technical request from readable reference evidence.
async function answerFromDocs(q, reqId, query = q, questionId = null) {
  if (answerInFlight) { pendingQ = { q, reqId, query, questionId }; return; } // supersede: keep only the newest
  answerInFlight = true;
  const competitive = query.startsWith("Splunk Core versus ");
  const answerCategory = competitive ? "competition" : "product";
  const answerStarted = performance.now();
  const controller = new AbortController();
  activeAnswerController = controller;
  const answerTimer = setTimeout(()=>controller.abort(new DOMException("Live answer deadline","TimeoutError")),20000);
  try {
    const lookupStarted = performance.now();
    const [hits, docs, pricing] = await abortable(Promise.all([search(query, 5), competitive ? competitiveSources(query) : searchSplunkDocs(query, 4), competitive ? Promise.resolve([]) : publicPricingSources(query)]),controller.signal);
    recordTiming("documentLookup",performance.now()-lookupStarted);
    const official = [...docs, ...pricing];
    if (reqId !== questionSeq) return;
    const refs = competitive ? competitionReferences(hits,official) : references(hits, official, query);
    const context = refs.map(r => `[${r.id}] ${r.title || r.source}\nSource: ${r.source}\n${r.text}`).join("\n\n");
    const recent = turns.slice(-4).map(t => t.text).join("\n");
    const raw = context ? await serialLLM(() => callQuality(competitive ? competitiveAnswerPrompt : answerPrompt,
      `Recent conversation (context, not evidence):\n${recent}\n\nReferences:\n${context}\n\nQuestion: ${q}`, 400, true, {task:"answer",signal:controller.signal,timeoutMs:15000}), "answer") : "";
    if (reqId !== questionSeq) return;
    const grounded = groundedAnswer(raw, refs, q);
    const result = competitive ? validateCompetitiveAnswer(grounded,refs,query) : grounded;
    if(result && questionId){const item=questionLedger.items.find(q=>q.id===questionId);if(item)recordTiming("questionToSourcedAnswer",Date.now()-item.createdAt);}
    saveAnswer({ q, questionId, category:answerCategory, diagnostics:{readableReferences:refs.length,officialReferences:official.length,validation:result?"accepted":refs.length?"unsupported-or-rejected":"no-readable-evidence"}, ...(result || { answer: "I need to confirm that detail before giving you a firm answer. I will follow up with the relevant documentation.", sources: [] }), status: result ? "grounded" : "unverified" });
    writeSession();
  } catch (e) {
    console.error(`[serve] rag error: ${e.message}`);
    if (reqId === questionSeq) {
      saveAnswer({ q, questionId, category:answerCategory, answer: "I cannot check the documentation right now. I will confirm this and follow up.", sources: [], status: "unverified" });
      writeSession();
    }
  } finally {
    clearTimeout(answerTimer);
    if(activeAnswerController===controller)activeAnswerController=null;
    recordTiming("liveAnswer",performance.now()-answerStarted,reqId===questionSeq?"completed":"superseded");
    if(questionId && questionLedger.items.find(q=>q.id===questionId)?.status==='searching')questionLedger.lookup(questionId,'needs_confirmation');
    answerInFlight = false;
    if (pendingQ) { const p = pendingQ; pendingQ = null; answerFromDocs(p.q, p.reqId, p.query,p.questionId); } // run the latest pending
  }
}

// Resolve customer identity with a real model (async, off the live loop). Authoritative over the
// instant regex guess, since it reads the whole conversation and tolerates messy transcription.
async function refineIdentity() {
  if(coachBusy || pendingCoachTurn || !roster.some(p=>!p.role)) return;
  const epoch = frameworkEpoch;
  try {
    const custText = customerEvidence();
    if (custText.trim().length < 10) return;
    const res = await extractIdentityAI(custText);
    if (epoch !== frameworkEpoch) return;
    const people = (Array.isArray(res.people) ? res.people : [])
      .filter((p) => p && typeof p.name === "string" && /[A-Za-z]{2,}/.test(p.name) && p.name.length <= 40)
      // stripTail here too: the LLM path was keeping "SED at Splunk" where the regex path would have
      // dropped the company. plausibleRole then discards anything that is not a role at all.
      .map((p) => ({ name: p.name.trim(), role: titleCaseRole(plausibleRole(stripTail((p.role || "").trim().slice(0, 60)))), decisionMaker: !!p.decision_maker }));
    if (!people.length) return;
    const known = new Set(turns.filter(t=>!["seller", "presenter"].includes(turnSide(t)) && !["mixed", "ambiguous"].includes(t.speakerStatus)).map(t=>introByTurn.get(t.id)).filter(Boolean));
    const groundedPeople = people.filter(p=>known.has(p.name));
    if (!groundedPeople.length) return;
    for (const p of groundedPeople) upsertRoster(p.name, p.role, p.decisionMaker);
    // Primary contact for the header/label: the decision-maker if named, else the first person.
    const primary = groundedPeople.find((p) => p.decisionMaker) || groundedPeople[0];
    customerName = primary.name;
    if (primary.role) customerRole = primary.role;   // already cleaned when the roster was built
    if (people.some((p) => p.decisionMaker) && /\b(?:i own the budget|i sign off|i approve|i have (?:the )?final say)\b/i.test(custText)) { confirmed.add("economic_buyer"); coverage.economic_buyer = "done"; }
    writeSession();
  } catch (e) { console.error(`[serve] identity refine error: ${e.message}`); }
}

// Clean up a committed turn's ASR in the BACKGROUND (CIRCUIT, off the local coach), then update the
// record + rolling context + the live display. Never blocks the live loop; identical for both speakers.
const CORRECT_MIN_MS = Number(process.env.CORRECT_MIN_INTERVAL_MS ?? 8000); // <0 disables (rely on turbo alone)
let lastCorrectAt = 0;
async function correctTurnAsync(turn, rawText, me) {
  // large-v3-turbo already produces accurate turns, so correction is now light-touch insurance, not a
  // per-turn call. Debounce it (default 8s) to cut CIRCUIT volume + free-tier rate-limit risk.
  if (CORRECT_MIN_MS < 0 || coachBusy || pendingCoachTurn || !/\b(?:spelunk|sock two|legacy sim|med pick)\b/i.test(rawText)) return;
  const now = Date.now();
  if (now - lastCorrectAt < CORRECT_MIN_MS) return;
  lastCorrectAt = now;
  try {
    const fixed = await correctTranscript(rawText);
    if (!fixed || fixed === rawText) return;
    turn.text = fixed;
    rebuildTranscript(); // so names/recap use the clean text
    writeSession();
    process.stdout.write(`@@correct@@ ${JSON.stringify({ orig: rawText, text: fixed })}\n`); // update the live display
  } catch (e) { console.error(`[serve] correct error: ${e.message}`); }
}

// Lightweight running summary — fires every few turns, in the background, never blocks the coach.
async function runningRecap() {
  const epoch = frameworkEpoch;
  if (recapInFlight || coachBusy || pendingCoachTurn || attributionTasks.size) return;
  recapInFlight = true;
  try {
    const sys =
`Summarize this sales call SO FAR in 2-3 sentences: the customer's situation, their pain, and what
you've learned. Plain, concrete, grounded in what was said. Output ONLY the summary — no JSON, no preamble.`;
    // Recap goes to the QUALITY model (CIRCUIT when configured) — better summaries, and it's off the
    // local coach so it never competes with live coaching.
    const full = await callQuality(sys, `Call so far:\n${coachTranscript()}`, 300, null, {task:"recap"});
    if (full && epoch === frameworkEpoch) { recap = full.trim(); writeSession(); }
  } catch (e) {
    console.error(`[serve] running-recap error: ${e.message}`);
  }
  recapInFlight = false;
}

// Name a call by who/what it was about, then archive it so it isn't lost when the next call starts.
function sessionName() {
  // Label calls by WHO they were with. The old fallbacks (a truncated recap sentence, or the first
  // thing the customer said) produced unusable names like "The provided transcript consists of song
  // lyrics ra" in the Past Calls menu. A clean "Untitled call" beats a misleading fragment.
  if (customerName) return customerName;
  if (roster.length) return roster[0].name;
  return "Untitled call";
}
function archiveSession() {
  try {
    if (!turns.length) return; // nothing to keep
    const dir = resolve(dirname(outPath), "history");
    mkdirSync(dir, { recursive: true });
    const now = new Date();
    const ts = now.toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const slug = sessionName().replace(/[^a-z0-9]+/gi, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "call";
    const session = JSON.parse(readFileSync(outPath, "utf8"));
    session.name = sessionName();
    session.archivedAt = now.toISOString();
    const archivePath=resolve(dir, `${ts}_${slug}_${process.pid}.json`);
    writeFileSync(archivePath+'.tmp', JSON.stringify(session, null, 2),{mode:0o600});
    renameSync(archivePath+'.tmp',archivePath);
  } catch (e) {
    console.error(`[serve] archive error: ${e.message}`);
  }
}

async function makeRecap() {
  if (!turns.some(turn => String(turn.text || "").trim())) {
    recap = null;
    nextSteps = [];
    return;
  }
  if (!customerEvidence().trim()) {
    recap = "No customer statements were captured. There is not enough information to summarize their needs.";
    nextSteps = [];
    return;
  }
  try {
    const sys =
`You are summarizing a live sales discovery call for the rep who ran it. Return ONLY JSON:
{ "recap": "3-4 sentences: the customer's situation, the pain, and what you learned",
  "next_steps": ["a specific next step", "..."] }
Be concrete and grounded in what was actually said. Include only next steps agreed to in the transcript; use an empty array if none were agreed. Do not judge the opportunity or recommend CRM changes without explicit transcript evidence. Do not invent needs, decisions, commitments, or customer opinions.`;
    const out = parse(await callQuality(sys, `Call transcript:\n${coachTranscript()}`, 500, true));
    if (!out || typeof out.recap !== "string" || !out.recap.trim()) throw Error("Recap provider returned no usable summary");
    recap = out.recap.trim(); nextSteps = Array.isArray(out.next_steps) ? out.next_steps : [];
  } catch (e) {
    engineError = "Recap unavailable. Your transcript is saved; review it or retry the recap.";
    console.error(`[serve] recap error: ${e.message}`);
  }
}

/// One pass of the coach against the current transcript, writing the cue onto `turn`.
/// coachGuidance() carries the forced next element, the bridge, the delivery steer and the close.
let coachBusy = false;
let activeCoachController = null;
let pendingCoachTurn = null;
const attributionTasks = new Set();
const attributionByTurn = new Map();
let coachSettleTimer = null;
function scheduleCoach(turn) {
  if(turn.coachIntent && turn.coachIntent !== 'explore' && !turn.coachCheckpoint)return;
  if(!currentCoachTurn(turn,turns.at(-1))) return;
  pendingCoachTurn = turn;
  coachProgress={state:'generating',message:'Generating a contextual follow-up.'};
  writeSession();
  activeCoachController?.abort(new DOMException("Newer customer context", "AbortError"));
  clearTimeout(coachSettleTimer);
  coachSettleTimer=setTimeout(drainCoach,Number(process.env.COACH_SETTLE_MS || 120));
}
function drainCoach() {
  if (coachBusy) return;
  coachBusy = true;
  (async () => {
    try {
      while (pendingCoachTurn) {
        const latest = pendingCoachTurn;
        pendingCoachTurn = null;
        if(!currentCoachTurn(latest,turns.at(-1)))continue;
        await new Promise(resolve=>setTimeout(resolve,Math.max(0,Number(process.env.COACH_SETTLE_MS || 120)-(Date.now()-latest.receivedAt))));
        if(pendingCoachTurn || !currentCoachTurn(latest,turns.at(-1)))continue;
        await runCoach(latest);
      }
    } finally { coachBusy = false; }
  })().catch(e => console.error(`[serve] coach scheduler: ${e.message}`));
}

async function runCoach(turn) {
  const controller = new AbortController();
  activeCoachController = controller;
  const started = performance.now();
  let passOutcome = "completed";
  const timer = setTimeout(() => controller.abort(new DOMException("Live coach deadline", "TimeoutError")), Number(process.env.COACH_PASS_TIMEOUT_MS || 10000));
  const contextTurnId = turns.at(-1)?.id;
  const epoch = frameworkEpoch;
  try {
    coachProgress={state:'generating',message:'Generating a contextual follow-up.'};
    livePartialCue = null;
    // Mid-demo the customer is only back-channelling, so let the checkpoint anchor on what they
    // told us before the demo started rather than on "okay".
    const opts = {...(repIsPresenting() ? {anchorWindow:40} : {}), evidenceTranscript:customerEvidence(), signal:controller.signal};
    const obj = parse(await serialLLM(() => {
      controller.signal.throwIfAborted();
      return fastTier(pack, coachTranscript(), coachGuidance(), delta => {
        if (!controller.signal.aborted && contextTurnId === turns.at(-1)?.id && epoch === frameworkEpoch) onCoachDelta(delta);
      }, opts);
    }));
    await (attributionByTurn.get(turn.id) || Promise.resolve());
    controller.signal.throwIfAborted();
    if (["mixed","ambiguous"].includes(turn.speakerStatus) || (["seller","presenter"].includes(turnSide(turn)) && !turn.coachCheckpoint)) {coachProgress={state:"listening",message:"Listening for the next clear customer thought."};writeSession();return;}
    livePartialCue = null;
    if (obj && epoch === frameworkEpoch && contextTurnId === turns.at(-1)?.id) {
      coachProgress={state:'listening',message:'Listening for the next useful discovery detail.'};
      engineError = null; // model reachable
      if (obj.coverage) { coverage = { ...coverage, ...obj.coverage }; recordCoverage(obj.coverage); }
      for (const id of confirmed) coverage[id] = "done"; // never regress a confirmed fact
      const q = Array.isArray(obj.next_questions) ? obj.next_questions[0] : null;
      if (q?.text && !pendingCoachTurn && (sessionPurpose!=="discovery" || discoverySafeCue(q.text))) {
        const rendered = renderCue(q);
        if (isRepeatOfShownCue(rendered)) {
          /* say nothing rather than say it again; the clock keeps running */
        } else {
          turn.coachTarget = labelOf(q.targets);
          turn.coachQ = rendered;
          recordTiming("turnToCue",Math.max(0,Date.now()-turn.receivedAt));
          if(Number.isFinite(turn.endedAt))recordTiming("speechEndToCue",Math.max(0,Date.now()-turn.endedAt*1000));
          recordTiming("transcriptToCue",Date.now()-turn.receivedAt);
          shownCues.push(rendered);
          nextqDedup.clear();
          nextqDedup.set(q.text, { q: rendered, tag: labelOf(q.targets), raw: q });
          turnsSinceCue = 0;
        }
      }

    }
  } catch (e) {
    passOutcome = "error";
    if (controller.signal.aborted && controller.signal.reason?.name === "AbortError") return;
    coachProgress={state:'failed',message:'Could not generate a follow-up. Transcript capture continues.'};
    engineError = controller.signal.reason?.name === "TimeoutError"
      ? "Coaching is taking too long. Transcript and notes continue."
      : "Coaching is temporarily unavailable. Transcript and notes continue.";
    console.error(`[serve] fast-tier error: ${e.message}`);
  } finally {
    clearTimeout(timer);
    recordTiming("coachPass",performance.now()-started,controller.signal.aborted ? controller.signal.reason?.name === "AbortError" ? "cancelled" : "timeout" : passOutcome);
    if(activeCoachController === controller) activeCoachController = null;
    writeSession();
  }
}

// A strong SE stops after each capability block and asks how what is on screen compares to how the
// customer does it today. That could never happen here: coaching only ever ran on CUSTOMER turns, so
// through a demo — where the customer says "okay" and "mm-hmm" and nothing else clears the substance
// gate — the coach either went quiet or fired a stale probe off something said minutes earlier.
// Coach the REP's own turn once they have been presenting for a stretch.
const CHECKPOINT_AFTER_TURNS = 4;
function maybeCheckpoint(turn) {
  if (!["seller", "presenter"].includes(turnSide(turn))) return;
  if (process.env.COACH_DEBUG) {
    console.error(`[checkpoint] queue=${turnQueue.length} sinceCue=${turnsSinceCue} presenting=${repIsPresenting()}`);
  }
  if (turnQueue.length) return;
  if (turnsSinceCue < CHECKPOINT_AFTER_TURNS) return;
  if (sessionPurpose==="discovery" || !repIsPresenting() || ["mixed","ambiguous"].includes(turn.speakerStatus)) return;
  turn.coachCheckpoint = true;
  scheduleCoach(turn);
}


// Prep remains context, not evidence of discovery completed on this call.
// Do not block incoming audio on a speculative pre-call inference.
if (prepContext) {
  for(const p of preparedPeople()){upsertRoster(p.name,p.role);Object.assign(roster.find(x=>x.name===p.name),p);}
}
writeSession(); // reset the review window to a clean live session immediately
if (arg("prep-preview")) process.exit(0); // one-shot: just wrote the prep-prefilled session, done
// Keep answers on the LATEST docs — but re-index in the BACKGROUND so it never freezes the coach at
// call open. search() tolerates an old/missing index and hot-reloads when the rebuild lands.
if (process.env.SALESPILOT_OFFLINE !== "1") indexIfStale().then((r) => { if (r.reindexed) console.error(`[serve] re-indexed ${r.chunks} chunks from ${r.files} files`); }).catch((e) => console.error(`[serve] reindex error: ${e.message}`));
// Warm authentication without generating a dummy question or loading a local model.
warmCoach().catch(() => {});
const rl = createInterface({ input: process.stdin });
console.error(`[serve] ${pack.name} — persistent coach ready.`);

for await (const line of rl) {
  const s = line.trim();
  if (!s) continue;
  let seg;
  try { seg = JSON.parse(s); } catch { continue; }
  if (!seg || typeof seg !== "object" || Array.isArray(seg)) continue; // null/array/scalar → skip (no crash)

  if(seg.cmd === 'question' && Number.isInteger(seg.id)) {
    if(questionLedger.resolve(seg.id,seg.status))writeSession();
    continue;
  }
  if (seg.cmd === "activity") {
    const wasBlocked=audioActivity.blocked(turns.at(-1));
    if(!audioActivity.update(seg))continue;
    const blocked=audioActivity.blocked(turns.at(-1));
    if(blocked){livePartialCue=null;}
    if(!seg.active)setTimeout(()=>writeSession(),1800);
    if(wasBlocked!==blocked){
      writeSession();
      const latest=turns.at(-1);
      if(!blocked && latest && !latest.coachQ && !["mixed","ambiguous"].includes(latest.speakerStatus)) {
        if(!["seller","presenter"].includes(turnSide(latest)) && isSubstantive(latest.text) && !referenceRequest(latest.text,turns.slice(-5,-1)))scheduleCoach(latest);
        else maybeCheckpoint(latest);
      }
    }
    continue;
  }
  if (seg.cmd === "recap") {
    // Turns are queued now, so the last few may still be in flight. Let them land before recapping,
    // or the recap would summarise a transcript that is missing the end of the call.
    while (draining || turnQueue.length) await new Promise((r) => setTimeout(r, 50));
    await Promise.allSettled([...attributionTasks]);
    activeCoachController?.abort(new DOMException("Call ended","AbortError")); pendingCoachTurn=null; clearTimeout(coachSettleTimer);
    questionSeq++; activeAnswerController?.abort(new DOMException("Call context ended or corrected","AbortError")); pendingQ = null; questionLedger.end(); if(liveAnswer?.status==="searching")liveAnswer=answerHistory.at(-1)||null; questionLedger.end(); await makeRecap(); writeSession(); archiveSession(); continue;
  }

  if (seg.cmd === "speaker" && Number.isInteger(seg.clusterId) && channelsOfCluster.has(seg.clusterId)) {
    if (["seller", "customer", "unknown"].includes(seg.side)) {
      sideOfCluster.set(seg.clusterId, seg.side);
      manualClusters.add(seg.clusterId);
      conflictedClusters.delete(seg.clusterId);
      for (const t of turns) if (clusterOfTurn.get(t.id) === seg.clusterId && t.speakerStatus === "ambiguous") delete t.speakerStatus;
      if (typeof seg.name === "string" && seg.name.trim() && seg.name.trim().length <= 60) clusterName.set(seg.clusterId, seg.name.trim());
      const removedNames = new Set(turns.filter(t=>clusterOfTurn.get(t.id)===seg.clusterId).map(t=>introByTurn.get(t.id)).filter(Boolean));
      if (seg.side === "seller") roster = roster.filter(p=>!removedNames.has(p.name));
      else if (seg.name?.trim()) {
        roster = roster.map(p=>removedNames.has(p.name) ? {...p,name:seg.name.trim(),side:seg.side,nameEvidence:'Manual speaker correction'} : p);
        upsertRoster(seg.name.trim());Object.assign(roster.find(p=>p.name===seg.name.trim()),{side:seg.side,nameEvidence:'Manual speaker correction'});
      }
      questionSeq++; activeAnswerController?.abort(new DOMException("Call context ended or corrected","AbortError")); pendingQ = null; liveAnswer = null;
      coverage = {}; confirmed.clear(); covHistory.clear(); nextqDedup.clear();
      frameworkEpoch++;
      rebuildTranscript();
      writeSession();
      const latest = [...turns].reverse().find(t => !["seller", "presenter"].includes(turnSide(t)));
      if (latest) scheduleCoach(latest);
    }
    continue;
  }

  // Switch methodology mid-call. The rail repaints with the new pack IMMEDIATELY; re-coaching the
  // transcript so far is a background job. It used to await that LLM call before writing anything,
  // so the switch appeared to do nothing for as long as the queue plus the call took.
  if (seg.cmd === "framework") {
    const p = PACKS[String(seg.value || "").toLowerCase()];
    if (p) {
      pack = p;
      coverage = {}; confirmed.clear(); nextqDedup.clear(); covHistory.clear();
      writeSession();                       // <- new elements on screen now, all "open"
      activeCoachController?.abort(new DOMException("Framework changed", "AbortError"));
      ++frameworkEpoch;
      const latest = [...turns].reverse().find(t => !["seller","presenter"].includes(turnSide(t)));
      if(latest) scheduleCoach(latest);
    }
    continue;
  }

  // Switch the coaching cue style mid-call (Autopilot / nudge / gap). Re-render the current
  // SAY-NEXT list in the new style with no LLM call; future turns pick it up automatically.
  if (seg.cmd === "mode") {
    const m = String(seg.value || "").toLowerCase();
    if (CUE_MODES.has(m)) {
      cueMode = m;
      for (const v of nextqDedup.values()) { if (v.raw) v.q = renderCue(v.raw); }
      writeSession();
    }
    continue;
  }

  // Turns are QUEUED, not handled inline. The readline loop must never block on an LLM call:
  // while it awaited one, every later line (including a methodology switch) sat unread in the
  // stdin queue behind it, which is what made a mid-call switch look like it did nothing.
  turnQueue.push(seg);
  drainTurns();
}

// stdin closed: the call is over. The sidecar is a live child holding open pipes, which keeps node's
// event loop alive on its own — without this the engine never exits and every call leaves a
// serve.mjs plus a python behind it.
await drainTurns();
await Promise.allSettled([...attributionTasks]);
while (coachBusy) await new Promise(resolve => setTimeout(resolve, 50));
diarizeShutdown();

/// Turns are processed strictly in order, one at a time, so coverage never races itself.
function timeAlignedEcho(previous, current, nowMs) {
  if ([previous.startedAt, previous.endedAt, current.startedAt, current.endedAt].every(Number.isFinite)) {
    return previous.startedAt <= current.endedAt + 1 && current.startedAt <= previous.endedAt + 1;
  }
  return nowMs - (previous.receivedAt ?? previous.at ?? nowMs) < ECHO_WINDOW_MS;
}

async function handleTurn(seg) {
const capturedText = (seg.text || "").trim();
const repName=microphoneName();
const text=normalizeRepGreeting(capturedText,repName,[...clusterName.values()]);
if(seg.speaker==='you'){const name=addressedName(text);if(name)addressedIdentity={name,at:Date.now()};}
if (!text) return;

const me = seg.speaker === "you" || seg.speaker === "me";

const nowMs = Date.now();
recentTurns = recentTurns.filter((r) => nowMs - r.at < ECHO_WINDOW_MS);
const wordCountForEcho = normWords(text).length;
turnsSeen++;

const exactShortEcho = wordCountForEcho > 0 && wordCountForEcho < MIN_ECHO_WORDS &&
  recentTurns.some((r) => !r.me && timeAlignedEcho(r, seg, nowMs) && nowMs - r.at < SHORT_ECHO_MS &&
                          normWords(r.text).join(" ") === normWords(text).join(" "));
if (me && !MIRROR_FRAME.test(text) &&
    ((wordCountForEcho >= MIN_ECHO_WORDS &&
      recentTurns.some((r) => !r.me && timeAlignedEcho(r, seg, nowMs) && bleedSimilarity(r.text, text) >= ECHO_SIM)) || exactShortEcho)) {
  // Mic turn echoing a customer turn we already have = speaker bleed. Drop it entirely:
  // don't record it, don't show it, don't coach on it.
  echoMicCopy++; recordEcho('mic');
  console.error("[serve] dropped mic echo");
  process.stdout.write(`@@drop@@ ${JSON.stringify({ text })}\n`);
  return;
}
if (!me && wordCountForEcho >= MIN_ECHO_WORDS) {
  // The customer copy is authoritative. Retract EVERY earlier mic fragment it matches — the bleed
  // usually arrives SPLIT across several partial mic turns, so removing only the first left the
  // rest on screen still attributed to the rep.
  for (let i = turns.length - 1; i >= 0; i--) {
    if (turns[i].me && timeAlignedEcho(turns[i], seg, nowMs) && !MIRROR_FRAME.test(turns[i].text) && bleedSimilarity(turns[i].text, text) >= ECHO_SIM) {
      const removed = turns.splice(i, 1)[0];
      // Un-count it: these words were banked as YOURS on an earlier iteration, and leaving them
      // there would inflate the very talk-ratio number this is here to measure.
      youWords -= removed.text.split(/\s+/).filter(Boolean).length;
      fillerCount -= countFillers(removed.text);
      longestYouWords = turns.reduce((m, t) => t.me ? Math.max(m, t.text.split(/\s+/).filter(Boolean).length) : m, 0);
      rolling = rolling.replace(`me: ${removed.text}\n`, "");
      echoCustCopy++; recordEcho('system');
      console.error("[serve] retracted mic echo");
      process.stdout.write(`@@drop@@ ${JSON.stringify({ text: removed.text })}\n`);
    }
  }
  recentTurns = recentTurns.filter((r) => !(r.me && timeAlignedEcho(r, seg, nowMs) && bleedSimilarity(r.text, text) >= ECHO_SIM));
}
recentTurns.push({ me, text, at: nowMs, startedAt: seg.startedAt, endedAt: seg.endedAt });

if(Number.isFinite(seg.endedAt)&&Number.isFinite(seg.finalizedAt)&&seg.finalizedAt>=seg.endedAt && seg.finalizedAt-seg.endedAt<120)recordTiming("speechEndToTranscript",(seg.finalizedAt-seg.endedAt)*1000);
const wc = text.split(/\s+/).filter(Boolean).length;
if (me) {
  youWords += wc;
  fillerCount += countFillers(text);
  if (wc > longestYouWords) longestYouWords = wc;
  if (openingFramed === null && wc >= 12) openingFramed = looksFramed(text);   // judge the real opener
} else custWords += wc;

clock += 4 + Math.round(text.split(/\s+/).length / 3);
rolling += `${me ? "me" : "cust"}: ${text}\n`;
const turn = { id: ++turnSeq, receivedAt: nowMs, me, side: me ? "seller" : (DEMO_NARRATION.test(text) && wc >= 20 ? "presenter" : "unknown"), who: me ? "You" : "Customer", time: mmss(clock), text, coachTarget: null, coachQ: null };
if(text!==capturedText){turn.rawText=capturedText;turn.nameCorrection="Direct greeting normalized using the rep’s self-introduction";}
const previousIntroTurn=turns.at(-1);
const splitIntroduction=previousIntroTurn && previousIntroTurn.me===me && /\b(?:my name(?: is|’s|'s)|i am|i'm|this is)[. …-]*$/i.test(previousIntroTurn.text) && !['mixed'].includes(previousIntroTurn.speakerStatus) && (!Number.isFinite(seg.startedAt)||!Number.isFinite(previousIntroTurn.endedAt)||seg.startedAt-previousIntroTurn.endedAt<15);
const identityText=splitIntroduction?previousIntroTurn.text.replace(/[. …-]+$/,'')+' '+text:text;
const participant = participantIntro(identityText, me);
if (participant) {
  participantByTurn.set(turn.id, participant);
  if (participant.side !== "unknown") turn.side = participant.side;
}
const extractedIntro = participant?.side === "seller" ? null : extractIdentity(identityText, me && participant?.side !== "customer");
let selfIntro = participant?.name || extractedIntro;
if (!selfIntro && participant) selfIntro = participant.name;
if (customerName) customerName = reconcileName(customerName);
if (selfIntro) {selfIntro = reconcileName(selfIntro);if(!me && participant?.side!=="seller")customerName=selfIntro;}
if (selfIntro) {
  introByTurn.set(turn.id, selfIntro);

  const prepared=preparedPeople().find(p=>p.name===selfIntro);
  if(prepared){participantByTurn.set(turn.id,{...participant,...prepared,nameEvidence:'Self-introduction matched call prep'});if(prepared.side!=='unknown')turn.side=prepared.side;}
  if (participant?.side !== "seller" && (!me || participant?.side === "customer")) {
    upsertRoster(selfIntro, selfIntro === customerName ? customerRole : null);
    const person=roster.find(p=>p.name===selfIntro);if(person){person.side=prepared?.side||participant?.side||'unknown';person.nameEvidence='Self-introduction';}
  }
}
if (Number.isFinite(seg.startedAt)) {
  turn.startedAt = seg.startedAt;
  turn.endedAt = Number.isFinite(seg.endedAt) ? seg.endedAt : seg.startedAt;
  turn.time = mmss(Math.max(0, Math.round(seg.startedAt - callStart / 1000)));
}
if(Number.isFinite(seg.endedAt)) recordTiming("captureToEngine",Math.max(0,nowMs-seg.endedAt*1000));
clearTimeout(coachSettleTimer); pendingCoachTurn=null;
activeCoachController?.abort(new DOMException("Newer transcript context", "AbortError"));
turns.push(turn);
turns.sort((a, b) => (a.startedAt ?? callStart / 1000 + a.id) - (b.startedAt ?? callStart / 1000 + b.id));
rebuildTranscript();
turnsSinceCue++;    // both speakers: a demo is nearly all rep turns, and the clock has to run there too
const attributionStarted = performance.now();
// Tiny backchannels/fillers are not enough linguistic evidence to establish a new voice.
// Self introductions still get diarized, even when brief. Consume every skipped snapshot.
const voiceEligible = wc >= 4 || introByTurn.has(turn.id) || participantByTurn.has(turn.id);
const recentChannelTurn=[...turns].reverse().find(t=>t.id!==turn.id&&t.me===me);
const continuityPrevious=recentChannelTurn?{...recentChannelTurn,clusterId:clusterOfTurn.get(recentChannelTurn.id)??null}:null;
const channelClusters=new Set([...channelsOfCluster].filter(([c,ch])=>me?ch.mic:ch.sys).map(([c])=>c));
if(seg.wav && !voiceEligible){try{unlinkSync(seg.wav);}catch{}}
const applyVoice = r=>{turn.speakerScore=r.score??null;turn.attributionReason=r.reason||'voice';if(["mixed","ambiguous"].includes(r.reason)){turn.speakerStatus=r.reason;const fragments=attributedFragments(seg.words,r.windows,turn.text);if(fragments.length)turn.voiceFragments=fragments;writeSession();return;}const c=r.cluster??continuationCluster(turn,continuityPrevious,channelClusters,r.reason);if(c!=null){turn.attributionSource=r.cluster!=null?'voice':'short continuation';attachCluster(turn.id,c,me);}};
const attribution = seg.wav && voiceEligible ? diarize(seg.wav).then(applyVoice).catch(() => {}) : Promise.resolve().then(()=>applyVoice({cluster:null,reason:'short'}));
attributionTasks.add(attribution);
attributionByTurn.set(turn.id,attribution);
attribution.finally(() => { attributionTasks.delete(attribution); if(seg.wav) recordTiming("speakerAttribution",performance.now()-attributionStarted); });
writeSession();     // transcript + name on screen NOW; coaching fills in below when it lands

const plan = dialoguePlan(text, turns.filter(t => t.id !== turn.id).slice(-16), {mode:sessionPurpose});
const docRequest = plan.request || null;
coachProgress = {state:'listening',message:plan.kind==='listen'?'Listening while they finish their thought.':'Listening for a useful follow-up.'};
turn.coachIntent = plan.kind;
turn.presentationNarration = /\b(?:one of my engineers|our engineers|smaller group conversations|pass it (?:over|on) to)\b/i.test(text) || /\b(?:a slide to show|this slide|this roadmap|this is where.{0,35}(?:app|dashboard)|let me show you|on my screen|we(?:’|')?re going to (?:pop into|install the common information model))\b/i.test(text);
if(turn.presentationNarration && !me)turn.side='presenter';
if (!me || turn.side === "customer") {
  if (!firstCust) firstCust = text;
  if (!["seller", "presenter"].includes(turn.side) && docRequest) {
    if (!followupsSet.has(text)) { followupsSet.add(text); followups.push(text); }
    const tracked=questionLedger.add({...turn,who:custLabel(turn)},docRequest,docRequest.category==="competition"?"competition":"answer");
    turn.questionId=tracked.id;questionLedger.lookup(tracked.id,'searching');
    liveAnswer = { questionId:tracked.id,q: text, category:docRequest.category || "product", answer: "Searching official documentation and your knowledge library…", sources: [], status: "searching" };
    writeSession();
    nextqDedup.clear();
    activeAnswerController?.abort(new DOMException("Newer product question","AbortError"));
    const requestId = ++questionSeq;
    attribution.then(() => {
      if (requestId !== questionSeq) return;
      if (["mixed", "ambiguous"].includes(turn.speakerStatus) || ["seller", "presenter"].includes(turnSide(turn))) { liveAnswer = null; writeSession(); return; }
      answerFromDocs(text, requestId, docRequest.query,tracked.id);
    });
  }
  // Skip coaching on trivial turns ("yeah", "okay", "mm-hmm") — spending a 3s LLM call on a
  // 2-word backchannel is what let the serial queue fall behind during a live call.
  const wordCount = text.split(/\s+/).filter(Boolean).length;
  // Coalesce: if more turns are already waiting, this cue would be stale before it rendered. Ingest
  // the turn and let the NEWEST one do the coaching — one good current cue beats a queue of old ones.
  // Holding also skips the model call entirely, which is most of the per-turn latency and cost.
  // A turn carrying real signal always gets through, so nothing important waits for the cadence.
  if (plan.customerQuestion) {const tracked=questionLedger.add({...turn,who:custLabel(turn)},plan.customerQuestion,'respond');turn.questionId=tracked.id;}
  if (plan.kind === 'clarify') {const tracked=questionLedger.add({...turn,who:custLabel(turn)},{query:text},'clarify');turn.questionId=tracked.id;}
  if (plan.question && !['mixed','ambiguous'].includes(turn.speakerStatus)) {
    attribution.then(() => {
      if (turns.at(-1)?.id !== turn.id || ['mixed','ambiguous'].includes(turn.speakerStatus) || ['seller','presenter'].includes(turnSide(turn))) return;
      turn.coachQ = plan.question; turn.coachTarget = plan.kind === 'redirect' ? 'Discovery focus' : plan.kind === 'clarify' ? 'Clarify' : (plan.target || 'Situation');
      nextqDedup.clear(); nextqDedup.set(plan.question,{q:plan.question,tag:turn.coachTarget,raw:{text:plan.question,targets:plan.targets,why:plan.reason}});
      shownCues.push(plan.question); recordTiming("transcriptToCue",Date.now()-turn.receivedAt); writeSession();
    });
  }
  const holdingCue = turnsSinceCue < CUE_HOLD_TURNS && !isHighSignal(text);
  if (!["seller", "presenter"].includes(turn.side) && plan.kind === 'explore' && !plan.question && !holdingCue && wordCount >= 4 && isSubstantive(text) && turnQueue.length === 0) {
    // Generate while voice analysis runs; validate attribution before publishing.
    scheduleCoach(turn);
  }
}


attribution.then(() => maybeCheckpoint(turn));
writeSession();
correctTurnAsync(turn, text, me).catch(() => {}); // async ASR cleanup on CIRCUIT — never blocks the live path
if (!me) {
  sinceRecap++; if (sinceRecap >= 6) { sinceRecap = 0; runningRecap(); } // fire-and-forget; every 6 turns so it doesn't jam live coaching
  // Once there's enough of the customer talking, let a real model (CIRCUIT when configured) resolve
  // name/role/authority — far more robust than regex on noisy audio. Async: zero live-loop latency.
  custTurns++; if (custTurns === 3 || custTurns === 8) refineIdentity();
}
}

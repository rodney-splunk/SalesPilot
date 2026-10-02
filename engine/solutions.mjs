// Splunk solution signals.
//
// The purpose here is NOT to pick a product. It is to notice what the customer keeps returning to
// and hand the SE a question that would TELL them, while staying honest that discovery is not done.
//
// Three rules keep this from becoming happy-ear selling:
//   1. One keyword is never enough. Signals are weighted and have to accumulate past a threshold,
//      so a passing mention of "security" proves nothing.
//   2. The probes are DIAGNOSTIC, not leading. "When an alert fires, what happens next?" is a good
//      question whether the answer turns out to be ES, SOAR, more people, or nothing at all.
//      A question like "would risk-based alerting help you?" assumes the conclusion and is banned.
//   3. Competing areas stay visible. When two areas are close, the tool says it is still open
//      instead of picking, because that IS the finding at that point in the call.
//
// None of this touches SAY NEXT. Methodology coaching stays the primary cue; this is a side channel
// the SE can ignore.

const SURFACE_AT = 5;      // weighted score before an area is worth mentioning at all
// Contested is a RATIO, not a fixed gap. At 11 versus 7 both areas are plainly live even though the
// difference is 4, while at 30 versus 26 the same gap means something quite different. Proportion is
// what actually tracks "the call has not distinguished these yet".
const CONTESTED_RATIO = 0.6;

export const SOLUTIONS = [
  {
    id: "es", name: "Enterprise Security", area: "security operations",
    signals: [
      { w: 4, re: /\b(correlation search(es)?|risk[- ]based alerting|notable event|risk score|detection(s)? we (wrote|built))\b/i },
      { w: 3, re: /\b(SIEM|security operations cent(er|re)|\bSOC\b)\b/i },
      { w: 3, re: /\b(MITRE|ATT&CK|threat hunt(ing)?|threat detection)\b/i },
      { w: 2, re: /\b(alert fatigue|false positives?|tier (one|1) analyst|triage)\b/i },
      { w: 1, re: /\b(analysts?|incident|investigat(e|ion))\b/i },
    ],
    probes: ["When an alert fires, what happens next?",
             "How do you decide which alerts get worked first?"],
  },
  {
    id: "soar", name: "SOAR", area: "response automation",
    signals: [
      { w: 2, re: /\b(security analysts?|incident response|security investigation)\b/i },
      { w: 4, re: /\b(playbook|runbook|SOAR|orchestrat(e|ion)|auto[- ]?remediat)/i },
      { w: 3, re: /\b(same steps every time|repetitive|manual(ly)? (run|do|check)|copy and paste)\b/i },
      { w: 2, re: /\b(swivel chair|too many tools|context switch)\b/i },
      { w: 2, re: /\b(analyst time|headcount|can'?t hire|burn(ing|t) out)\b/i },
    ],
    probes: ["How much of that response is the same steps every time?",
             "Walk me through what a person actually does on one of those."],
  },
  {
    id: "itsi", name: "ITSI", area: "service reliability",
    signals: [
      { w: 4, re: /\b(service health|ITSI|glass table|KPI|service dependenc|business service)\b/i },
      { w: 3, re: /\b(major incident|war room|bridge call|MTTR|mean time to (resolve|restore))\b/i },
      { w: 2, re: /\b(which service|blast radius|who('s| is) affected|downstream)\b/i },
      { w: 2, re: /\b(outage|degrad(ed|ation)|availability|SLA)\b/i },
    ],
    probes: ["When something breaks, how do you work out which service is affected?",
             "Who gets pulled in on a major incident, and how long does that take?"],
  },
  {
    id: "apm", name: "APM and Observability Cloud", area: "application performance",
    signals: [
      { w: 4, re: /\b(APM|distributed trac(e|ing)|OpenTelemetry|OTel|span|microservice)/i },
      { w: 3, re: /\b(latency|p9[59]|slow (checkout|page|api|response)|time ?out)\b/i },
      { w: 3, re: /\b(user experience|customer facing|checkout|conversion|cart)\b/i },
      { w: 2, re: /\b(kubernetes|k8s|container|serverless|lambda)\b/i },
    ],
    probes: ["When a user says it is slow, how do you find where the time is going?",
             "How far can you follow one request through the system today?"],
  },
  {
    id: "infra", name: "Infrastructure Monitoring", area: "infrastructure health",
    signals: [
      { w: 3, re: /\b(host|node|VM|virtual machine|cluster) (health|metrics|monitoring)\b/i },
      { w: 3, re: /\b(cloud (cost|spend|migration)|AWS|Azure|GCP) /i },
      { w: 2, re: /\b(capacity|utilis|utiliz|saturation|scaling)\b/i },
      { w: 2, re: /\b(agent(s)? on every|deploy(ing)? agents|coverage gap)\b/i },
    ],
    probes: ["What are you using to see host and container health today?",
             "Where do you have blind spots in that estate?"],
  },
  {
    id: "data", name: "Data management and ingest control", area: "data and cost control",
    signals: [
      { w: 4, re: /\b(edge processor|ingest action|route (the )?data|mask(ing)?|hash(ing|ed)?|de[- ]identif)/i },
      { w: 4, re: /\b(PII|personally identifiable|sensitive (data|field)|GDPR|HIPAA|PCI)\b/i },
      { w: 3, re: /\b(ingest (cost|volume)|license (cost|usage)|data volume|retention|too much data)\b/i },
      { w: 2, re: /\b(index(ing)? everything|what we keep|drop (the )?logs?|noisy sources?)\b/i },
    ],
    probes: ["What decides today what gets indexed and what gets dropped?",
             "Where does sensitive data land before anyone can act on it?"],
  },
];

/// Score the transcript so far. Returns areas above the surfacing bar, strongest first, each with
/// the phrases that actually earned it, so the SE can judge the evidence rather than trust a label.
export function solutionSignals(transcript) {
  const text = String(transcript || "");
  const scored = [];
  for (const sol of SOLUTIONS) {
    let score = 0; const hits = new Set();
    for (const s of sol.signals) {
      const m = text.match(new RegExp(s.re.source, s.re.flags.includes("g") ? s.re.flags : s.re.flags + "g"));
      if (!m) continue;
      // Repeats count, but with heavy diminishing returns: saying "SOC" nine times is one fact.
      const uniq = new Set(m.map((x) => x.toLowerCase().trim()));
      score += s.w + Math.min(uniq.size - 1, 2);
      for (const x of uniq) hits.add(x.trim());
    }
    if (score > 0) scored.push({ id: sol.id, name: sol.name, area: sol.area, score, probes: sol.probes, evidence: [...hits].slice(0, 6) });
  }
  scored.sort((a, b) => b.score - a.score);
  const surfaced = scored.filter((s) => s.score >= SURFACE_AT).slice(0, 3);
  if (!surfaced.length) return { status: "open", areas: [], note: null };
  // Two strong areas that are close together mean the call has not distinguished them yet. Saying so
  // is more useful than picking one, and it is what stops the SE funnelling on the first thing heard.
  const contested = surfaced.length > 1 && (surfaced[1].score / surfaced[0].score) >= CONTESTED_RATIO;
  return {
    status: contested ? "contested" : "leaning",
    areas: surfaced,
    note: contested
      ? "More than one area is live. Not enough yet to tell them apart."
      : "One area is running ahead. Still worth testing before you commit to it.",
  };
}

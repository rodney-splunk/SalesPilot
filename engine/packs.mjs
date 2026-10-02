// Framework packs (machine-readable source for the harness).
// Human-readable YAML lives in ../frameworks/. Keep them in sync.
// A pack = goals to uncover. Example questions are STYLE ONLY, never shown verbatim.

export const PACKS = {
  meddic: {
    name: "MEDDPICC",
    elements: [
      { id: "identify_pain",   label: "Identify Pain",   covered_when: "A specific, felt business pain (not a feature wish) is surfaced." },
      { id: "metrics",         label: "Metrics",         covered_when: "A quantified business impact/economic value is established (cost, risk, time, revenue)." },
      { id: "champion",        label: "Champion",        covered_when: "An internal advocate with influence who sells on your behalf is identified." },
      { id: "competition",     label: "Competition",     covered_when: "Alternatives (incumbents, other vendors, do-nothing) are known." },
      { id: "decision_criteria", label: "Decision Criteria", covered_when: "The customer's explicit criteria for choosing a solution are known." },
      { id: "decision_process",  label: "Decision Process",  covered_when: "The steps, stakeholders, and timeline to a decision are mapped." },
      { id: "economic_buyer",  label: "Economic Buyer",  covered_when: "The person who controls budget / final yes is identified, ideally engaged." },
      { id: "paper_process",   label: "Paper Process",   covered_when: "Procurement / legal / security review steps and timing are understood." },
    ],
  },
  spin: {
    name: "SPIN",
    elements: [
      { id: "situation",   label: "Situation",   covered_when: "Current state/context established (tools, team, process, scale)." },
      { id: "problem",     label: "Problem",     covered_when: "A specific difficulty or dissatisfaction is surfaced." },
      { id: "implication", label: "Implication", covered_when: "The cost/impact/risk of the problem is quantified or felt." },
      { id: "need_payoff", label: "Need-payoff", covered_when: "The customer articulates the value of solving it." },
    ],
  },
  challenger: {
    name: "Challenger",
    elements: [
      { id: "warmer",            label: "Warmer",            covered_when: "A credible hypothesis about the customer's world is established before pitching." },
      { id: "reframe",           label: "Reframe / Teach",   covered_when: "An insight that reframes how the customer sees their problem has landed." },
      { id: "rational_drowning", label: "Rational Drowning", covered_when: "The cost/consequence of the status quo is quantified and made undeniable." },
      { id: "emotional_impact",  label: "Emotional Impact",  covered_when: "The customer personally feels the problem — their story, their stakes." },
      { id: "value_prop",        label: "Value Proposition", covered_when: "A solution path tied to the reframe is introduced." },
      { id: "take_control",      label: "Take Control",      covered_when: "The SE is guiding next steps with constructive tension on process/price." },
    ],
  },
};

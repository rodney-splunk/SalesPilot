export const callPurpose = value => value === 'discovery' ? 'discovery' : 'standard';
export function demoRequest(text) {
 const t=String(text||'').trim();
 if(/\b(?:don.t|do not|not|no need|without)\b.{0,25}\b(?:demo|demonstration)\b|\b(?:last|previous|earlier|yesterday|already|recorded)\b.{0,30}\bdemo\b|\bdemo\b.{0,30}\b(?:last week|yesterday|was helpful|next week|later|next call)\b/i.test(t))return false;
 const request=/\b(?:can|could|would|will|want|like|need|hoping|expecting)\b|\b(?:show me|show us|give us|let.s)\b/i.test(t);
 const explicit=/\b(?:demo|demonstration|demonstrate it|demonstrate this|demonstrate that)\b/i.test(t);
 const show=/\b(?:show (?:me|us)|share (?:your|the) screen|walk.{0,8}through)\b/i.test(t);
 const now=/\b(?:today|now|right now|on this call|during this call|your screen)\b/i.test(t);
 const pronoun=/\bshow (?:me|us) (?:this|that|it)\b/i.test(t);
 return request && (explicit || (show && (now || pronoun))) && !/\bdemographic\b/i.test(t);
}
export function discoveryRedirect(text) {
 const focus=/\b(?:firewall|palo alto)\b/i.test(text)?'your firewall investigation workflow':/\b(?:alert|triage|siem)\b/i.test(text)?'how your team investigates an alert':/\b(?:ingest|data|collect)\b/i.test(text)?'how your data is collected today':'the workflow you most want to improve';
 return `Let’s use today to understand ${focus}, so we can tailor a useful demo as a next step. Where would you want that demo to make the biggest difference?`;
}
export function purposeGuidance(mode) {
 return callPurpose(mode)==='discovery' ? 'DISCOVERY-ONLY SESSION. No demonstration is planned for today. Keep coaching in discovery: current workflow, technical friction, business impact, personal effort and success criteria. If a demo is requested, acknowledge it warmly and explain that today’s discovery will shape a tailored next-step demo. Ask what it should prove. Do not offer to open a dashboard, run a demo, share a screen or execute a proof of concept now. Technical and competitive questions still deserve a concise sourced answer before returning to discovery. Do not invent a commitment or meeting date. Past demos may be discussed as evidence; this is not a reason to redirect historical discussion.' : '';
}
export function discoverySafeCue(text) {
 return !/\b(?:let me|i(?:’|')?ll|we can|let(?:’|')?s|i can)\s+(?:show|demo|demonstrate|share my screen|open.{0,15}dashboard|run.{0,15}demo)\b|\b(?:book|schedule) (?:a |the )?demo (?:now|today)\b/i.test(text||'');
}

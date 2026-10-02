// Conservative partial coverage from literal customer statements; never claims completion.
export function partialEvidence(turns,sideOf=t=>t.side||'unknown'){
 const result={};
 const patterns={situation:/\b(?:we (?:use|have|are|run|ingest)|we.?ve got|head of (?:security|it)|i (?:manage|oversee|lead)|our (?:team|analysts|environment)|cash registers|routers|switches)\b/i,problem:/\b(?:don.?t have anything capturing|no (?:visibility|monitoring)|too many|miss(?:es)? (?:alerts|incidents)|wait.{0,40}(?:hours|team)|manual|delay|struggl|can.?t)\b/i,implication:/\b(?:miss.{0,25}sla|lost revenue|costs? us|work weekends|business at risk|contract at risk|fail.{0,25}audit|delays? our|instead of.{0,30}(?:planned|work))\b/i,need_payoff:/\b(?:we (?:need|want) to|we.?re.{0,20}looking for|maintain.{0,15}uptime|without waiting|reduce.{0,20}(?:time|risk|downtime))\b/i,metrics:/\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\.\d+)?\s*(?:hours?|minutes?|days?|gigs?|gb|tb|percent|%)\b/i,competition:/\b(?:looking at|considering|evaluating).{0,50}(?:datadog|elastic|sentinel|qradar)\b/i};
 for(const t of turns){if(!['customer','unknown'].includes(sideOf(t))||t.me||['mixed','ambiguous'].includes(t.speakerStatus)||/\b(?:hypothetically|for example|let.?s say)\b/i.test(t.text))continue;
 const statements=String(t.text).split(/(?<=[.!?])\s+/).filter(s=>!s.endsWith("?")&&!/^(?:what|which|how|is|are|do|does|can|could)\b/i.test(s.trim())).join(" ");
 for(const [id,pattern]of Object.entries(patterns))if(pattern.test(statements))result[id]={turnId:t.id,quote:t.text,speakerUnconfirmed:sideOf(t)==="unknown"};}
 if(result.problem)result.identify_pain=result.problem;return result;
}

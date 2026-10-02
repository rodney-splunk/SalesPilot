// Mentions are context, never evidence that someone spoke or attended.
export function mentionedPeople(turns, participants = []) {
 const known = new Set(participants.map(p => p.name.toLowerCase()));
 const people = new Map();
 for (const turn of turns) {
  const text = String(turn.text || '');
  if (/\b(?:for example|imagine|hypothetically)\b/i.test(text)) continue;
  const patterns = [
   /\b([A-Z][a-z]+(?: [A-Z][a-z]+)?)\s+(?:is|was)\s+(?:(?:the|our|your|a)\s+)?(?:(Splunk|Cisco)\s+)?(RSM|SE|account manager|solutions engineer|sales engineer|regional sales manager)\b(?:\s+(?:at|from|on|with)\s+(Splunk|Cisco))?/g,
   /\b([A-Z][a-z]+(?: [A-Z][a-z]+)?)\s+(?:did|ran|led|gave)\s+(?:(?:your|our|the)\s+)?(?:last|previous)\s+demo\b/g,
  ];
  for (let i=0;i<patterns.length;i++) for (const m of text.matchAll(patterns[i])) {
   const name=m[1];if(known.has(name.toLowerCase()) || ['He','She','They','We','You','Someone'].includes(name))continue;
   const inferred=i===1;
   const role=inferred?'Demo presenter':m[3];
   const organization=inferred?'':m[2]||m[4]||'';
   const entry={name,role,organization,inferred,attendance:'unconfirmed',quote:text,who:turn.who||'Unconfirmed speaker',turnId:turn.id ?? null};
   const prior=people.get(name.toLowerCase());
   if(!prior || (prior.inferred && !inferred))people.set(name.toLowerCase(),entry);
  }
 }
 return [...people.values()];
}

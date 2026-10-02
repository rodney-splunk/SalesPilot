import {completedThought} from './coach-timing.mjs';
import {noteFragments} from './note-fragments.mjs';
import { productContext } from "./product-context.mjs";
// Extractive call memory. No model rewrites numbers, units or customer statements.
const clean = text => String(text || '').replace(/\s+/g, ' ').trim();
const key = text => clean(text).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const words = text => new Set(key(text).split(' ').filter(w => w.length > 3));
const categories = [
 ['personal', /\b(?:currently leading|team members)\b|\b(?:my (?:team|role|job|goal|priority)|on.call|burn(?:ed|ing)? out|frustrat\w*|stress|weekend|late nights?|my time|personally|promotion|accountable)\b/i],
 ['business', /\b(?:business|revenue|cost|budget|sla|risk|compliance|audit|deadline|customer experience|lost|lose|loss|hours?|days?|weeks?|manual|delay|miss|impact|because|blocked|wait|waiting)\b/i],
 ['technical', /\b(?:soc|analysts?|consolidate|tooling)\b|\b(?:firewall|palo alto|fortinet|meraki|cisco|splunk|siem|logs?|data|gigs?|gb|tb|terabytes?|gigabytes?|ingest|retention|endpoints?|servers?|windows|linux|routers?|switches?|tools?|console|dashboard|alerts?|search|investigat\w*|integrat|pipeline|deploy|cloud|network|security|monitor|using|use|running)\b/i],
 ['outcomes', /\b(?:need|want|goal|success|hoping|ideally|better|improve|reduce|faster|priority|priorities|important)\b/i],
 ['next_steps', /\b(?:agree|agreed|let.?s|will send|will share|i.?ll send|i.?ll share|schedule|follow.up|next step|meet again)\b/i],
];
export function callNotes(turns, sideOf = t => t.me ? 'seller' : t.side || 'unknown') {
 turns = noteFragments(turns,sideOf);
 const seen = new Set(), notes = [];
 for (const turn of turns) {
  const side = sideOf(turn);
  if (['mixed','ambiguous'].includes(turn.speakerStatus) || ['seller','presenter'].includes(side)) continue;
  const text = clean(turn.text);
  if (!text || text.split(' ').length < 4) continue;
  // Quoted examples, product narration and questions are not customer facts.
  if (/\b(?:for example|let me show|you would say|you basically say|hypothetically|let.?s say)\b/i.test(text)) continue;
  const statements = text.split(/(?<=[.!?])\s+(?=[A-Z])/);
  for (let quote of statements) {
   quote = clean(quote);
   if (!completedThought(quote)) continue;
   if (quote.endsWith('?') || quote.split(' ').length < 4) continue;
   if (/\b(?:want|need|trying|try)\b.{0,35}\b(?:monitor|capture|collect|integrate)\s*$/i.test(quote)) continue;
   const tags = categories.filter(([,pattern]) => pattern.test(quote)).map(([id]) => id);
   if (!tags.length) continue;
   const normalized = `${side}:${turn.who || "unconfirmed"}:${key(quote)}`;
   if (seen.has(normalized)) continue;
   seen.add(normalized);
   const uncertainty = /\b(?:maybe|roughly|about|approximately|i think|not sure|probably|might)\b/i.test(quote);
   notes.push({id:`${turn.id ?? notes.length}-${notes.length}`,turnId:turn.id ?? null,quote,categories:tags,
    speaker:turn.who || (side === 'unknown' ? 'Unconfirmed speaker' : 'Customer'),
    voiceClusterId:turn.clusterId ?? null,sourceTurnIds:turn.sourceTurnIds||[turn.id],evidenceQuotes:turn.evidenceQuotes||[quote],provenance:'customer-stated',
    speakerUnconfirmed:side === 'unknown',tentative:uncertainty,
    context:productContext(quote,turns.slice(0,turns.indexOf(turn))),
    at:turn.time || null,startedAt:turn.startedAt ?? null,
    correction:/^(?:actually\b|correction\b|no[, ]+sorry\b)|\b(?:i meant|let me correct|scratch that)\b/i.test(quote)});
  }
 }
 // Only explicit, same-speaker corrections with the same quantity unit and topic
 // supersede an earlier claim. Keep both literal statements for audit/review.
 for (let i=0;i<notes.length;i++) {
  const newer=notes[i];if(!newer.correction)continue;
  const unit=newer.quote.match(/\b\d+(?:\.\d+)?\s*(gigs?|gb|gigabytes?|tb|terabytes?|hours?|days?|weeks?|minutes?)\b/i)?.[1]?.toLowerCase();
  if(!unit)continue;
  const family=u=>/^(gigs?|gb|gigabytes?)$/.test(u)?'gb':/^(tb|terabytes?)$/.test(u)?'tb':u.replace(/s$/,'');
  for(let j=i-1;j>=0;j--){const older=notes[j];
   const sameVoice=older.voiceClusterId!=null&&older.voiceClusterId===newer.voiceClusterId;
   if(older.speaker!==newer.speaker || ((older.speakerUnconfirmed || newer.speakerUnconfirmed)&&!sameVoice))continue;
   const oldUnit=older.quote.match(/\b\d+(?:\.\d+)?\s*(gigs?|gb|gigabytes?|tb|terabytes?|hours?|days?|weeks?|minutes?)\b/i)?.[1]?.toLowerCase();
   const shared=[...words(newer.quote)].filter(w=>words(older.quote).has(w)&&!['actually','roughly','about','meant','retain','retention','ingest','using','have','with','that','those','these','days','hours','weeks','minutes','gigs','gigabytes','terabytes',unit].includes(w));
   const period=q=>q.match(/\b(?:per|a|each) (day|week|month|year)\b/i)?.[1]?.toLowerCase();
   const compatiblePeriod=!(period(older.quote)&&period(newer.quote)&&period(older.quote)!==period(newer.quote));
   if(oldUnit && family(oldUnit)===family(unit) && shared.length>=2 && compatiblePeriod){older.supersededBy=newer.turnId;newer.correctsTurnId=older.turnId;break;}
  }
 }
 return notes;
}
export function callContext(turns, notes, prep = '', sideOf = t => t.me ? 'seller' : t.side || 'unknown') {
 const recent = turns.slice(-12);
 const topic = words(recent.slice(-5).map(t => t.text).join(' '));
 const recentIds = new Set(recent.map(t => t.id));
 const represented = new Set(notes.map(n=>n.turnId));
 const additional = turns.filter(t=>!recentIds.has(t.id) && !represented.has(t.id)
  && !['mixed','ambiguous'].includes(t.speakerStatus) && !['seller','presenter'].includes(sideOf(t)) && clean(t.text).split(' ').length >= 4 && !clean(t.text).endsWith('?')
  && !/\b(?:for example|let me show|you would say|you basically say|hypothetically|let.?s say)\b/i.test(t.text))
  .map(t=>({turnId:t.id,quote:clean(t.text),categories:[],speakerUnconfirmed:sideOf(t)==='unknown'}));
 const order = new Map(turns.map((t,i)=>[t.id,i]));
 const earlier = [...notes.filter(n=>!n.supersededBy && !recentIds.has(n.turnId)),...additional].sort((a,b)=>(order.get(a.turnId)||0)-(order.get(b.turnId)||0));
 const scored = earlier.map((n,index) => ({n,index,score:[...words(n.quote)].filter(w=>topic.has(w)).length*5
  + (n.categories.includes('outcomes') ? 3 : 0) + (/\d/.test(n.quote) ? 2 : 0)}));
 const selected = new Set(scored.sort((a,b)=>b.score-a.score||a.index-b.index).slice(0,22).map(x=>x.n));
 // Keep initial environment and each impact layer available, even during a long demo.
 for (const layer of ['technical','business','personal','outcomes','next_steps']) {
  const first = earlier.find(n=>n.categories.includes(layer)); if (first) selected.add(first);
 }
 const memory = earlier.filter(n=>selected.has(n)).map(n => `cust: ${n.quote}${n.speakerUnconfirmed ? ' [speaker role unconfirmed]' : ''}`).join('\n').slice(0,6000);
 const superseded=new Set(notes.filter(n=>n.supersededBy).map(n=>n.turnId));
 const corrections=notes.filter(n=>n.correctsTurnId!=null).slice(-8).map(n=>`Correction from turn ${n.correctsTurnId} to ${n.turnId}: ${n.quote}`).join('\n').slice(0,1000);
 const answered=turns.slice(0,-12).flatMap((t,i)=>sideOf(t)==='seller' && /\?\s*$/.test(t.text) && turns[i+1] && sideOf(turns[i+1])==='customer' && !['mixed','ambiguous'].includes(turns[i+1].speakerStatus) ? [`Asked: ${clean(t.text)} Answer: ${clean(turns[i+1].text)}${superseded.has(turns[i+1].id) ? ' [superseded; use explicit correction below]' : ''}`]:[]).slice(-8).join('\n').slice(0,2500);
 const tail = recent.map(t=>`${t.speakerStatus==='mixed' ? 'mixed speakers (not attributable)' : sideOf(t)==='seller' ? 'me' : sideOf(t)==='presenter' ? 'presenter' : 'cust'}: ${clean(t.text)}${superseded.has(t.id) ? ' [superseded by explicit customer correction; do not use as current fact]' : ''}`).join('\n').slice(-5000);
 return `${prep ? `Preparation (unconfirmed until the customer validates it):\n${prep.slice(0,1500)}\n` : ''}${memory ? `Earlier captured statements (literal evidence, not new speech):\n${memory}\n` : ''}${corrections ? `Explicit corrections (use the newer statement, retaining its uncertainty):\n${corrections}\n` : ''}${answered ? `Previously asked and answered (do not ask these again; deepen only if needed):\n${answered}\n` : ''}Recent conversation:\n${tail}`;
}
export function valueGuidance(notes) {
 return `Follow the current thread using open, probing and confirming moves. Do not march through qualification fields.\nExplore three impact layers when earned: technical (workflow and bottleneck), business (consequence and measurable outcome), personal (effect on this person's responsibilities and team). Never force that order or assume pain.\nStay with the concrete issue until the customer's answer is understood. Ask one natural follow-up, not three impact questions at once. If a fact was already given, use it rather than ask again. Confirm uncertainty before quantifying it.\nA demonstration is a conversation: connect what was just shown to their earlier workflow and invite comparison. Mention only capabilities actually shown in the transcript.\nPersonal impact should be respectful and specific, such as time taken from their team's other work; do not invent stress, career fears or emotional motives.\nCaptured impact evidence: ${['technical','business','personal'].map(layer=>`${layer}: ${notes.filter(n=>n.categories.includes(layer)).length ? 'statements available, use their words' : 'not established, do not presume'}`).join('; ')}.`;
}

import {completedThought} from './coach-timing.mjs';
export function noteFragments(turns,sideOf){const result=[];
 for(const t of turns){const p=result.at(-1);const unfinished=p&&(!completedThought(p.text)||/\b(?:monitor|capture|collect|integrate)\s*$/i.test(p.text));const same=p&&p.who&&p.who===t.who&&!/^(?:Unconfirmed|Uncertain|Mixed|You|Customer)/i.test(p.who)&&['customer','unknown'].includes(sideOf(p))&&sideOf(p)===sideOf(t)&&(sideOf(p)==='customer'||p.clusterId!=null&&p.clusterId===t.clusterId)&&!['mixed','ambiguous'].includes(p.speakerStatus)&&!['mixed','ambiguous'].includes(t.speakerStatus);
 const close=p&&(!(Number.isFinite(t.startedAt)&&Number.isFinite(p.endedAt))||t.startedAt-p.endedAt>=0&&t.startedAt-p.endedAt<20);
 if(unfinished&&same&&close&&!/[?]$/.test(t.text)&&!(p.sourceTurnIds?.length>=3))result[result.length-1]={...p,text:p.text.trim().replace(/(?:--|[—–])\s*$/,'').trim()+' '+t.text.trim(),endedAt:t.endedAt,sourceTurnIds:[...(p.sourceTurnIds||[p.id]),t.id],evidenceQuotes:[...(p.evidenceQuotes||[p.text]),t.text]};else result.push({...t});
 }return result;}

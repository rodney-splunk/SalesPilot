const normalized = s => String(s||'').toLowerCase().replace(/[^\p{L}\p{N}]+/gu,' ').trim();
export class QuestionLedger {
 constructor(){this.items=[];this.sequence=0;}
 add(turn,request,kind='answer'){
  const key=normalized(request.query||turn.text);
  let item=this.items.find(q=>!['answered','deferred'].includes(q.status)&&q.key===key&&q.speaker===turn.who);
  if(item){if(!item.turnIds.includes(turn.id))item.turnIds.push(turn.id);return item;}
  item={id:++this.sequence,key,q:turn.text,query:request.query||turn.text,speaker:turn.who||'Unconfirmed speaker',speakerUnconfirmed:turn.side==='unknown',turnIds:[turn.id],kind,status:'open',createdAt:Date.now(),updatedAt:Date.now()};this.items.push(item);return item;
 }
 lookup(id,status,answer){const q=this.items.find(q=>q.id===id);if(!q||['answered','deferred'].includes(q.status))return false;q.status=status;q.updatedAt=Date.now();if(answer)q.answer=answer;return true;}
 resolve(id,status){const q=this.items.find(q=>q.id===id);if(!q||!['answered','deferred','open'].includes(status))return false;q.status=status;q.updatedAt=Date.now();q.resolution='user-confirmed';return true;}
 reconcile(turns,sideOf){const byId=new Map(turns.map(t=>[t.id,t]));this.items=this.items.filter(q=>q.turnIds.some(id=>{const t=byId.get(id);return t&&!['mixed','ambiguous'].includes(t.speakerStatus)&&!['seller','presenter'].includes(sideOf(t))}));for(const q of this.items){const t=q.turnIds.map(id=>byId.get(id)).find(Boolean);if(t){q.speaker=t.who||q.speaker;q.speakerUnconfirmed=sideOf(t)==='unknown';}}}
 end(){for(const q of this.items)if(q.status==='searching')this.lookup(q.id,'needs_confirmation');}
 get open(){return this.items.filter(q=>!['answered','deferred'].includes(q.status));}
}
export function coverageDetails(pack,statusOf,evidence){return pack.elements.map(e=>({id:e.id,name:e.label,status:statusOf(e.id),quote:evidence[e.id]?.quote||null,turnId:evidence[e.id]?.turnId||null,speakerUnconfirmed:evidence[e.id]?.speakerUnconfirmed||false,criterion:e.covered_when,remaining:statusOf(e.id)==='done'?'Marked covered. Review the evidence before relying on it.':statusOf(e.id)==='partial'?`Validate the remaining detail: ${e.covered_when}`:e.covered_when}));}

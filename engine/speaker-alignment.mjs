// Never distribute words uniformly over audio: only real ASR timestamps may assign fragments.
export function attributedFragments(words,windows,expectedText=null){
 if(!Array.isArray(words)||!Array.isArray(windows))return [];
 const ordered=words.filter(w=>typeof w.word==='string'&&Number.isFinite(w.start)&&Number.isFinite(w.end)&&w.start>=0&&w.end>w.start).sort((a,b)=>a.start-b.start);
 const normalize=s=>s.normalize("NFC").replace(/\s+/g," ").trim();
 if(expectedText!==null&&normalize(ordered.map(w=>w.word).join(""))!==normalize(String(expectedText)))return [];
 const chunks=[];
 for(const word of ordered){
  const covering=windows.filter(w=>Number.isFinite(w.start)&&Number.isFinite(w.end)&&Math.max(0,Math.min(word.end,w.end)-Math.max(word.start,w.start))>=(word.end-word.start)*.8);
  const labels=new Set(covering.map(w=>w.cluster));
  const cluster=covering.length&&labels.size===1&&Number.isInteger(covering[0].cluster)?covering[0].cluster:null;
  const prior=chunks.at(-1);
  if(prior&&prior.cluster===cluster&&word.start-prior.end<.5){prior.text+=word.word;prior.end=word.end;}
  else chunks.push({cluster,start:word.start,end:word.end,text:word.word});
 }
 return chunks.map(c=>({...c,text:c.text.trim()})).filter(c=>c.text);
}

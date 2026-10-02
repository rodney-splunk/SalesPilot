// Local operational timings only. No transcript, prompts, account names or credentials.
const stages = new Map();
export function recordTiming(stage, elapsedMs, outcome = 'ok', model = null) {
 const ms=Number(elapsedMs);if(!Number.isFinite(ms)||ms<0)return;
 const bucket=stages.get(stage)||{count:0,outcomes:{},recent:[]};bucket.count++;bucket.outcomes[outcome]=(bucket.outcomes[outcome]||0)+1;bucket.recent.push({ms:Math.round(ms),outcome,...(model?{model}: {})});if(bucket.recent.length>64)bucket.recent.shift();stages.set(stage,bucket);
}
export function performanceSnapshot() {
 return Object.fromEntries([...stages].map(([name,b])=>{const sorted=b.recent.map(r=>r.ms).sort((a,c)=>a-c);const at=p=>sorted[Math.min(sorted.length-1,Math.ceil(sorted.length*p)-1)]??0;return [name,{count:b.count,outcomes:{...b.outcomes},p50Ms:at(.5),p95Ms:at(.95),last:b.recent.at(-1)}];}));
}
export function abortable(promise, signal) {
 if(!signal)return promise;
 if(signal.aborted){Promise.resolve(promise).catch(()=>{});return Promise.reject(signal.reason||new DOMException('Cancelled','AbortError'));}
 return new Promise((resolve,reject)=>{
  const abort=()=>reject(signal.reason||new DOMException('Cancelled','AbortError'));
  signal.addEventListener('abort',abort,{once:true});
  Promise.resolve(promise).then(resolve,reject).finally(()=>signal.removeEventListener('abort',abort));
 });
}

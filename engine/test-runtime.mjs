import assert from 'node:assert/strict';
import {mkdtempSync,copyFileSync,writeFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {pathToFileURL} from 'node:url';
const dir=mkdtempSync(join(tmpdir(),'salespilot-runtime-test-'));
for(const file of ['core.mjs','privacy.mjs','circuit.mjs','performance.mjs','coach-timing.mjs'])copyFileSync(new URL(file,import.meta.url),join(dir,file));
writeFileSync(join(dir,'.circuit.json'),JSON.stringify({client_id:'synthetic-only',client_secret:'synthetic-only',app_key:'synthetic-only',inference_url:'https://chat-ai.cisco.com',api_version:'synthetic-only'}),{mode:0o600});
process.on('exit',()=>rmSync(dir,{recursive:true,force:true}));
delete process.env.COACH_LOCAL;delete process.env.SALESPILOT_OFFLINE;
import {abortable,recordTiming,performanceSnapshot} from './performance.mjs';
process.env.PROVIDER='circuit';process.env.COACH_HOSTED_TIMEOUT_MS='40';process.env.COACH_LOCAL_TIMEOUT_MS='80';
let mode='healthy';const routes=[];let tokenCount=0;
globalThis.fetch=async (url,options={})=>{
 if(String(url).includes('/token')){tokenCount++;return Response.json({access_token:'synthetic-test-token',expires_in:3600});}
 const local=String(url).startsWith('http://localhost');const body=JSON.parse(options.body||'{}');routes.push({local,model:local?body.model:'hosted'});
 if(!local && mode==='error')return new Response('Synthetic outage',{status:503});
 if(mode==='hang' || (!local && mode==='hosted-hang'))return new Promise((resolve,reject)=>{options.signal.addEventListener('abort',()=>reject(options.signal.reason),{once:true});});
 return Response.json(local?{message:{content:'local'}}:{choices:[{message:{content:'hosted'}}]});
};
const {callCoach}=await import(pathToFileURL(join(dir,'core.mjs')));
assert.deepEqual(await Promise.all([callCoach('s','u',50,null),callCoach('s','u',50,null)]),['hosted','hosted']);assert.equal(tokenCount,1,'concurrent calls share one token refresh');
mode='hosted-hang';assert.equal(await callCoach('s','u',50,null),'local');assert.equal(routes.at(-1).model,'qwen2.5:7b','fallback actually uses local model under explicit circuit provider');
mode='healthy';assert.equal(await callCoach('s','u',50,null),'hosted');
mode='hang';const before=routes.length;const ac=new AbortController();const task=callCoach('s','u',50,null,null,{signal:ac.signal});setTimeout(()=>ac.abort(new DOMException('Superseded','AbortError')),5);await assert.rejects(task,{name:'AbortError'});assert.equal(routes.slice(before).filter(r=>r.local).length,0,'cancellation never triggers fallback');
mode='error';assert.equal(await callCoach('s','u',50,null),'local');assert.equal(await callCoach('s','u',50,null),'local');const count=routes.filter(r=>!r.local).length;assert.equal(await callCoach('s','u',50,null),'local');assert.equal(routes.filter(r=>!r.local).length,count,'repeated outage opens circuit breaker');
await assert.rejects(callCoach('s','u',50,null,null,{remoteOnly:true}),/503/,'comparison cannot silently substitute local model');
const pre=new AbortController();pre.abort();await assert.rejects(abortable(Promise.resolve('x'),pre.signal),{name:'AbortError'});
recordTiming('example',10);recordTiming('example',30,'cancelled');const snap=performanceSnapshot();assert.equal(snap.example.count,2);assert.equal(snap.example.p95Ms,30);assert.ok(!JSON.stringify(snap).includes('synthetic-test-token'));
console.log('PASS hosted success, bounded timeout, genuine local fallback, cancellation, outage breaker, strict model comparison and private timing metadata');

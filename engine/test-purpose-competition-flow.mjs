import {spawn} from 'node:child_process';import assert from 'node:assert/strict';import {mkdtempSync,readFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
async function run(localOnly){
 const dir=mkdtempSync(join(tmpdir(),'salespilot-purpose-')),file=join(dir,'session.json');
 const env={...process.env,SALESPILOT_OFFLINE:'1',COACH_LOCAL:'1',PROVIDER:'ollama',SALESPILOT_CALL_PURPOSE:'discovery',SESSION_FILE:file,PREP_FILE:join(dir,'absent'),SALESPILOT_RAG_INDEX:join(dir,'absent-index'),SALESPILOT_DOCS_SERVER:join(dir,'absent-docs'),CORRECT_MIN_INTERVAL_MS:'-1'};
 if(localOnly)env.SALESPILOT_LOCAL_ONLY='1';else delete env.SALESPILOT_LOCAL_ONLY;
 const p=spawn(process.execPath,['--import',new URL('../tests/engine/mock-purpose-competition.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname],{env,stdio:['pipe','ignore','pipe']});let error='';p.stderr.on('data',d=>error+=d);const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file))}catch{return null}};async function until(fn){for(let i=0;i<250;i++){const s=read();if(s&&fn(s))return s;await sleep(25)}throw Error(error)}
 async function send(text){const n=read().turns.length;p.stdin.write(JSON.stringify({speaker:'customer',text})+'\n');return until(s=>s.turns.length>n)}
 try{
  await until(()=>true);assert.equal(read().callPurpose,'discovery');
  await send('We have inconsistent dashboards and an unreliable investigation workflow.');await sleep(500);assert.ok(!read().nextq.some(q=>/demo now/i.test(q.q)));
  await send('Can you give us a firewall demo today?');let s=await until(s=>s.turns.at(-1).coachQ);assert.equal(s.turns.at(-1).coachTarget,'Discovery focus');assert.equal(s.nextq[0].q,s.turns.at(-1).coachQ);assert.match(s.nextq[0].q,/next step/);
  await send('We use Sumo Logic for centralized logs.');await until(s=>s.competition?.length===1);assert.equal(read().competition[0].name,'Sumo Logic');
  await send('What is the difference between Splunk and Sumo Logic?');s=await until(s=>s.liveAnswer?.status!=='searching');assert.equal(s.liveAnswer.category,'competition');assert.equal(s.liveAnswer.status,localOnly?'unverified':'grounded');assert.equal(s.customerQuestions.at(-1).kind,'competition');assert.equal(s.customerQuestions.at(-1).status,localOnly?'needs_confirmation':'ready');assert.ok(!['answered','deferred'].includes(s.customerQuestions.at(-1).status));
  if(!localOnly){assert.ok(s.liveAnswer.sources.some(u=>u.includes('sumologic.com')));assert.ok(s.liveAnswer.sources.some(u=>u.includes('splunk.com')));await send('I was wondering how they differ in terms of data ingestion.');s=await until(s=>s.liveAnswer?.q.includes('data ingestion')&&s.liveAnswer.status!=='searching');assert.equal(s.liveAnswer.category,'competition');}
  console.log('PASS '+(localOnly?'local-only':'sourced')+' real engine: discovery redirect, unsafe demo suppression, competitor notes, categorized answer, ledger and contextual comparison');
 }finally{p.kill('SIGTERM');rmSync(dir,{recursive:true,force:true});}
}
await run(false);await run(true);

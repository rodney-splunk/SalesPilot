import {spawn} from 'node:child_process';import assert from 'node:assert/strict';import {mkdtempSync,readFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'salespilot-retry-polish-')),file=join(dir,'session.json');
const env={...process.env,SALESPILOT_OFFLINE:'1',COACH_LOCAL:'1',PROVIDER:'ollama',SESSION_FILE:file,PREP_FILE:join(dir,'absent'),SALESPILOT_RAG_INDEX:join(dir,'absent-index'),SALESPILOT_DOCS_SERVER:join(dir,'absent-docs'),CORRECT_MIN_INTERVAL_MS:'-1'};delete env.SALESPILOT_LOCAL_ONLY;
const p=spawn(process.execPath,['--import',new URL('../tests/engine/mock-retry-polish.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname],{env,stdio:['pipe','ignore','pipe']});let errors='';p.stderr.on('data',d=>errors+=d);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file))}catch{return null}};const send=obj=>p.stdin.write(JSON.stringify(obj)+'\n');async function until(fn){for(let i=0;i<300;i++){const s=read();if(s&&fn(s))return s;await sleep(25)}throw Error(errors)}
try{
 await until(()=>true);send({speaker:'customer',text:'How does Splunk differ from Sumo Logic?'});
 let s=await until(s=>s.liveAnswer?.requestFailed===true);assert.equal(s.coachProgress.state,'failed');const id=s.customerQuestions[0].id;assert.equal(s.customerQuestions[0].status,'needs_confirmation');
 send({cmd:'retry',id});s=await until(s=>s.liveAnswer?.status==='grounded');assert.equal(s.customerQuestions.length,1);assert.equal(s.customerQuestions[0].status,'ready');assert.equal(s.coachProgress.state,'ready');
 send({cmd:'question',id,status:'answered'});await until(s=>s.customerQuestions[0].status==='answered');send({cmd:'retry',id});await sleep(100);assert.equal(read().customerQuestions[0].status,'answered');
 send({speaker:'customer',text:'Which is cheaper, Splunk or Sumo Logic pricing?'});await until(s=>s.liveAnswer?.status==='searching');send({cmd:'recap'});s=await until(s=>s.recap);assert.ok(!s.customerQuestions.some(q=>q.status==='searching'));const before=JSON.stringify(s.liveAnswer);
 send({cmd:'retry',id:s.customerQuestions.at(-1).id});await sleep(1500);assert.equal(JSON.stringify(read().liveAnswer),before);assert.ok(!read().customerQuestions.some(q=>q.status==='searching'));
 console.log('PASS outage status, explicit retry, preserved question ID/delivery, stop during search and no retry/late publication after call end');
}finally{p.kill('SIGTERM');await new Promise(r=>p.exitCode!==null?r():p.once('exit',r));rmSync(dir,{recursive:true,force:true});}

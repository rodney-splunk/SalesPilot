import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';import {join} from 'node:path';
import {partialEvidence} from './coverage-evidence.mjs';import {callContext,callNotes} from './call-memory.mjs';
const turns=[];const add=text=>turns.push({id:turns.length,text,side:'customer',who:'Jesse',me:false});
add('We use Palo Alto firewall logs at 45 GB per day.');
for(let i=0;i<280;i++){if(i===90)add('Our manual handoff delays investigations by six hours.');else if(i===140)add('Those delays mean we miss our response SLA and work weekends.');else if(i===210)add('We need to reduce investigation time so our team can meet its response commitment.');else add(`Our analysts review routine operational item ${i}.`);}
add('We have separate Linux server logs with a different collection workflow.');
const ev=partialEvidence(turns);assert.ok(ev.situation.evidence.some(e=>e.turnId===0));assert.ok(ev.situation.evidence.some(e=>e.turnId===281));
const context=callContext(turns,callNotes(turns));for(const phrase of ['45 GB','six hours','work weekends','response commitment','Linux server'])assert.ok(context.includes(phrase),phrase);
const dir=mkdtempSync(join(tmpdir(),'salespilot-layered-')),file=join(dir,'session.json'),prompts=join(dir,'prompts');
const p=spawn(process.execPath,['--import',new URL('../tests/engine/mock-layered-answer.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname],{env:{...process.env,SALESPILOT_OFFLINE:'1',COACH_LOCAL:'1',PROVIDER:'ollama',SESSION_FILE:file,PREP_FILE:join(dir,'absent'),SALESPILOT_RAG_INDEX:join(dir,'absent-index'),SALESPILOT_DOCS_SERVER:join(dir,'absent-docs'),TEST_PROMPTS:prompts,CORRECT_MIN_INTERVAL_MS:'-1'},stdio:['pipe','ignore','pipe']});let errors='';p.stderr.on('data',d=>errors+=d);const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file))}catch{return null}};const send=o=>p.stdin.write(JSON.stringify(o)+'\n');async function until(fn){for(let i=0;i<350;i++){const s=read();if(s&&fn(s))return s;await sleep(25)}throw Error(errors)}
try{
 await until(()=>true);send({speaker:'customer',text:'What is the difference between Splunk and Datadog?'});await until(s=>s.liveAnswer?.status==='searching');
 await sleep(250);send({speaker:'customer',text:'Specifically in terms of ingestion for our Linux logs, not pricing.'});
 let s=await until(s=>s.turns.length===2);assert.notEqual(s.liveAnswer.status,'grounded','do not publish generic answer while scope is arriving');
 s=await until(s=>s.liveAnswer?.status==='grounded');assert.equal(s.customerQuestions.length,1);assert.equal(s.customerQuestions[0].turnIds.length,2);assert.match(s.liveAnswer.answer,/\n\nDatadog/);assert.ok(s.nextq[0].q.endsWith('?'));assert.ok(!/sourced answer|Searching documentation|Unanswered:/i.test(s.nextq[0].q));
 const requests=readFileSync(prompts,'utf8');assert.match(requests,/Linux logs/);assert.match(requests,/not pricing/);assert.match(s.nextq[0].q,/sources|collection/);
 send({speaker:'customer',text:'What about retention for those investigations?'});await until(s=>s.liveAnswer?.status==='searching');s=await until(s=>s.liveAnswer?.status==='grounded'&&s.customerQuestions[0].turnIds.length===3);assert.equal(s.answerHistory.length,1,'replace the stale generic comparison rather than presenting both');assert.match(s.nextq[0].q,/How long/);
 send({cmd:'question',id:s.customerQuestions[0].id,status:'answered'});await until(s=>s.customerQuestions[0].status==='answered');send({speaker:'customer',text:'What about retention for our audit?' });await until(s=>s.turns.length===4);assert.equal(read().customerQuestions[0].turnIds.length,3,'resolved question cannot be silently reopened');
 send({speaker:'customer',text:'Does Datadog support log collection through an agent?'});s=await until(s=>s.liveAnswer?.q.includes('agent')&&s.liveAnswer.status==='grounded');assert.equal(s.liveAnswer.category,'product');assert.ok(s.liveAnswer.sources.every(u=>u.includes('docs.datadoghq.com')));assert.ok(!/Splunk/.test(s.liveAnswer.answer));
 console.log('PASS layered live comparison: standby, scope refinement, preserved ledger ID, full-context prompt, vendor paragraph breaks, actual follow-up question; 282-turn whole-call SPIN evidence');
}finally{p.kill('SIGTERM');await new Promise(r=>p.exitCode!==null?r():p.once('exit',r));rmSync(dir,{recursive:true,force:true});}

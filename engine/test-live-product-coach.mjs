// Opt-in provider smoke using a synthetic conversation, never a recorded call.
import {spawn} from 'node:child_process';import assert from 'node:assert/strict';import {mkdtempSync,readFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'salespilot-live-provider-')),file=join(dir,'session.json');const env={...process.env,SESSION_FILE:file,PREP_FILE:join(dir,'absent'),CORRECT_MIN_INTERVAL_MS:'-1'};delete env.COACH_LOCAL;delete env.SALESPILOT_OFFLINE;
const p=spawn(process.execPath,[new URL('./serve.mjs',import.meta.url).pathname,'--framework','spin'],{env,stdio:['pipe','ignore','ignore']});const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file,'utf8'))}catch{return null}};let heartbeat;
try{
 for(let i=0;i<80&&!read();i++)await sleep(50);
 const at=Date.now()/1000;p.stdin.write(JSON.stringify({speaker:'customer',text:'We are comparing Splunk Cloud and Splunk Enterprise because we need to monitor Windows event logs. How do they differ in data ingestion?',startedAt:at-8,endedAt:at})+'\n');
 heartbeat=setInterval(()=>{const now=Date.now()/1000;p.stdin.write(JSON.stringify({cmd:'activity',speaker:'you',active:true,at:now,voicedAt:now})+'\n')},250);
 for(let i=0;i<300&&read()?.turns?.[0]?.coachIntent!=='answer';i++)await sleep(50);
 let s=read();assert.equal(s.turns[0].coachIntent,'answer');assert.equal(s.turns[0].coachQ,null,'product answer is not interrupted by a discovery question');assert.equal(s.nextq[0].tag,'Customer question');
 const now=Date.now()/1000;p.stdin.write(JSON.stringify({speaker:'customer',text:'Our analysts miss important alerts while waiting six hours for the network team to send firewall logs.',startedAt:now,endedAt:now+1})+'\n');
 for(let i=0;i<300&&(!read()?.turns?.[1]?.coachQ);i++)await sleep(50);
 s=read();assert.ok(s.turns[1].coachQ,'discovery resumes on the new customer workflow');assert.equal(s.nextq[0].q,s.turns[1].coachQ);assert.ok(s.coverage.some(c=>c.status!=='open'));assert.ok(s.performance.hostedCoach.outcomes.ok>=1);console.log('PASS live CIRCUIT: answer-first product routing, resumed workflow discovery, transcript/Next Move parity and partial coverage during ongoing audio activity');
}finally{clearInterval(heartbeat);p.kill('SIGTERM');rmSync(dir,{recursive:true,force:true});}

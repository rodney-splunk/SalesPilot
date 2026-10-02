// Opt-in real provider check with a fictitious competitive question; isolated session and no customer recording.
import {spawn} from 'node:child_process';import assert from 'node:assert/strict';import {mkdtempSync,readFileSync,rmSync} from 'node:fs';import {join} from 'node:path';import {tmpdir} from 'node:os';
const dir=mkdtempSync(join(tmpdir(),'salespilot-live-competition-')),file=join(dir,'session.json');
const env={...process.env,SESSION_FILE:file,PREP_FILE:join(dir,'absent'),SALESPILOT_RAG_INDEX:join(dir,'absent-index'),SALESPILOT_CALL_PURPOSE:'discovery',CORRECT_MIN_INTERVAL_MS:'-1'};delete env.SALESPILOT_LOCAL_ONLY;delete env.SALESPILOT_OFFLINE;delete env.COACH_LOCAL;
const p=spawn(process.execPath,[new URL('./serve.mjs',import.meta.url).pathname,'--framework','spin'],{env,stdio:['pipe','ignore','pipe']});let diagnostics='';p.stderr.on('data',d=>diagnostics=(diagnostics+d).slice(-2000));const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file))}catch{return null}};
try{
 for(let i=0;i<80&&!read();i++)await sleep(50);
 p.stdin.write(JSON.stringify({speaker:'customer',text:'What is the difference between Splunk and Sumo Logic for log search and deployment options?'})+'\n');
 for(let i=0;i<650&&read()?.liveAnswer?.status!=='grounded'&&read()?.liveAnswer?.status!=='unverified';i++)await sleep(50);
 const s=read(),a=s?.liveAnswer;if(a?.status!=='grounded')console.error(JSON.stringify({status:a?.status,diagnostics:a?.diagnostics,engineError:s?.engineError,transportLog:diagnostics}));
 assert.equal(a?.category,'competition');assert.equal(a?.status,'grounded','Both-vendor sourced comparison required');assert.ok(a.sources.some(u=>u.includes('sumologic.com')));assert.ok(a.sources.some(u=>u.includes('splunk.com')));assert.equal(s.customerQuestions[0].kind,'competition');assert.equal(s.customerQuestions[0].status,'ready');assert.equal(s.competition[0].name,'Sumo Logic');
 console.log('PASS real Cisco competitive answer: official Splunk and Sumo sources, customer signal, Research route and question ledger');
}finally{p.kill('SIGTERM');rmSync(dir,{recursive:true,force:true});}

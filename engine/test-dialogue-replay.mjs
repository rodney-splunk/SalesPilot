import assert from 'node:assert/strict';
import {dialoguePlan,discoveryGuidance} from './dialogue-plan.mjs';
import {partialEvidence} from './coverage-evidence.mjs';
import {spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';import {join} from 'node:path';
const prior=[{text:'What is the difference between Splunk Cloud and Splunk Enterprise?',side:'customer'}];
assert.equal(dialoguePlan('The main question I had for you today was,').kind,'listen');
assert.equal(dialoguePlan('I was wondering how they differed in terms of data ingestion.',prior).kind,'answer');
assert.match(dialoguePlan('I was wondering how they differed in terms of data ingestion.',prior).request.query,/Cloud.*Enterprise|Enterprise.*Cloud/i);
assert.equal(dialoguePlan('We have Windows syslogs. Can those go into Splunk Cloud?',prior).kind,'clarify');
assert.equal(dialoguePlan('Can Splunk Cloud ingest Windows Event Logs and syslog from network devices?',prior).kind,'answer');
assert.equal(dialoguePlan('We have eight theaters and no visibility into failures.').kind,'explore');
assert.match(dialoguePlan('Our mean time to detect is six hours, and our target is under one hour.').question,/before your team detects/);
const evidence=partialEvidence([{id:1,side:'customer',text:'We track mean time to detect. It is six hours; the target is under one hour.'},{id:2,side:'customer',text:'If nothing changes we will fail our audit in March and that puts a major customer contract at risk.'}]);assert.ok(evidence.metrics);assert.ok(evidence.implication);assert.match(discoveryGuidance(),/Distinguish detection/);assert.match(dialoguePlan('No, we have no formal uptime or downtime requirement.',[{text:'We manage eight theaters and have no central monitoring.'}]).question,/busy showing/);
const dir=mkdtempSync(join(tmpdir(),'salespilot-dialogue-replay-')),file=join(dir,'session.json');
const p=spawn(process.execPath,['--import',new URL('../tests/engine/mock-model.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname,'--framework','spin'],{env:{...process.env,COACH_LOCAL:'1',SALESPILOT_OFFLINE:'1',SESSION_FILE:file,PREP_FILE:join(dir,'absent'),CORRECT_MIN_INTERVAL_MS:'-1'},stdio:['pipe','ignore','pipe']});let error='';p.stderr.on('data',d=>error+=d);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file))}catch{return null}};
const send=text=>p.stdin.write(JSON.stringify({speaker:'customer',text})+'\n');
try{
 for(let i=0;i<80&&!read();i++)await sleep(50);
 send('The main question I had for you today was,');await sleep(600);assert.equal(read().turns.at(-1).coachQ,null);
 send('What is the difference between Splunk Cloud and Splunk Enterprise?');await sleep(600);let s=read();assert.equal(s.turns.at(-1).coachIntent,'answer');assert.equal(s.turns.at(-1).coachQ,null);assert.equal(s.nextq[0].tag,'Customer question');assert.ok(s.nextq[0].q.endsWith('?'));assert.ok(!/sourced answer|Searching documentation/i.test(s.nextq[0].q));assert.ok(s.customerQuestions.some(q=>!['answered','deferred'].includes(q.status)));
 send('I was wondering how they differed in terms of data ingestion.');await sleep(500);assert.equal(read().turns.at(-1).coachIntent,'answer');
 send('We have Windows syslogs. Could those go into Splunk Cloud?');await sleep(500);s=read();assert.equal(s.turns.at(-1).coachIntent,'clarify');assert.match(s.turns.at(-1).coachQ,/Windows Event Logs/);assert.equal(s.nextq[0].q.replace(/^Clarify: /,''),s.turns.at(-1).coachQ);
 send('Our analysts investigate alerts in the legacy SIEM and wait six hours for firewall logs.');for(let i=0;i<100&&(read().turns.at(-1).coachIntent!=='explore'||!read().turns.at(-1).coachQ);i++)await sleep(50);s=read();assert.equal(s.turns.at(-1).coachIntent,'explore');assert.ok(s.turns.at(-1).coachQ,error);assert.equal(s.nextq[0].q.replace(/^Clarify: /,''),s.turns.at(-1).coachQ);
 console.log('PASS recorded-pattern replay: unfinished thought, answer-first, retained comparison, source clarification, return to discovery, transcript/Next Move parity, spoken metrics and literal risk');
}finally{p.kill('SIGTERM');rmSync(dir,{recursive:true,force:true})}

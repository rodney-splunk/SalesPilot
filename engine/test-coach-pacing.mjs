import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'salespilot-pacing-')),file=join(dir,'session.json');
const p=spawn(process.execPath,['--import',new URL('../tests/engine/mock-model.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname],{env:{...process.env,COACH_LOCAL:'1',SALESPILOT_OFFLINE:'1',SESSION_FILE:file,PREP_FILE:join(dir,'absent'),CORRECT_MIN_INTERVAL_MS:'-1'},stdio:['pipe','ignore','pipe']});
let errors='';p.stderr.on('data',d=>errors+=d);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const read=()=>{try{return JSON.parse(readFileSync(file,'utf8'))}catch{return null}};
const send=(speaker,text)=>p.stdin.write(JSON.stringify({speaker,text})+'\n');
try{
 for(let i=0;i<80&&!read();i++)await sleep(50);assert.ok(read(),errors);
 send('customer','Our analysts investigate alerts in the legacy SIEM because');
 await sleep(1700);assert.equal(read().turns.length,1);assert.ok(!read().turns[0].coachQ,'unfinished thought stays quiet');assert.ok(!read().performance?.coachPass,'unfinished thought does not use inference');
 send('customer','Our analysts wait for alerts in the legacy SIEM every morning.');
 await sleep(100);send('you','Let me answer that before we move on.');
 await sleep(1700);assert.ok(!read().turns.some(t=>t.coachQ),'a responding seller cancels pending customer coaching');assert.ok(!read().performance?.coachPass,'settling absorbs a rapid response without inference');
 send('customer','Our analysts miss alerts in the legacy SIEM while waiting for the network team.');
 await sleep(500); // Hosted/local request is now in flight, beyond the settling window.
 send('customer','The legacy SIEM misses alerts and the delay affects our investigation SLA.');
 for(let i=0;i<45&&!read().turns.at(-1).coachQ;i++)await sleep(50);
 assert.ok(read().turns.at(-1).coachQ,errors);assert.ok(read().performance.coachPass.outcomes.cancelled>=1,'in-flight outdated work cancels');
 const voicedAt=Date.now()/1000;
 p.stdin.write(JSON.stringify({cmd:'activity',speaker:'customer',active:true,at:voicedAt,voicedAt})+'\n');
 await sleep(100);assert.ok(read().nextq.length,'audio onset retains the completed follow-up instead of blanking the coach');
 p.stdin.write(JSON.stringify({cmd:'activity',speaker:'customer',active:false,at:Date.now()/1000+.01,voicedAt})+'\n');
 await sleep(150);assert.ok(read().nextq.length,'quiet and delayed transcription do not erase the completed follow-up');
 p.stdin.write(JSON.stringify({speaker:'customer',text:'The legacy SIEM investigation delay means we miss our triage SLA.',startedAt:voicedAt-.5,endedAt:voicedAt})+'\n');
 for(let i=0;i<45&&!read().turns.at(-1).coachQ;i++)await sleep(50);
 assert.ok(read().turns.at(-1).coachQ,'completed transcript releases the quiet gate');
 console.log('PASS real engine: unfinished thoughts, seller responses, cancellation, audio onset, delayed transcription and quiet release');
}finally{p.kill('SIGTERM');await sleep(100);rmSync(dir,{recursive:true,force:true});}

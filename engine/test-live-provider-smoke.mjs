// Opt-in provider smoke using a synthetic conversation, never a recorded call.
import {spawn} from 'node:child_process';import assert from 'node:assert/strict';import {mkdtempSync,readFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'salespilot-live-provider-')),file=join(dir,'session.json');const env={...process.env,SESSION_FILE:file,PREP_FILE:join(dir,'absent'),CORRECT_MIN_INTERVAL_MS:'-1'};delete env.COACH_LOCAL;delete env.SALESPILOT_OFFLINE;
const p=spawn(process.execPath,[new URL('./serve.mjs',import.meta.url).pathname,'--framework','spin'],{env,stdio:['pipe','ignore','pipe']});const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(file,'utf8'))}catch{return null}};let heartbeat;let diagnostics="";p.stderr.on("data",d=>diagnostics=(diagnostics+d.toString()).slice(-3500));
try{
 for(let i=0;i<80&&!read();i++)await sleep(50);
 const at=Date.now()/1000;p.stdin.write(JSON.stringify({speaker:'customer',text:'Our analysts miss important alerts in the legacy SIEM while waiting six hours for the network team to send firewall logs.',startedAt:at-8,endedAt:at})+'\n');
 heartbeat=setInterval(()=>{const now=Date.now()/1000;p.stdin.write(JSON.stringify({cmd:'activity',speaker:'you',active:true,at:now,voicedAt:now})+'\n')},250);
 for(let i=0;i<300&&!read()?.turns?.[0]?.coachQ;i++)await sleep(50);
 const s=read();if(!s?.turns?.[0]?.coachQ)console.error(JSON.stringify({engineError:s?.engineError,progress:s?.coachProgress,performance:s?.performance,diagnostics}));assert.ok(s.turns[0].coachQ,'real hosted coaching completes despite ongoing activity');assert.ok(s.nextq.length,'completed follow-up remains visible');assert.ok(s.coverage.some(c=>c.name==='Problem'&&c.status!=='open'));assert.ok(s.performance.hostedCoach.outcomes.ok>=1);console.log('PASS live CIRCUIT: synthetic customer cue, partial coverage and visible follow-up during continuous microphone activity');
}finally{clearInterval(heartbeat);p.kill('SIGTERM');rmSync(dir,{recursive:true,force:true});}

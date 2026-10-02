import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'salespilot-answer-flow-'));
const session=join(dir,'session.json');
const index=join(dir,'index.json');
writeFileSync(index,JSON.stringify({records:[{file:'fixture.txt',text:'Synthetic retention can be configured to 30 days.',embedding:null}]}));
const proc=spawn(process.execPath,['--import',new URL('../tests/engine/mock-answers.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname],{env:{...process.env,SALESPILOT_OFFLINE:'1',COACH_LOCAL:'1',SESSION_FILE:session,PREP_FILE:join(dir,'none'),SALESPILOT_RAG_INDEX:index,SALESPILOT_DOCS_SERVER:new URL('../tests/fixtures/docs-server.mjs',import.meta.url).pathname,CORRECT_MIN_INTERVAL_MS:'-1'},stdio:['pipe','pipe','pipe']});
let error='';proc.stderr.on('data',d=>error+=d);proc.stdout.on('data',()=>{});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const read=()=>{try{return JSON.parse(readFileSync(session,'utf8'));}catch{return null;}};
async function until(predicate){for(let i=0;i<120;i++){const d=read();if(d&&predicate(d))return d;await delay(50);}throw Error(`Timed out: ${error}`);}
const send=text=>proc.stdin.write(JSON.stringify({speaker:'customer',text})+'\n');
try{
 await until(()=>true);
 send('We need to know whether Splunk can retain our logs for 30 days.');
 await until(d=>d.liveAnswer?.status==='searching');
 assert.equal(read().turns.length,1,'indirect request ingests immediately');
 send('Can Splunk configure retention to 30 days?');
 const d=await until(d=>d.liveAnswer?.status==='grounded');
 assert.equal(d.liveAnswer.q,'Can Splunk configure retention to 30 days?','newest question wins');
 assert.ok(d.liveAnswer.sources.length,'completed answer carries real selected sources');
 assert.ok(d.answerHistory.some(a=>a.q===d.liveAnswer.q),'completed answers remain in the session history');
 send('How does our team investigate incidents today?');
 await until(d=>d.turns.length===3);
 assert.equal(read().liveAnswer.q,'Can Splunk configure retention to 30 days?','discovery question does not replace technical answer');
 send('Can Splunk retain logs for 30 days?');
 await until(d=>d.liveAnswer?.status==='searching');
 proc.stdin.write(JSON.stringify({cmd:'recap'})+'\n');
 await until(d=>d.liveAnswer?.status!=="searching");
 await delay(1700);
 assert.equal(read().liveAnswer.q,'Can Splunk configure retention to 30 days?','recap retains the last completed answer instead of clearing it');
 console.log('PASS indirect requests, immediate transcript, latest-question wins, source links, discovery separation, recap cancellation');
}finally{proc.kill();await new Promise(resolve=>proc.exitCode!==null?resolve():proc.once('exit',resolve));rmSync(dir,{recursive:true,force:true});}

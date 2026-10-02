import {execFileSync,spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,copyFileSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import {participantIntro} from './participants.mjs';
const dir=mkdtempSync(join(tmpdir(),'salespilot-four-voices-'));const session=join(dir,'session.json');
assert.equal(participantIntro("Hi, I'm Abby from Splunk.").side,'seller');
assert.equal(participantIntro("Hi, I'm Jesse from Buttercup Enterprises.").side,'customer');
assert.equal(participantIntro("This is our colleague Abby from Splunk."),null);
assert.equal(participantIntro("I'm thinking about the next steps."),null);
if(!existsSync(new URL('../diarize/speaker.onnx',import.meta.url)))throw new Error('Speaker model unavailable');
const samples=[
 ['Daniel','you',"Hi, my name is Rodney White, and I am from Splunk."],
 ['Samantha','customer',"Hello, I'm Jesse from Buttercup Enterprises. I manage our security operations team."],
 ['Karen','customer',"Hi, my name is Abby, and I am from Splunk. I am the security specialist joining Rodney today."],
 ['Fred','customer',"Hello, my name is Joe, and I am from Buttercup Enterprises. I manage the network engineering team."],
 ['Daniel','you','Thanks for joining. Where does investigation slow down for your team today?'],
 ['Samantha','customer','Our SIEM generates too many false positives and analysts miss important alerts while triaging the queue.'],
 ['Karen','customer','Our Enterprise Security platform uses risk based alerting. Let me show you this demonstration of our detection dashboard.'],
 ['Fred','customer','We gather Cisco firewall logs by hand and wait six hours for another team to send the data.'],
 ['Samantha','customer','My analysts work weekends instead of doing their planned security engineering work.'],
 ['Karen','customer','The price is always free and our deployment never needs any infrastructure.'],
];
if (process.env.SALESPILOT_ASR_INTRO_FILE) { const intros=JSON.parse(readFileSync(process.env.SALESPILOT_ASR_INTRO_FILE)); for(let i=0;i<4;i++) samples[i][2]=intros[i]; }
for(let i=0;i<samples.length;i++){
 const [voice,,text]=samples[i];const aiff=join(dir,`${i}.aiff`),wav=join(dir,`${i}.wav`);
 if(process.env.SALESPILOT_VOICE_FIXTURES){copyFileSync(join(process.env.SALESPILOT_VOICE_FIXTURES,`${i}.wav`),wav);continue;}
 execFileSync('/usr/bin/say',['-v',voice,'-o',aiff,text]);execFileSync('/usr/bin/afconvert',['-f','WAVE','-d','LEI16@16000','-c','1',aiff,wav]);
}
const mock=new URL('../tests/engine/mock-model.mjs',import.meta.url).pathname;
const proc=spawn(process.execPath,['--import',mock,new URL('./serve.mjs',import.meta.url).pathname],{env:{...process.env,SESSION_FILE:session,PREP_FILE:join(dir,'none'),SALESPILOT_OFFLINE:'1',COACH_LOCAL:'1',CORRECT_MIN_INTERVAL_MS:'-1'},stdio:['pipe','pipe','pipe']});let errors='';proc.stderr.on('data',d=>errors+=d);proc.stdout.on('data',()=>{});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(session));}catch{return null}};
try{
 for(let i=0;i<100&&!read();i++)await sleep(50);
 for(let i=0;i<samples.length;i++){
  const [,speaker,text]=samples[i];const audio=join(dir,`consume-${i}.wav`);copyFileSync(join(dir,`${i}.wav`),audio);
  proc.stdin.write(JSON.stringify({speaker,text,wav:audio,startedAt:Date.now()/1000+i*20,endedAt:Date.now()/1000+i*20+8})+'\n');
  for(let n=0;n<100;n++){await sleep(100);const s=read();if(s?.turns.some(t=>t.text===text && t.clusterId!==null))break;}
 }
 let s=read();console.log('VOICE RESULTS',s.turns.map(t=>({who:t.who,side:t.side,cluster:t.clusterId})));assert.equal(s.turns.length,samples.length);
 const expected=['Rodney White','Jesse','Abby','Joe','Rodney White','Jesse','Abby','Joe','Jesse','Abby'];
 assert.deepEqual(s.turns.map(t=>t.who),expected,errors);
 assert.equal(s.customerName,'Joe');
 assert.match(s.customerRole,/network engineering/i,'a new named customer gets their own role');
 assert.doesNotMatch(s.customerRole,/security operations/i,'a prior customer role does not leak into the new identity');
 assert.equal(new Set(s.turns.map(t=>t.clusterId)).size,4,'four actual voice clusters');
 assert.deepEqual(s.turns.map(t=>t.side),['seller','customer','seller','customer','seller','customer','seller','customer','customer','seller']);
 assert.ok(!s.notes.some(n=>/always free|never needs/.test(n.quote)),'colleague claims excluded from notes');
 assert.ok(!s.solutions.areas.some(a=>a.evidence.some(x=>/risk.based/.test(x))),'colleague pitch excluded from opportunity evidence');
 const joe=s.turns[3].clusterId;proc.stdin.write(JSON.stringify({cmd:'speaker',clusterId:joe,side:'customer',name:'Joe Network Lead'})+'\n');await sleep(300);s=read();
 assert.equal(s.turns[3].who,'Joe Network Lead','manual name corrects prior speech');assert.equal(s.turns[7].who,'Joe Network Lead','manual name corrects later speech');assert.equal(s.turns[1].who,'Jesse','other voice unaffected');
 const mixed=join(dir,'mixed.wav');
 execFileSync(new URL('../diarize/.venv/bin/python',import.meta.url).pathname,['-c',"import wave,sys; a=wave.open(sys.argv[1]); b=wave.open(sys.argv[2]); o=wave.open(sys.argv[3],'wb'); o.setparams(a.getparams()); o.writeframes(a.readframes(a.getnframes())+b.readframes(b.getnframes())); o.close()",join(dir,'5.wav'),join(dir,'6.wav'),mixed]);
 proc.stdin.write(JSON.stringify({speaker:'customer',text:'Our analysts investigate important alerts. Let me show you this product demonstration.',wav:mixed,startedAt:Date.now()/1000+240,endedAt:Date.now()/1000+255})+'\n');
 for(let n=0;n<100;n++){await sleep(100);if(read()?.turns.at(-1)?.speakerStatus==='mixed')break;}
 s=read();assert.equal(s.turns.at(-1).who,'Mixed speakers','mixed audio does not get a single confident name');
 assert.ok(!s.notes.some(n=>n.quote.includes('Our analysts investigate important alerts')),'mixed-role statements excluded from notes');
 for(const [index,text] of ['All right.','Ummmm...','Uh oh.'].entries()){
  const brief=join(dir,`brief-${index}.wav`);copyFileSync(join(dir,'0.wav'),brief);
  proc.stdin.write(JSON.stringify({speaker:'you',text,wav:brief,startedAt:Date.now()/1000+260+index,endedAt:Date.now()/1000+260.8+index})+'\n');
  await sleep(100);s=read();const found=s.turns.find(t=>t.text===text);assert.equal(found.clusterId,null,'brief fillers do not create voice identities');assert.equal(found.who,'Rodney White','brief microphone speech keeps the confirmed name');assert.equal(existsSync(brief),false,'skipped audio snapshot is removed');
 }
 console.log('PASS brief fillers preserve transcript without creating extra speakers or leaking audio files');
 const conflict=join(dir,'conflict.wav');copyFileSync(join(dir,'0.wav'),conflict);
 proc.stdin.write(JSON.stringify({speaker:'you',text:"Hi, I'm Marcus from Splunk.",wav:conflict,startedAt:Date.now()/1000+280,endedAt:Date.now()/1000+288})+'\n');
 for(let n=0;n<100;n++){await sleep(100);if(read()?.turns.at(-1)?.speakerStatus==='ambiguous')break;}
 s=read();assert.match(s.turns[0].who,/^Speaker \d+$/,'conflict retains a stable anonymous voice ID');assert.equal(s.turns.at(-1).who,s.turns[0].who);assert.equal(s.turns[0].speakerStatus,'ambiguous','identity conflict remains explicit');
 proc.stdin.write(JSON.stringify({cmd:'speaker',clusterId:s.turns[0].clusterId,side:'seller',name:'Rodney White'})+'\n');await sleep(300);s=read();assert.equal(s.turns[0].who,'Rodney White');assert.equal(s.turns.at(-1).who,'Rodney White');assert.equal(s.turns[1].who,'Jesse');
 console.log('PASS conflicting identity stays uncertain and manual correction restores only its voice');
 console.log('PASS four real synthesized voices, both teams, ongoing names, evidence isolation, and manual correction');console.log('Fixture directory:',dir);
}catch(e){console.log('Fixture directory:',dir);console.error(e);process.exitCode=1;}finally{proc.kill('SIGTERM');}

// Synthetic audio only. A spelling benchmark, not an accent or demographic fairness evaluation.
import {execFileSync} from 'node:child_process';
import {mkdtempSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const dir=process.env.SALESPILOT_NAME_FIXTURES || mkdtempSync(join(tmpdir(),'salespilot-name-audio-'));
const names=['Nancy Xiao','Wei Zhang','Priya Nair','Arjun Desai','Nguyen Tran','José García','Amina Hassan',"Siobhán O’Connor"];
const clips=names.map((name,i)=>({name,voice:i%2?'Daniel':'Samantha'}));clips.push({name:'Nancy Xiao',voice:'Daniel'});
const vocab='Splunk, MEDDPICC, SPIN, Challenger, APM, SOAR, ITSI, SIEM, SOC 2, SLA, SLAs, MTTR, PII, Edge Processor, Enterprise Security, risk-based alerting, correlation search, observability, Cisco, POC, renewal.';
const results=[];const norm=s=>s.toLowerCase().normalize('NFKC').replace(/[’']/g,'').replace(/[^\p{L}\p{N}]+/gu,' ').trim();
for(let i=0;i<clips.length;i++){
 const {name,voice}=clips[i],expected=`Hi, my name is ${name}. I manage the security team and we use Splunk.`;
 if(!process.env.SALESPILOT_NAME_FIXTURES) execFileSync('/usr/bin/say',['-v',voice,'-o',join(dir,`${i}.aiff`),expected],{timeout:30000});
 if(!process.env.SALESPILOT_NAME_FIXTURES) execFileSync('/usr/bin/afconvert',['-f','WAVE','-d','LEI16@16000','-c','1',join(dir,`${i}.aiff`),join(dir,`${i}.wav`)],{timeout:30000});
 for(const model of ['small.en','medium.en'])for(const hints of [false,true]){
  const prompt=vocab+(hints?` On this call: ${names.join(', ')}.`:'');
  const args=['-m',`${process.env.HOME}/.config/open-wispr/models/ggml-${model}.bin`,'-f',join(dir,`${i}.wav`),'-l','en','-nt','-t',model==='small.en'?'4':'6','--prompt',prompt];if(model==='medium.en')args.push('-bs','5');
  const start=performance.now();const text=execFileSync('/opt/homebrew/bin/whisper-cli',args,{encoding:'utf8',timeout:90000,stdio:['ignore','pipe','ignore']}).trim();
  results.push({name,voice,model,hints,expected,transcribed:text,exactName:norm(text).includes(norm(name)),elapsedMs:Math.round(performance.now()-start)});
  const summary=Object.fromEntries(['small.en','medium.en'].flatMap(model=>[false,true].map(hints=>{const r=results.filter(x=>x.model===model&&x.hints===hints);return[`${model}:${hints?'attendees':'baseline'}`,{correct:r.filter(x=>x.exactName).length,total:r.length}]})));
  writeFileSync(new URL('../previews/name-audio-evaluation.json',import.meta.url),JSON.stringify({scope:'Nine clean English synthetic clips, eight names, two TTS voices; exact Unicode spelling ignoring case/punctuation. Does not establish natural pronunciation, accent performance, live latency or population accuracy.',fixtureDirectory:dir,summary,results},null,2)+'\n');
  console.log(`${name} | ${voice} | ${model} | ${hints?'attendees':'baseline'} | ${results.at(-1).exactName?'PASS':'MISS'} | ${text}`);
 }
}

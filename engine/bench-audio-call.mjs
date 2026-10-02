// Local file inference against synthetic voices; no live device capture or hosted requests.
import {execFileSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
import {join} from 'node:path';
const dir=process.argv[2];if(!dir)throw new Error('Pass the synthetic four-voice fixture directory');
const clips=[
 [0,'Hi, my name is Rodney White, and I am from Splunk.'],
 [1,"Hello, I'm Jesse from Buttercup Enterprises. I manage our security operations team."],
 [2,'Hi, my name is Abby, and I am from Splunk. I am the security specialist joining Rodney today.'],
 [3,'Hello, my name is Joe, and I am from Buttercup Enterprises. I manage the network engineering team.'],
 [5,'Our SIEM generates too many false positives and analysts miss important alerts while triaging the queue.'],
 [7,'We gather Cisco firewall logs by hand and wait six hours for another team to send the data.'],
 [8,'My analysts work weekends instead of doing their planned security engineering work.']
];
const prompt='Splunk, MEDDPICC, SPIN, Challenger, APM, SOAR, ITSI, SIEM, SOC 2, SLA, SLAs, MTTR, PII, Edge Processor, Enterprise Security, risk-based alerting, correlation search, observability, Cisco, POC, renewal.';
const words=s=>s.toLowerCase().replace(/[^a-z0-9\s]/g,' ').trim().split(/\s+/);
function distance(a,b){let prev=Array.from({length:b.length+1},(_,i)=>i);for(let i=1;i<=a.length;i++){const row=[i];for(let j=1;j<=b.length;j++)row[j]=Math.min(row[j-1]+1,prev[j]+1,prev[j-1]+(a[i-1]===b[j-1]?0:1));prev=row;}return prev[b.length];}
const results=[];
for(const model of ['small.en','medium.en'])for(const [id,expected] of clips){
 const args=['-m',`${process.env.HOME}/.config/open-wispr/models/ggml-${model}.bin`,'-f',join(dir,`${id}.wav`),'-l','en','-nt','-t',model==='small.en'?'4':'6','--prompt',prompt];if(model==='medium.en')args.push('-bs','5');
 const start=performance.now();const text=execFileSync('/opt/homebrew/bin/whisper-cli',args,{encoding:'utf8',timeout:60000,stdio:['ignore','pipe','ignore']}).trim();
 results.push({model,clip:id,expected,transcribed:text,elapsedMs:Math.round(performance.now()-start),wordErrors:distance(words(expected),words(text)),referenceWords:words(expected).length});
}
const report={scope:'Seven synthetic clips, two local models; punctuation/case normalized. CLI timing includes model load and is not resident-server or live-call latency.',results,summary:Object.fromEntries(['small.en','medium.en'].map(model=>{const r=results.filter(x=>x.model===model);return[model,{clips:r.length,wordErrorRate:r.reduce((s,x)=>s+x.wordErrors,0)/r.reduce((s,x)=>s+x.referenceWords,0)}]}))};
writeFileSync(new URL('../previews/audio-call-evaluation.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report.summary));

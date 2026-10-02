import {writeFileSync} from 'node:fs';
import {callQuality,MODELS} from './core.mjs';
import {groundedAnswer} from './answer-policy.mjs';
const refs=[{id:'S1',source:'synthetic-guide.txt',title:'Synthetic connector guide',text:'The sample connector supports configurable retention of 30 days. This test source does not establish support for 90 days.'}];
const rows=[];
for(const question of ['How long does this sample connector retain events?','Does this source confirm the sample connector supports ninety days?']){
 const started=performance.now();try{
  const raw=await callQuality('You are evaluating a SYNTHETIC source, not actual product documentation. Answer only from S1. Output JSON with answer, sourceIds, supported. If the source does not support a claim, supported must be false. Never invent capabilities or numbers.',`S1: ${refs[0].text}\nQuestion: ${question}`,800,true,{task:'answer',remoteOnly:true,timeoutMs:30000});
  const result=groundedAnswer(raw,refs,question);rows.push({question,ms:Math.round(performance.now()-started),raw,result,correct:question.includes('ninety')?result===null:!!result&&/30/.test(result.answer)});
 }catch(error){rows.push({question,ms:Math.round(performance.now()-started),error:error.message.slice(0,100)});}console.log(JSON.stringify(rows.at(-1)));
}
writeFileSync(new URL(`../previews/quality-benchmark-${MODELS.circuit.worker}.json`,import.meta.url),JSON.stringify({model:MODELS.circuit.worker,syntheticOnly:true,rows},null,2));

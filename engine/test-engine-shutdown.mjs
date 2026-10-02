import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,copyFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const fixture=process.argv[2];if(!fixture)throw new Error('Pass a synthetic voice WAV');
const dir=mkdtempSync(join(tmpdir(),'salespilot-shutdown-')),out=join(dir,'session.json'),audio=join(dir,'voice.wav');copyFileSync(fixture,audio);
const proc=spawn(process.execPath,['--import',new URL('../tests/engine/mock-model.mjs',import.meta.url).pathname,new URL('./serve.mjs',import.meta.url).pathname],{env:{...process.env,COACH_LOCAL:'1',SALESPILOT_OFFLINE:'1',SESSION_FILE:out,PREP_FILE:join(dir,'absent')},stdio:['pipe','ignore','ignore']});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));const read=()=>{try{return JSON.parse(readFileSync(out,'utf8'))}catch{return null}};
try {
 proc.stdin.write(JSON.stringify({speaker:'customer',text:'Hi, I am Dana.',wav:audio})+'\n');
 for(let i=0;i<100&&read()?.turns?.[0]?.clusterId==null;i++)await sleep(100);
 assert.ok(read()?.turns?.[0]?.clusterId!=null,'real sidecar started');
 const exited=new Promise(resolve=>proc.once('exit',(code,signal)=>resolve({code,signal})));
 proc.kill('SIGTERM');let timer;const result=await Promise.race([exited,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('engine did not stop')),2000)})]);clearTimeout(timer);
 assert.equal(result.code,143);console.log('PASS real speaker sidecar shutdown terminates its engine without waiting for stdin EOF');
}finally{if(proc.exitCode==null)proc.kill('SIGKILL');rmSync(dir,{recursive:true,force:true});}

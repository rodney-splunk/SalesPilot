// Read-only checks. Never send a transcript or change an audio device.
import {existsSync,readFileSync,statSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {circuitConfig,circuitToken} from './circuit.mjs';
export async function readiness({root=resolve(fileURLToPath(new URL('..',import.meta.url))),online=false}={}) {
 const checks=[];const add=(id,state,detail)=>checks.push({id,state,detail});
 const config=circuitConfig();
 if(process.env.SALESPILOT_LOCAL_ONLY!=='1' && config.client_id&&config.inference_url&&((config.client_secret&&config.app_key)||config.credential_store==='macos-keychain')){
  if(online){try{await circuitToken();add('coaching','available','Cisco authentication succeeded; model response is checked when coaching runs.');}catch{add('coaching','unavailable','Cisco authentication failed. Check your connection and provider setup.');}}
  else add('coaching','configured','Cisco is configured. Run connection checks to verify access.');
 }else{try{const res=await fetch('http://localhost:11434/api/tags',{signal:AbortSignal.timeout(1500)});const data=await res.json();add('coaching',res.ok&&data.models?.length?'available':'unavailable',res.ok&&data.models?.length?'Local models are available.':'No local models are loaded.');}catch{add('coaching','unavailable','No configured Cisco provider or reachable local model.');}}
 const model=resolve(root,'diarize/speaker.onnx');const python=resolve(root,'diarize/.venv/bin/python');
 add('voices',existsSync(model)&&existsSync(python)?'configured':'unavailable',existsSync(model)&&existsSync(python)?'Local speaker model installed; uncertain and overlapping speech still needs review.':'Speaker model missing. Transcript capture can continue with unnamed audio.');
 const docs=process.env.SALESPILOT_DOCS_SERVER||`${process.env.HOME}/.config/ghost/mcp-servers/dist/servers/splunk-docs/server.js`;
 if(process.env.SALESPILOT_LOCAL_ONLY==='1')add('documentation','disabled','Public documentation requests are blocked in local-only mode. Local references remain available.');
 else if(!existsSync(docs))add('documentation','unavailable','Official documentation connector is missing. Add local approved references as a fallback.');
 else if(online){try{const {searchSplunkDocs}=await import('./splunkdocs.mjs');const hits=await searchSplunkDocs('Splunk Enterprise data inputs',1);add('documentation',hits.length?'available':'unavailable',hits.length?'Official documentation returned a readable source.':'No readable source returned. Check your connection or connector.');}catch{add('documentation','unavailable','Documentation connection check failed.');}}
 else add('documentation','configured','Official connector installed. Run connection checks to verify a readable source.');
 const index=resolve(root,'sessions/rag-index.json');try{const value=JSON.parse(readFileSync(index));add('references',value.records?.length?'available':'optional',value.records?.length?`${new Set(value.records.map(r=>r.file)).size} indexed references; last indexed ${new Date(statSync(index).mtimeMs).toISOString()}.`:'No local documents indexed. Official documentation remains available separately.');}catch{add('references','optional','No local documents indexed.');}
 return {checkedAt:new Date().toISOString(),online,checks};
}
if(process.argv[1]===fileURLToPath(import.meta.url))console.log(JSON.stringify(await readiness({online:process.argv.includes('--online')})));

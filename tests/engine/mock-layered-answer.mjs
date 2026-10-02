import {appendFileSync} from 'node:fs';
import './mock-purpose-competition.mjs';
const original=globalThis.fetch;
globalThis.fetch=async(url,options={})=>{
 const u=new URL(url);
 if(u.hostname==='docs.datadoghq.com')return new Response('<main>'+('Datadog provides log collection through its Agent and integrations. ').repeat(5)+'</main>',{headers:{'content-type':'text/html'}});
 if(u.hostname==='localhost'){
  const request=JSON.parse(options.body||'{}');
  if(/live competitive discussion/.test(request.messages?.[0]?.content||'')){
   appendFileSync(process.env.TEST_PROMPTS,JSON.stringify(request)+'\n');
   return Response.json({message:{content:JSON.stringify({answer:'Splunk provides managed Cloud Platform and self-managed Enterprise deployments. Datadog provides log collection through its Agent and integrations.',sourceIds:['S1','S2','S3'],supported:true})}});
  }
 }
 return original(url,options);
};

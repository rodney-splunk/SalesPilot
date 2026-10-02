import assert from 'node:assert/strict';
globalThis.fetch=async(url,options={})=>{
 const u=new URL(url);
 if(u.hostname!=='localhost'){
  assert.notEqual(process.env.SALESPILOT_LOCAL_ONLY,'1','Local-only mode made an external request');
  if(!['www.splunk.com','www.sumologic.com'].includes(u.hostname))return new Response('',{status:404});
  const content=u.hostname==='www.splunk.com'?'Splunk Core supports search and analytics. Splunk Cloud Platform is a managed cloud service. Splunk Enterprise is software for self-managed deployments.':'Sumo Logic is a cloud analytics platform. Log Search queries log data using its Search Query Language. Both logging and security workflows are described in the vendor documentation.';
  return new Response('<main>'+content.repeat(3)+'</main>',{headers:{'content-type':'text/html'}});
 }
 const request=JSON.parse(options.body||'{}'),system=request.messages?.[0]?.content||'';
 if(/live competitive discussion/.test(system))return Response.json({message:{content:JSON.stringify({answer:'Both platforms provide log analytics. Splunk offers managed Cloud Platform and self-managed Enterprise deployments; Sumo Logic documents a cloud analytics platform and its Search Query Language.',sourceIds:['S1','S2','S3'],supported:true})}});
 if(/summarizing a live/.test(system))return Response.json({message:{content:JSON.stringify({recap:'Synthetic discovery and evaluation criteria.',next_steps:[]})}});
 if(/helping a Splunk solutions engineer/.test(system))return Response.json({message:{content:JSON.stringify({answer:'Splunk supports search and analytics.',sourceIds:['S1'],supported:true})}});
 return Response.json({message:{content:JSON.stringify({coverage:{},next_questions:[{anchor:'inconsistent dashboards',text:'Let me show you these inconsistent dashboards in a demo now?',targets:'identify_pain',why:'Synthetic forbidden demo proposal'}],people:[]})}});
};

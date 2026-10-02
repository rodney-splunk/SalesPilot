// Isolated model transport for answer request ordering. No network or audio.
globalThis.fetch=async(_url, options={})=>{
 const request=JSON.parse(options.body||'{}');
 const system=request.messages?.[0]?.content||'';
 if(system.includes('helping a Splunk solutions engineer')){
  await new Promise(resolve=>setTimeout(resolve,500));
  return Response.json({message:{content:JSON.stringify({answer:'Retention can be configured to 30 days.',sourceIds:['S1'],supported:true})}});
 }
 if(/summariz/i.test(system)) return Response.json({message:{content:'Synthetic retention discussion.'}});
 return Response.json({message:{content:JSON.stringify({coverage:{},next_questions:[]})}});
};

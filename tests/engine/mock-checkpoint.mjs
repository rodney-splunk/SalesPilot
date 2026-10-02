import assert from 'node:assert/strict';
globalThis.fetch=async(url,options={})=>{
 assert.equal(new URL(url).hostname,'localhost');
 const request=JSON.parse(options.body||'{}'), prompt=request.messages?.map(m=>m.content).join('\n')||'';
 if(/THE REP IS MID-DEMO/.test(prompt)) return Response.json({message:{content:JSON.stringify({coverage:{},next_questions:[{anchor:'four separate consoles',text:'How does this dashboard compare to checking those four separate consoles today?',targets:'identify_pain',why:'Compare demonstrated capability with customer workflow'}]})}});
 if(/summarizing a live/.test(prompt))return Response.json({message:{content:JSON.stringify({recap:'Synthetic call.',next_steps:[]})}});
 return Response.json({message:{content:JSON.stringify({coverage:{},next_questions:[],people:[]})}});
};

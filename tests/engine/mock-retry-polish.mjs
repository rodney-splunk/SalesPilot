import './mock-purpose-competition.mjs';
const original=globalThis.fetch;
let failed=false;
globalThis.fetch=async(url,options={})=>{
 const u=new URL(url);
 const request=JSON.parse(options.body||'{}');
 if(u.hostname==='localhost' && /live competitive discussion/.test(request.messages?.[0]?.content||'') && !failed){failed=true;throw Error('Synthetic answer provider outage');}
 if(u.hostname==='www.sumologic.com' && u.pathname.includes('pricing'))await new Promise(r=>setTimeout(r,1200));
 return original(url,options);
};

import {createInterface} from 'node:readline';
const input=createInterface({input:process.stdin});
const reply=(id,result)=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',id,result})+'\n');
let initialized=false;
for await(const line of input){
 const m=JSON.parse(line);
 if(m.method==='initialize'){await new Promise(r=>setTimeout(r,650)); initialized=true;reply(m.id,{protocolVersion:'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'fixture',version:'1'}});}
 if(m.method==='tools/call'){
  if(!initialized)throw Error('Request arrived before initialization');
  const value=m.params.name==='search_splunk_docs'
   ?{results:[{title:'Retention',url:'https://help.splunk.com/retention'},{title:'Failed read',url:'https://docs.splunk.com/failure'}]}
   : m.params.arguments.url.includes('failure') ? {error:'Read failed: 403',url:m.params.arguments.url}
   : {title:'Retention',content:'# Retention\n\nRetention configuration requires an explicit policy.\n\nA synthetic test example uses 30 days.',url:m.params.arguments.url};
  reply(m.id,{content:[{type:'text',text:JSON.stringify(value)}]});
 }
}

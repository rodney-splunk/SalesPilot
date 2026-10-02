// Conversation quality scenarios, derived from the useful moves in the shadowed call.
import {performanceSnapshot} from './performance.mjs';
import {writeFileSync} from 'node:fs';
import { fastTier } from './core.mjs';
import { PACKS } from './packs.mjs';
import {callNotes,callContext,valueGuidance} from './call-memory.mjs';
const cases = [
 {name:'Workflow before commercial qualification',text:'me: What led you to take this call?\ncust: Our analysts investigate alerts by checking four consoles one at a time.',
  reject:/budget|sign.?off|approv|procurement|economic/i},
 {name:'Stay with a concrete operational consequence',text:'me: What happens when that investigation takes too long?\ncust: We miss the triage SLA and the incident stays open for six hours.',reject:/budget|vendor|procurement|demo/i},
 {name:'Clarify a bottleneck without assuming its cause',text:'me: Where does the investigation slow down?\ncust: We wait for another team to send the firewall logs.',reject:/licens|price|budget|seven|splunk/i},
 {name:'Useful demo checkpoint',text:'cust: Our analysts check four separate consoles by hand each morning.\nme: Let me show you the correlated search view.\ncust: Okay.',
  guidance:'THE REP IS MID-DEMO. Ask one checkpoint comparing the correlated search view with the way their analysts check four consoles today. Anchor on the earlier customer statement.',opts:{anchorWindow:3},require:/compar|today|current|now|replace|consoles|by hand/i},
 {name:'An acknowledgement does not invent a new thread',text:'cust: Our analysts investigate alerts in a legacy SIEM.\nme: What happens when an alert is missed?\ncust: Right, yeah exactly.',empty:true},
 {name:'Uncertain transcription does not invent retention',text:'cust: The retention is uh is like the the seven I mean.',empty:true},
 {name:'Do not re-ask an answered timeframe',text:'me: How long does investigation take?\ncust: About six hours per incident because we have to pull logs from four consoles.',reject:/how (?:long|many hours|much time).*(?:investigation take|investigat(?:e|ing) an incident|per incident)|budget|procurement/i},
 {name:'Explore the outcome the customer actually wants',text:'cust: We need our analysts to find the root cause without waiting for the network team.',reject:/budget|procurement|demo|what is the cost/i},
];
const fullCall = [
 {id:1,me:false,side:'customer',text:'Our analysts wait six hours for the network team to send Palo Alto firewall logs.'},
 {id:2,me:false,side:'customer',text:'We miss our triage SLA while waiting, and my team works weekends to catch up.'},
 ...Array.from({length:65},(_,i)=>({id:3+i,me:true,side:'presenter',text:'Let me show you the correlated search view and this navigation panel.'})),
 {id:80,me:true,side:'seller',text:'The correlated search view is on screen now.'},
 {id:81,me:false,side:'customer',text:'Okay, I see that.'},
];
const memory=callNotes(fullCall);
cases.push(
 {name:'Technical bottleneck to business consequence',text:'cust: We wait six hours for the network team to send the firewall logs.\nme: What happens while you wait?\ncust: Incidents stay unresolved and we miss our triage SLA.',require:/sla|unresolved|incident|triage/i,reject:/budget|procurement|demo/i},
 {name:'Personal impact stays on team responsibilities',text:'cust: My team spends weekends catching up on those incident investigations.\nme: What does that take time away from?\ncust: We keep postponing our planned engineering work.',require:/planned|engineering|postpon|work|team|weekend/i,reject:/budget|procurement|career|promotion/i},
 {name:'Long demo uses opening evidence for comparison',text:callContext(fullCall,memory),guidance:valueGuidance(memory)+' THE REP IS MID-DEMO. Return one checkpoint comparing the correlated search view just shown with the earlier six-hour wait for firewall logs.',opts:{anchorWindow:40,evidenceTranscript:fullCall.filter(t=>!t.me).map(t=>t.text).join('\n')},require:/compar|today|current|now|wait|firewall|search/i,reject:/budget|procurement|book.*demo/i},
 {name:'Do not ask a quantity already established',text:"cust: We ingest 45 gigs of Palo Alto firewall logs each day.\nme: How does the team use those logs?\ncust: Analysts switch between four consoles to investigate alerts.",opts:{evidenceTranscript:'We ingest 45 gigs of Palo Alto firewall logs each day. Analysts switch between four consoles to investigate alerts.'},require:/analyst|console|investigat|switch|alert/i,reject:/how (?:much|many).*gigs|budget|procurement/i}
);
let passed=0;
for (const scenario of cases) {
 const output=JSON.parse(await fastTier(PACKS.meddic,scenario.text,scenario.guidance || valueGuidance([]),null,scenario.opts||{}));
 const questions=output.next_questions||[];
 const text=questions[0]?.text||'';
 const ok=scenario.empty ? questions.length===0 : questions.length===1 && text.includes('?') && (!scenario.reject||!scenario.reject.test(text)) && (!scenario.require||scenario.require.test(text));
 console.log(`${ok?'PASS':'FAIL'} ${scenario.name}: ${text||'(wait)'}`);
 if(ok)passed++;
}
console.log(`${passed}/${cases.length} quality scenarios passed`);
if(process.env.DISCOVERY_REPORT)writeFileSync(process.env.DISCOVERY_REPORT,JSON.stringify({scope:"Synthetic discovery-quality cases against a real provider; not end-to-end call latency",passed,total:cases.length,performance:performanceSnapshot()},null,2));
process.exitCode=passed===cases.length?0:1;

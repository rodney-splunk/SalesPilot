import assert from 'node:assert/strict';
import {callNotes,callContext,valueGuidance} from './call-memory.mjs';
import {questionIssues} from './core.mjs';
const t=(id,text,side='customer')=>({id,text,side,me:side==='seller',who:side==='seller'?'You':'Dana'});
const turns=[
 t(1,"We're using Palo Alto firewalls and bringing in 45.5 gigs of those logs."),
 t(2,'Our analysts spend six hours waiting for the network team to send firewall logs.'),
 t(3,'That delays our triage SLA and puts our business at risk.'),
 t(4,'My team spends weekends doing manual cleanup instead of our planned work.'),
 t(5,'We need to investigate without waiting for another team.'),
 t(6,'Let me show you a product dashboard with 100 gigs per day.','presenter'),
 t(7,'For example, we could say we ingest 999 gigs of data.'),
 t(8,'How many firewalls could Splunk monitor?'),
 t(9,'We are not using Fortinet firewalls.'),
 t(10,'Actually, I meant roughly 46 gigs of firewall logs.'),
 t(11,'We will send the firewall inventory before the next meeting.'),
 t(12,'Yes, okay, thank you.'),
];
const notes=callNotes(turns);
assert.ok(notes.some(n=>n.quote.includes('45.5 gigs')),'decimal and unit survive');
assert.ok(!notes.some(n=>/45.5 gigs.*day/.test(n.quote)),'no invented period');
assert.ok(!notes.some(n=>/100|999/.test(n.quote)),'presenter and hypothetical numbers excluded');
assert.ok(!notes.some(n=>n.quote.endsWith('?')),'questions are not customer facts');
assert.ok(notes.some(n=>n.quote.includes('not using Fortinet')),'negation retained');
assert.ok(notes.some(n=>n.correction && n.tentative && n.quote.includes('46 gigs')),'correction and uncertainty retained');
assert.ok(notes.some(n=>n.categories.includes('business')) && notes.some(n=>n.categories.includes('personal')),'impact layers retained');
assert.equal(callNotes([turns[0],{...turns[0],id:20}]).length,1,'identical statements deduplicated');
assert.equal(callNotes([{...turns[0],side:'unknown'}])[0].speakerUnconfirmed,true,'unknown role stays explicit');
assert.equal(callNotes([{...turns[0],side:'seller'}]).length,0,'manual seller attribution removes notes');
const long=[...turns,...Array.from({length:90},(_,i)=>t(i+20,`Let me show you navigation panel ${i} and the correlated search view.`,'presenter')),t(150,'How does that compare to the firewall investigation workflow?','seller')];
const context=callContext(long,callNotes(long));
assert.ok(context.includes('45.5 gigs') && context.includes('six hours') && context.includes('weekends'),'beginning-of-call facts survive long demonstration');
assert.ok(context.length<17000,'context remains bounded');
assert.ok(valueGuidance(notes).includes('personal'),'guidance includes respectful personal impact');
const norm=x=>x.toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
assert.deepEqual(questionIssues({anchor:'firewall logs',text:'How does this compare with the way your team investigates firewall logs today?',targets:'identify_pain'},norm('firewall logs'),'MEDDPICC',norm(context)),[],'natural comparison accepted');
assert.deepEqual(questionIssues({anchor:'firewall logs',text:'Does waiting for those firewall logs keep your team from its other work?',targets:'identify_pain'},norm('firewall logs'),'MEDDPICC',norm(context)),[],'confirming question accepted');
assert.ok(questionIssues({anchor:'firewall logs',text:'How do 99 gigs affect your firewall investigation?',targets:'metrics'},norm('firewall logs'),'MEDDPICC',norm(context)).some(x=>x.includes('invented')),'invented quantity still rejected');
assert.deepEqual(questionIssues({anchor:'firewall logs',text:'How does waiting for those firewall logs affect the six hours your team spends investigating?',targets:'metrics'},norm('firewall logs'),'MEDDPICC',norm(context)),[],'grounded earlier quantity accepted without latest-turn-only rejection');
const contrast=callNotes([t(200,'They used Splunk in the past, not for observability, but for security monitoring.')]);
assert.equal(contrast[0].correction,false,'ordinary contrast is not a corrected fact');
const duplicatePeople=callNotes([t(201,'We use Palo Alto firewall logs.'),{...t(202,'We use Palo Alto firewall logs.'),who:'Joe'}]);
assert.equal(duplicatePeople.length,2,'identical statements retain both speakers');
assert.equal(callNotes([t(203,'We also want to try and monitor')]).length,0,'unfinished monitoring objective is not a complete note');
console.log('PASS 19 call memory, notes provenance, impact, and conversational validation checks');

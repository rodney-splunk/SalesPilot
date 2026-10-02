import assert from 'node:assert/strict';
import {prepPeople,reconcilePreparedName} from './call-name-hints.mjs';
import {documentationQuery,rankDocumentation} from './splunkdocs.mjs';
import {participantIntro} from './participants.mjs';
import {referenceRequest,references} from './answer-policy.mjs';
import {callNotes} from './call-memory.mjs';
import {dialoguePlan} from './dialogue-plan.mjs';
import {opportunities} from './opportunities.mjs';
const people=prepPeople('People: Jesse Yang — customer, security director; Rodney White — Splunk, host; Nancy Xiao — Cisco, manager');
assert.deepEqual(people.map(p=>p.name),['Jesse Yang','Rodney White','Nancy Xiao']);assert.equal(people[0].side,'customer');assert.equal(people[1].side,'seller');
assert.equal(reconcilePreparedName('Jessie Yang',people),'Jesse Yang');assert.equal(reconcilePreparedName('Jeff Yang',[...people,{name:'Jeff Yang'}]),'Jeff Yang');assert.equal(reconcilePreparedName('Joe Yang',people),'Joe Yang');
assert.equal(reconcilePreparedName('Jessie Yang',[...people,{name:'Jessi Yang'}]),'Jessie Yang','ambiguous surname stays unresolved');
assert.equal(participantIntro('My name is Jesse Yang.').name,'Jesse Yang');
const docs=[{url:'https://help.splunk.com/en/splunk-on-call/dashboard',title:'Splunk On-Call dashboard'},{url:'https://help.splunk.com/en/splunk-enterprise/search',title:'Search your data'}];
assert.equal(rankDocumentation(docs,'On this call right now, can Splunk search our logs?').length,1);assert.equal(rankDocumentation(docs,'How does the Splunk On-Call dashboard work?').length,2);assert.ok(!documentationQuery('On this call right now, can Splunk search our logs?').includes('call'));
assert.equal(opportunities([])[0].id,'core');const fit=opportunities([{id:1,text:'Our SIEM produces false positives and our analysts miss important alerts in triage.',side:'customer'}]);assert.equal(fit[0].id,'core');assert.ok(fit.find(p=>p.id==='es'));assert.equal(fit[1].status,'Additional fit to validate');


assert.equal(referenceRequest('Can you show me that on the call today?', [{text:'We have no dashboards and have AWS and firewall logs.'}]),null);assert.equal(dialoguePlan('Can you show me that on the call today?').kind,'respond');assert.equal(reconcilePreparedName('Jessi',people),'Jesse Yang');assert.equal(reconcilePreparedName('Jessey',people),'Jesse Yang');

assert.equal(references([],[{title:'Splunk On-Call dashboard',url:'https://help.splunk.com/en/splunk-on-call/dashboard',body:'Dashboard instructions.'}],'Can you show that on this call?').length,0);
assert.equal(references([],[{title:'Splunk On-Call dashboard',url:'https://help.splunk.com/en/splunk-on-call/dashboard',body:'Dashboard instructions.'}],'How does the Splunk On-Call dashboard work?').length,1);

assert.equal(participantIntro('My name is José Muñoz from customer.').name,'José Muñoz');

assert.equal(participantIntro('This is Splunk Cloud.'),null);

console.log('PASS prepared names, Unicode introductions, ambiguity guards, call-vs-product routing and Core-first opportunities');

const notes=callNotes([{id:1,text:'We ingest 45 GB of firewall logs per day.',who:'Jesse Yang',side:'unknown',clusterId:4},{id:2,text:'Actually, we ingest 50 GB of firewall logs per day.',who:'Jesse Yang',side:'unknown',clusterId:4}]);assert.equal(notes[0].supersededBy,2);
assert.equal(callNotes([{id:1,text:'We collect firewall logs and',who:'Jesse Yang',side:'customer'}]).length,0);

assert.equal(people[1].role,'Splunk, host','leading separator whitespace does not corrupt the role');

assert.equal(prepPeople('Context: The customer name is Jesse Yang.')[0].name,'Jesse Yang');

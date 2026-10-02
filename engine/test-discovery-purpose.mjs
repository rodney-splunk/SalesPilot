import assert from 'node:assert/strict';
import {dialoguePlan} from './dialogue-plan.mjs';
import {demoRequest,discoverySafeCue,purposeGuidance} from './call-purpose.mjs';
for(const request of ['Can you give us a demo today?','Show me that on this call.','We were hoping to see a firewall demo','Could you share your screen now?']){
 assert.equal(dialoguePlan(request,[],{mode:'discovery'}).kind,'redirect',request);
 assert.match(dialoguePlan(request,[],{mode:'discovery'}).question,/today.*next step/);
 assert.notEqual(dialoguePlan(request,[],{mode:'standard'}).kind,'redirect');
}
for(const text of ['The demo last week was helpful.','I do not need a demo today.','Can we book a demo next week?','Can you explain how Splunk ingests firewall logs?','Can you show me how Splunk ingests data?'])assert.equal(demoRequest(text),false,text);
assert.equal(dialoguePlan('Can Splunk retain logs for 30 days?',[],{mode:'discovery'}).kind,'answer');
assert.equal(dialoguePlan('How do you compare to Sumo Logic?',[],{mode:'discovery'}).request.category,'competition');
assert.equal(discoverySafeCue('Let me show you this dashboard.'),false);assert.equal(discoverySafeCue('What would a useful demo need to prove?'),true);assert.match(purposeGuidance('discovery'),/DISCOVERY-ONLY/);
console.log('PASS discovery-only demo redirects, standard mode, future/past/negative guards, technical and competitive answers');

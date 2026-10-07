import assert from 'node:assert/strict';
import {partialEvidence} from './coverage-evidence.mjs';
const t=(id,text,side='customer')=>({id,text,side});
const turns=[t(1,'I oversee eight theaters. We have cash registers, Wi-Fi routers and switches.'),t(2,"We don't have anything capturing our data right now."),t(3,'We want to maintain uptime on those things and monitor their operations.'),t(4,'No specific requirements for uptime or downtime.'),t(5,"I'm looking at some other companies like Datadog.")];
const evidence=partialEvidence(turns);assert.ok(evidence.situation&&evidence.problem&&evidence.need_payoff&&evidence.competition);assert.ok(!evidence.implication,'desired uptime is not established business impact');
assert.deepEqual(partialEvidence(turns.map(t=>({...t,side:'seller'}))),{});
assert.deepEqual(partialEvidence(turns.map(t=>({...t,speakerStatus:'mixed'}))),{});
assert.deepEqual(partialEvidence([t(8,'For example, we want to maintain uptime.')]),{});
assert.deepEqual(partialEvidence([t(9,'Do we have Wi-Fi routers?')]),{});
assert.ok(partialEvidence([t(10,'The delay means we miss our triage SLA.')]).implication);
console.log('PASS customer provenance, literal partial coverage, unknown impact, speaker exclusions and question/hypothetical safeguards');

for (const text of ['The delays put our incident response target at risk.', 'My analysts sometimes work late to catch up.']) {
 const result=partialEvidence([t(11,text)]);assert.equal(result.implication?.turnId,11);assert.equal(result.implication.quote,text);
 assert.ok(!partialEvidence([t(11,text,'seller')]).implication);
 assert.ok(!partialEvidence([t(11,'Hypothetically, '+text)]).implication);
}
for (const text of ['Our analysts do not work late.', 'The delays do not put our incident response target at risk.', 'Do your analysts sometimes work late?', 'We want to improve incident response targets.']) assert.ok(!partialEvidence([t(12,text)]).implication);
console.log('PASS response-target risk and personal overtime are partial customer evidence; denials, questions and aspirations stay open');

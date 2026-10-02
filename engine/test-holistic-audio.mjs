// Run after local ASR; input is the synthetic fixture's transcript, not prerecorded ground truth.
import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
import {partialEvidence} from './coverage-evidence.mjs';import {callContext,callNotes} from './call-memory.mjs';
assert.ok(process.argv[2],'Provide the locally transcribed fictional fixture');
const text=readFileSync(process.argv[2],'utf8');
const turns=text.split(/(?<=[.!?])\s+/).map((text,id)=>({id,text,side:'customer',me:false,who:'Synthetic customer'}));
const evidence=partialEvidence(turns,t=>t.side),context=callContext(turns,callNotes(turns,t=>t.side),'',t=>t.side);
for(const id of ['situation','problem','implication','need_payoff'])assert.ok(evidence[id]?.evidence.length,id);
for(const phrase of ['45 gigabytes','six hours','work weekends','response commitment','one hour'])assert.ok(context.includes(phrase),phrase);
console.log(`PASS actual local ASR → early/middle/late SPIN evidence and contextual memory (${turns.length} statements)`);

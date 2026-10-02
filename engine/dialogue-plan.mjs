import {callPurpose,demoRequest,discoveryRedirect} from './call-purpose.mjs';
import {competitiveRequest,competitorTechnicalRequest} from './competition.mjs';
import {completedThought} from './coach-timing.mjs';
import {referenceRequest} from './answer-policy.mjs';
export function dialoguePlan(text, prior=[], options={}) {
 if(!completedThought(text))return {kind:'listen',reason:'Let the customer finish their thought.'};
 if(callPurpose(options.mode)==='discovery' && demoRequest(text))return {kind:'redirect',question:discoveryRedirect(text),target:'Discovery focus',reason:'Acknowledge the demo request and use discovery to define a useful next-step demo.'};
 const competitive=competitiveRequest(text,prior);if(competitive)return {kind:'answer',request:competitive,reason:'Answer the competitive question from verified sources, then validate the customer’s criteria.'};
 if(/\b(?:can|could|would) you (?:show|demonstrate|pull up)\b/i.test(text) && /\b(?:on|during) (?:this|the|our) call\b/i.test(text) && !/\b(?:how|support|integrat|deploy|licens|pricing)\b/i.test(text))return {kind:'respond',customerQuestion:{query:text},reason:'Respond to their demonstration request using the current conversation; do not search for Splunk On-Call.'};
 const vendorCapability=competitorTechnicalRequest(text,prior);if(vendorCapability)return {kind:"answer",request:vendorCapability,reason:"Answer the named product capability from its own documentation; this is not a competitive positioning question."};
 const request=referenceRequest(text,prior);
 if(/\bwindows\s+syslogs?\b/i.test(text)&&!(/\b(?:both|windows event logs.{0,40}syslog|syslog.{0,40}windows event logs)\b/i.test(text)))return {kind:'clarify',question:'Do you mean Windows Event Logs, syslog from network devices, or both?',reason:'Confirm the source type before recommending a collection path.'};
 if(request)return {kind:'answer',request,reason:'Resolve the customer’s product question before opening another discovery thread.'};
 if (/\?\s*$/.test(text)||/^(?:what|who|when|where|how|why|can|could|would|do|does|is|are)\b/i.test(text.trim())) return {kind:'respond',customerQuestion:{query:text},reason:'Answer the customer’s question before discovery.'};
 if (/\b(?:mean time to detect|detection time)\b/i.test(text) && /\b(?:hours?|minutes?)\b/i.test(text)) {
   const question = 'Where does most of the delay happen before your team detects an issue?';
   if (!prior.some(t=>/\b(?:where|what).{0,60}(?:delay|detect)/i.test(t.text) && /\?/.test(t.text))) return {kind:'explore',question,target:'Problem',reason:'Understand the detection bottleneck without confusing it with investigation time.'};
 }
 if (/\bno\b.{0,55}\b(?:formal|specific|actual)\b.{0,35}\brequirements?\b/i.test(text) && /\b(?:uptime|downtime)\b/i.test(text) && prior.some(t=>/\b(?:monitor|uptime|downtime|theaters?|venues?)\b/i.test(t.text))) {
   const venues = prior.some(t=>/\b(?:theaters?|venues?)\b/i.test(t.text));
   return {kind:'explore',question:venues?'Which service disruption would cause the most trouble during a busy showing?':'Which service disruption would cause the most trouble for your team?',reason:'Explore service criticality without inventing an SLA or business impact.'};
 }
 return {kind:'explore',reason:'Explore the smallest useful gap in the customer’s current topic.'};
}
export function discoveryGuidance() {
 return 'Choose one smallest useful follow-up, using the customer’s current topic and earlier answers. First understand a real example and the technical workflow; quantify effort after you understand that workflow. Then explore a business consequence the customer has actually identified, and later the person’s responsibility or effort. These are not three mandatory questions per turn. Never invent revenue loss, stress, authority, a demonstration, or a preference. A stated role does not need another responsibilities question. Distinguish detection time from investigation time. When uptime has no formal target, that is not a refusal to discuss monitoring: ask which service disruption matters or how failures are detected, rather than repeating the SLA question. Phrase delays neutrally: ask where time is spent, not what the team does that prevents success. For audit risk, ask which requirement is hard to demonstrate; do not presume missing controls or the cause of a prior failure. Ask what the evaluation must demonstrate before pitching a product. After an actual demonstration, ask how it compares with their current workflow. Do not ask what has already been answered. A product question requires an answer or clarification first, not another discovery question. Return no next_questions when listening or an answer is the useful action.';
}

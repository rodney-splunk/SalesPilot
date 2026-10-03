# Leadership presentation preparation

Planning window: October 5–9, 2026; exact presentation day not yet provided. Owner: unassigned until the presenter confirms. This is a readiness runbook, not evidence that rehearsal or the new examples are finished.

## Presentation script: Stay with the customer

Delivery: approximately 6–8 minutes with the fictional walkthrough. Use the pauses to let the audience absorb the idea; do not read the bracketed directions aloud. Demonstrate the installed behavior rather than promising accuracy or outcomes that have not been measured.

### Open with a moment they recognize

Think about the last good customer conversation you had.

Someone explained how their team works. Somewhere in that explanation, they mentioned a delay. A workaround. Something that was costing them more than they realized.

And you had a choice.

Follow that thought—or look down and write it down.

[Pause. Keep the app hidden for the opening.]

That is the tension in discovery. We want to give the customer our full attention. At the same time, we are remembering details, choosing the next question, and deciding which answers we need to verify.

The conversation keeps moving while we do all of that.

I built SalesPilot around one idea:

**Help us stay with the customer.**

### Reveal the product through three jobs

[Show the clean workspace.]

There are three things I want help with during a call.

Remember what matters.

Find the question worth asking next.

Bring the evidence when I need an answer.

SalesPilot brings those three jobs into the conversation.

Let me show you what that means with a fictional customer.

### Tell one customer story

[More → Show example. Keep Coach visible.]

Dana leads a security operations team. She tells us, “Our analysts wait six hours for the network team to send firewall logs.”

We could hear that and immediately think: log collection. We have a product for that.

But we have only heard the beginning of the story.

Six hours matters because of what happens during those six hours.

[Point to the transcript and the contextual follow-up. Read the actual question displayed; do not substitute a rehearsed line and imply the app generated it.]

A useful next question stays with her experience. What does that delay mean for the team?

Dana explains that they miss their triage SLA. Then she tells us her team works weekends to catch up.

Now we understand more than a technical requirement.

There is a technical problem: access to the logs.

There is a business consequence: the missed SLA.

And there is a personal consequence: people giving up their weekends.

That is the value-selling connection I want us to preserve.

### Show how discovery becomes value

[Show SPIN coverage, then open the supporting transcript evidence.]

The framework helps us see how far we have gone.

We understand the situation. We have evidence of a problem. We can explore the implication.

The next step is to understand what a better outcome is worth to Dana.

For example: “If your analysts could investigate without waiting on another team, what would that change for you?”

That is an illustrative discovery question. During the demo, the actual suggestion is the one on screen.

The framework gives us a direction. The customer's answer gives us the substance.

SalesPilot shows the evidence behind its coverage so we can judge it, correct it, and decide where to go deeper.

### Make the other two jobs visible

[Open Notes.]

While we are listening, the call details have somewhere to go.

The firewall source. The volume. The delay. The impact.

Dana initially says 45 gigs, then corrects it to roughly 46. That correction belongs in our understanding of the call.

These notes are there for us to review. They help us carry the conversation forward without relying entirely on memory.

[Open Research → Answers.]

Then Dana asks a question: “Which is more expensive, Splunk Cloud or Enterprise?”

A confident guess would be easy. A useful answer needs scope.

What workload are we comparing? What support? Who is operating the infrastructure?

Here we can review an answer alongside its sources and identify what still needs confirmation. We choose what to say to the customer.

[Select Competitive.]

If she asks how Splunk compares with Sumo Logic, that is still an answer—but it needs competitive context.

So it lives here too, inside Answers.

Today, these comparisons use documentation, with internal CI references available separately. Direct retrieval of vetted Klue wording is on the roadmap; it is not connected yet.

### Show that the customer still sets the direction

[Return to Coach. Show the final demo request.]

Now Dana asks for a demo.

Sometimes a demo belongs in today's conversation. Sometimes today's purpose is to understand what the next demo needs to prove.

That is why there are two modes.

Flexible conversation supports a mixed agenda.

Discovery first helps us establish the customer's needs and agree on a focused next step before jumping into a demo.

[If time allows, show the same fictional example in the other mode. Read the actual displayed response.]

In either case, the goal is to make the next step relevant to what Dana has told us.

### Close on the customer outcome

[Return to the clean Coach view. Pause.]

At the beginning, we heard: “We need firewall logs.”

By the end, we understand a team waiting six hours, missing its SLA, and spending weekends catching up.

That changes the conversation we should have. It changes the demo we should prepare. And it changes how we describe the value of solving the problem.

That is what I want SalesPilot to help us do more consistently.

**Stay with the customer. Understand what matters. Make the next step count.**

### Pilot discussion, after the story

This walkthrough is fictional. Questioning speed has improved in my recent use, but the next gates include a two-to-three-hour endurance test, more natural multi-speaker testing, and measured end-to-end latency. Organization-specific compliance and deployment reviews remain open.

For the pilot, I want to measure whether the suggestions stay relevant, whether notes preserve the customer's meaning, and whether the tool helps us uncover technical, business, and personal value. Those outcomes need evidence from real use.

The leadership decision I would ask for is a scoped pilot with agreed success measures and the right CI and security partners involved.

## Rehearsal checklist

- [ ] Confirm presentation time, Mac/display, expected duration, audience and permitted live data.
- [ ] Finish DEMO-01/02; no claimed behavior shown only in a roadmap.
- [ ] Record exact commit/build, model/runtime prerequisites and signed candidate location.
- [ ] Run safe checks and native isolated checks on final build; inspect light/dark and minimum/default workspace layout.
- [ ] Verify both examples, mode persistence, arrow navigation, source links, compact/workspace and clean exit/reset.
- [ ] Two full rehearsals: connected and unavailable network. Explain expected Needs confirmation gracefully.
- [ ] Choose either explicitly fictional walkthrough or approved live synthetic test; label it accurately.
- [ ] Prepare local screenshots/short fictional recording as fallback; do not include real customer content or credential screens.
- [ ] Freeze the candidate at least one working day before presenting; record unresolved issues rather than modifying runtime immediately before the session.
- [ ] Leave no actual call capturing, and do not change audio devices during someone else's call.

## Honest answers to likely questions

- **Where does data go?** Audio transcription is local. Cisco mode can send selected masked text/public evidence to Cisco; local-only blocks hosted inference and public reads. Masking is not complete DLP.
- **Does it identify everybody?** Current-call corrections/introductions and local voice continuity exist. Natural multi-party/overlap certification is unfinished; unresolved speech must remain visible.
- **Can colleagues use it?** Private source repository and detailed setup exist. Each developer builds locally and provisions own approved access. Portable approved binary distribution is not done.
- **Is it approved?** Engineering safeguards exist; organization-specific reviews and deployment decisions remain open.
- **How fast is it?** Synthetic checks exist; production end-to-end p50/p95 remains a release gate. Do not present provisional targets as guarantees.
- **Does competition work?** A real synthetic Cisco/Sumo comparison passed. The remaining catalog requires individual live source acceptance; unavailable evidence stays unconfirmed.

## If something fails

Stop that demonstration path, name the observed limitation and show clearly labeled fictional/offline material. Do not grant new permissions, enter/display secrets, swap models or troubleshoot a recording workflow on stage. Capture an appropriately redacted defect after the presentation.

## Feedback capture

Record the user problem, desired behavior, severity, scenario and suggested roadmap ID. Keep private customer details out of public/repository issue bodies. No promise of delivery without an assigned owner and acceptance criteria.

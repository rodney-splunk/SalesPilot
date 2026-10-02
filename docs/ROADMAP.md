# SalesPilot product and engineering roadmap

Updated October 2, 2026. Canonical roadmap for contributors. This is a prioritized plan, not a claim that every feature or customer-call scenario is certified. The presentation is next week (October 5–9); the exact day and audience requirements are not yet specified. Dates below are planning checkpoints, not promised completion dates.

## Product objective and boundaries

Help an SE listen, ask a natural next question, retain customer context and verify answers during discovery. Keep the live screen calm: Coach, Notes and Research, with Answers/Opportunities nested in Research; Answers includes technical and competitive categories. Start positioning from Splunk Core; premium applications require evidence of customer need.

Modes: **Flexible conversation** supports a mixed agenda. **Discovery first** keeps today focused on needs and redirects immediate demo requests toward a tailored follow-up. Choose during onboarding or More → Call mode, before capture. Both retain technical/competitive answers, notes and methodology coverage.

Names and voice identity are call-scoped. Do not reintroduce a people library or cross-call voice enrollment. Do not invent identities to conceal unresolved speech. No automatic customer email, Salesforce write, Slack write or meeting booking. New integrations and cloud destinations require deliberate scope and review.

## How to read and maintain this plan

- **Implemented / validation open:** behavior exists, but the listed acceptance evidence remains missing.
- **Verified in stated scope:** a specific synthetic, local, live-provider or UI check passed; do not extend that claim to all scenarios.
- **Planned:** work has not been implemented.
- **External decision:** needs an accountable organization owner; coding alone cannot close it.
- **P0:** milestone blocker. **P1:** important improvement after blockers. **P2:** later enhancement.

Every open item is **unassigned** until a contributor claims it in a GitHub issue. “Role” identifies the needed expertise, not an assigned person. Use the stable ID in the issue title, branch/PR description and evidence record. Break large items into independently reviewable child issues. Update this document when scope or status changes; never close an item only because code compiles.

## Current baseline and evidence

| Capability | Current state | Evidence and remaining limit |
| --- | --- | --- |
| Native workspace and compact window | Implemented | Workspace lifecycle checks pass; another developer's fresh Mac is not yet accepted |
| Mode chooser and onboarding | Implemented | Installed UI verified; selection persists, selector under More, six-step guide; distinct mode demos pass native checks |
| Local transcription and speaker continuity | Implemented / validation open | Synthetic timed-ASR/voice checks; natural accents, devices and overlap remain open; true overlapping speech is not separated |
| Natural cues and methodology evidence | Implemented / validation open | Synthetic continuity/coverage checks and user feedback; production latency and unseen-call quality need measurement |
| Notes and question ledger | Implemented / validation open | Fragment/correction/context regressions; generated answers remain open until delivered or deferred; broader natural-call review pending |
| Sources and competitive research | Implemented / validation open | Actual Cisco comparison with official Splunk/Sumo sources passed; 12-vendor detection catalog is not 12-vendor live acceptance |
| Consent, local-only mode and Keychain | Implemented / policy review open | Negative-egress and consent checks pass; classification, retention and organizational approvals remain external |
| Private collaboration repository | Available | Source-only build passed, 24 selected engine suites and 13 native offline checks passed; coworker access/setup pending username |
| Endurance and recovery | Implemented / validation open | Prior one-hour run retained 359 turns; final recap assertion failed on malformed fixture. Short corrected checks passed; full-hour finalization retest remains open |

The above summarizes prior checks; this roadmap update runs no new audio/provider acceptance. Local qwen2.5:14b quality testing previously measured inference p50 4.43s / p95 6.17s; this is not full end-to-end production latency and does not meet the provisional 4-second cue target. Preserve initial failed results with retest evidence.

## Milestone A — polished leadership presentation

Use fictional data and an explicitly described pilot. A curated example demonstrates intended behavior; it does not prove live transcription/model accuracy. Resolve P0 items before calling the presentation rehearsed. See [presentation runbook](PRESENTATION.md).

| ID / priority | Deliverable and state | Acceptance criteria | Dependencies / role |
| --- | --- | --- | --- |
| DEMO-01 P0 | Two distinct mode examples — Implemented; native acceptance passed | Verified October 2: both fictional examples show the same immediate demo request with different transcript/Next Move cues; 13 native checks pass. Flexible example explores a mixed/demo agenda; Discovery first redirects naturally and asks a contextual discovery question. Each clearly labeled fictional; switching modes updates transcript and Next Move consistently; exit returns to actual state; no capture or hosted request | Native UI + coaching |
| DEMO-02 P0 | Guided demonstration path — Planned | Repeatable 6–8 minute story: prep → mode → transcript/cue → framework evidence → notes/correction → sourced answer → competition → recap. No empty/stale panel, invented claims or runtime setup needed mid-demo; presenter can reset in one action | DEMO-01; product + UI |
| UX-01 P0 | End-to-end visual polish — Validation open | Check both modes at default/minimum window sizes and light/dark appearance; no clipped controls, inaccessible source links or confusing statuses. Compact/workspace switching keeps active state; More contains secondary controls; meaningful empty/loading/error states | Native UI + QA |
| DEMO-03 P0 | Rehearsal on presentation Mac — Planned | Two complete rehearsals on the final build, one network-connected and one with network unavailable. Document version/commit, prerequisites, steps and results; demo does not depend on a last-minute login. No production call disturbed | DEMO-02, UX-01; presenter + QA |
| DEMO-04 P0 | Accurate leadership narrative — Planned | Show value, current limits, local/hosted data boundary and next decisions. Present fictional vs live evidence separately; no “Cisco approved,” “all names accurate,” “all vendors supported” or guaranteed latency claim | Presenter + product |
| DEV-01 P1 | Coworker access and fresh setup — Pending username | Verified username invited with intended developer access; second Mac clones/builds/opens both examples using its own settings. README steps work without Rodney's secrets or workspace paths | User identity; maintainer + new contributor |
| DEMO-05 P1 | Backup presentation artifact — Planned | Approved screenshots or short fictional walkthrough available locally; date/build identified; no customer data. Presenter can explain a live failure and continue without pretending offline material is a live result | DEMO-02; presenter |

### Suggested next-week checkpoints

- **Before the first rehearsal:** DEMO-01/02 and UI review; freeze the demo story, not every future feature.
- **At least one working day before the presentation:** final candidate and two rehearsals; publish evidence and list remaining gaps.
- **Presentation day:** verify readiness, use the rehearsed build, have offline fallback. No dependency/model/signing changes immediately before the session.
- **After the presentation:** turn feedback into issues; prioritize measured customer-call failures before new surface area.

Exact-day scheduling and ownership require the presenter/contributors; this file does not start a background schedule.

## Milestone B — trustworthy controlled customer pilots

P0 gates below are required before claiming customer-call readiness. Controlled evaluation requires applicable authorization/consent and documented residual limits. Failure in one gate is not hidden by a good demo.

| ID / priority | Deliverable and state | Acceptance criteria | Dependencies / role |
| --- | --- | --- | --- |
| AUDIO-01 P0 | Natural audio benchmark — Planned | Authorized local ground-truth set covering 2-person and 3–4-person calls, headset/room speakers, brief replies, introductions, name corrections, accents, interruptions, bleed and overlap. Record device/OS, methodology and consent; report missed/extra voices, confusion, unresolved duration, transcription errors and name accuracy separately | GOV-01/02; audio + QA |
| AUDIO-02 P0 | Speaker pipeline comparison — Planned | Compare current embeddings and approved local segmentation/overlap-aware alternatives on the same AUDIO-01 set; report latency/memory/error tradeoffs. Select from measured results; uncertain segments stay reviewable and excluded from evidence. No secretly hosted audio route | AUDIO-01, GOV-04; audio |
| AUDIO-03 P0 | Identity and channel acceptance — Validation open | Rodney/host label consistent across mic turns; prepared/unseen/split names, corrections and multiple colleagues never duplicate identities solely because channels change. Echo/bleed warnings require evidence and clear automatically when resolved. Do not force known names onto ambiguous voices | AUDIO-01/02; audio + engine |
| COACH-01 P0 | Full-context question quality — Validation open | Review long fictional and authorized natural conversations for topic continuity, natural language, depth and technical/business/personal impact. No unrelated pivot, repeated resolved question, unsafe demo invitation in Discovery first, or cue from incomplete/ambiguous speech. Use human ratings and publish rubric | AUDIO-01; engine + SE reviewers |
| COACH-03 P1 | Expert discovery examples — Planned | Begin with 10–20 selected, authorized Gong transcripts from multiple expert SEs. Preserve context → question → customer response, listening decisions, technical/business/personal impact and SPIN purpose. Human-review examples, retrieve relevant sequences without copying customer details; hold out whole calls/accounts for blind quality evaluation. Bryan Ting’s restricted calls remain excluded until access and intended use are explicitly authorized. Retrieval-first pilot; fine-tuning only if measured gains and training authorization justify it | COACH-01, GOV-01–02; discovery reviewers + engine |
| COACH-02 P0 | Cue display and cancellation — Validation open | Transcript and Next Question agree; new context/stop invalidates stale work; mode/detail changes preserve valid cues; interruptions do not publish obsolete suggestions. Replay corrections and rapid turn boundaries | Engine + native UI |
| PERF-01 P0 | Measured live timing — Planned | Record silence-to-final transcript, finalized-turn-to-visible cue, question-to-source-backed answer and notes freshness. Publish p50/p95/failure rates for cold/warm local and Cisco paths on reference hardware. Provisional targets: cue p95 <4s, answer p95 <10s; explicitly flag misses, do not call targets measured | Audio + engine + QA |
| ANSWER-01 P0 | Question lifecycle and context — Validation open | Direct/indirect/pronoun questions remain anchored to product context across topic changes. Ordinary “on this call” never routes to Splunk On-Call; Cloud/Enterprise ingestion comparison stays anchored. Delivered/deferred/reopened state persists; generation alone never resolves a question | Engine + QA |
| NOTES-01 P0 | Complete facts with provenance — Validation open | Preserve early-call context, product names, units and speaker; join supported fragments, retain exact correction history and transcript links. Incomplete thoughts remain incomplete; no invented completion or assumptions promoted to confirmed facts | Engine + SE reviewers |
| REL-01 P0 | Full-hour finalization — Retest pending | Repaired 60-minute fixture preserves all expected turns, notes, questions, coverage and sources; end completes recap and history within a documented bound. Repeat start/stop; isolated test does not create synthetic calls in actual history | Engine + QA |
| REL-02 P0 | Crash/recovery and outage matrix — Validation open | Native/engine/ASR crash, sleep/wake, permission loss, provider timeout, docs outage and interrupted stop have visible states and recoverable local journal; no silent loss or false Ready. Recovery sections clearly require review | Native + engine + QA |
| CI-01 P0 | Vetted Klue competitive answers — Planned; integration access/owner decision open | Use supported read-only Content API or CI-approved exports, not browser cookies or unreviewed chat summaries. API credential in Keychain; honor published-card permissions, updates/revocation and allowed CIRCUIT processing. Retrieve exact sections with competitor, product scope, reviewer/date, audience and customer-safe wording. Match Core versus Observability/ES/ITSI and latest question scope; keep internal-only positioning separate from customer-ready wording. Prefer approved talk tracks; current public docs validate factual claims. Missing/stale/conflicting CI evidence is explicit, never labeled pre-vetted. Test Datadog, Sumo and scope/negation/context routing before expanding vendors | SOURCES-01, GOV-01; CI owner + engine/platform |
| REL-03 P0 | Very long call acceptance — Planned | Extend repaired one-hour fixture to 120–180 minutes in isolated state. Measure actual elapsed-time performance: cue/answer latency p50/p95 by call segment, memory, queue backlog, ASR/speaker stability, silence/interruptions, early/middle/late/corrected context, accumulated SPIN evidence and source freshness. End writes a complete recap/history; verify turn/evidence counts and unresolved questions. Accelerated timestamp replays supplement but do not certify wall-clock endurance. Follow with an authorized natural call and production-model run | REL-01, AUDIO-01, COACH-01; QA + engine |
| SOURCES-01 P1 | Vendor-by-vendor acceptance — Planned | Each of 12 recognized vendors gets an evidence test: readable official sources on both sides or explicit Needs confirmation; pricing/performance/absence claims rejected without equivalent evidence. Record source date, failure and cancellation. Core-first fit remains evidence driven | Engine + competitive SE |
| UX-02 P1 | First-use customer-task study — Planned | Fresh users can prep, choose mode, correct speaker, inspect methodology evidence, use sources, switch windows and review past calls without coaching. Record confusion and fix top failures; accessibility/keyboard/VoiceOver basics verified | DEV-01; product + UI |
| REVIEW-01 P1 | Recap and opportunity quality — Validation open | Commitments, dates and next steps only when supported; opportunities separate evidence from hypotheses and preserve Core-first stance. Recap edits/export are deliberate; no automatic integrations | Engine + SE reviewers |

Numerical speaker/name accuracy thresholds must be defined with the pilot owner after establishing baseline and scenario coverage. Do not choose an aggregate threshold that hides overlap, accent or device failures. No pipeline choice is approved merely by appearing in this table.

## Milestone C — repeatable development and approved deployment

| ID / priority | Deliverable and state | Acceptance criteria | Dependencies / role |
| --- | --- | --- | --- |
| DEV-02 P0 | Portable runtime packaging — Planned | App carries required engine/runtime resources or installs them through an approved documented path; data in per-user storage, no author clone dependency. Upgrade/uninstall preserve or deliberately handle data. Test fresh Mac and moved clone | Native/platform |
| DEV-03 P1 | Test suite modernization — Planned | Separate hermetic, native, live-provider and disruptive/audio suites; remove original machine paths; explicit isolated state; accurate exit codes. Safe CI runs no audio, secrets or hosted requests | Engine + QA |
| DEV-04 P1 | CI and collaboration controls — Planned | PR template, runnable safe checks, macOS build checks where runner approved, reviewed branch protection and secret scanning. Document code areas and reviewers; contributors own their credentials | DEV-03; maintainer |
| GOV-01 P0 | Classification and provider decision — External decision | Accountable Cisco reviewer confirms permitted transcript/reference classes, CIRCUIT registration/service handling and internal-only pilot scope. Record decision/restrictions in approved internal location; link sanitized decision status | Security/privacy + service owner |
| GOV-02 P0 | Consent/retention/backups — External decision | Approved notice/consent workflow by applicable setting, retention periods/holds/deletion/backup destinations and customer expectations. Engineering implements chosen rules and verifies export/data deletion paths | Legal/privacy + product |
| GOV-03 P0 | Endpoint/security review — External decision | Approved EDR/MDM baseline, Keychain least privilege, TLS boundaries, at-rest protections, threat review and vulnerability remediation evidence. Enrollment alone is not attestation | Security + platform |
| GOV-04 P0 | Dependencies and model provenance — Open | Exact versions/hashes/licenses/transitive inventory for whisper/Ollama/Python/model artifacts, especially speaker weights; OSPO/model approvals captured before distribution. No unverified weights silently bundled | Platform + OSPO/AI governance |
| RELEASE-01 P0 | Managed signing/distribution — Planned + external decision | Approved identity/signing/notarization/internal distribution, supported OS/hardware matrix, installation permission flow, versioning, rollback and documented ownership. Self-signed local build is not enterprise rollout | DEV-02, GOV-01–04; platform |
| RELEASE-02 P1 | Privacy-preserving diagnostics — Planned | Local opt-in diagnostic export strips credentials/call content by default, records relevant timing/version/errors, previews before export; no silent cloud telemetry | GOV-02/03; native + QA |
| RELEASE-03 P1 | Pilot support and feedback — Planned | Named maintainer/pilot owner, defect intake, severity guidance, versioned release notes, measured rollout/rollback criteria and a support route. Claims trace to evidence | Product + maintainer |

## Later work: deliberately outside the next-week scope

- CONNECT-01 P2: reviewable Salesforce/email/calendar handoff only after user-approved scopes and explicit per-action confirmation; draft/preview/cancel/failure cases tested. Existing placeholders are not enabled connector claims.
- KNOWLEDGE-01 P2: approved product knowledge ingestion with source freshness, licensing, local retrieval and explicit selection; never use it as a persistent people library.
- MODE-01 P2: reusable agenda templates after the two modes are demonstrated and understood; avoid more top-level tabs.
- ADMIN-01 P2: team configuration/version management only after classification and deployment ownership are settled; no customer-state syncing by default.

## Definition of done and release evidence

1. Issue links its roadmap ID, owner, scope, dependencies and explicit acceptance scenarios.
2. PR explains behavior, includes necessary checks and preserves relevant negative cases; reviewer can reproduce using fictional fixtures.
3. Evidence records commit, app version/hash where relevant, hardware/OS/model/provider, fixture class, timing methodology, outcome and limits. Preserve failures and retests. No secrets/customer content in repository artifacts.
4. UI changes are reviewed at supported sizes and relevant modes; behavior changes include interrupted/failure/cancellation paths, not only a happy turn.
5. Roadmap status changes only after criteria pass. External approvals record an authorized decision; absence of a decision is not a pass.
6. Release notes list known limitations and rollback. Presentation-ready, pilot-ready and distribution-ready are separate gates.

A presentation can use verified fictional examples while audio certification remains open. A customer-ready claim cannot skip Milestone B P0 gates and applicable governance decisions. Broader distribution additionally requires Milestone C P0 gates.

## Contributor starting points

- Native/UI: DEMO-01, UX-01, onboarding/card/window acceptance.
- Coaching/SE: COACH-01, NOTES-01, competitive question rubric.
- Audio: AUDIO-01 first; do not swap model engines before a comparative baseline.
- QA/reliability: REL-01, DEV-03 and reproduction-oriented bug reports.
- Platform/security: DEV-02, GOV-04 and scoped review intake.

Use [Contributing](../CONTRIBUTING.md), [README](../README.md), [Privacy boundaries](PRIVACY.md) and [presentation runbook](PRESENTATION.md). Create/claim an issue before parallel work, and coordinate shared modules such as `serve.mjs`, `ReviewView.swift` and `core.mjs` to avoid incompatible changes.


## October 2 polish implementation and evidence

- DEMO-01: two mode-specific fictional examples implemented. Flexible conversation asks which demo workflow/success criteria matter; Discovery first redirects today toward discovery and a tailored next step. Both use the same customer request, label their mode and match transcript/Next Move. Example host turns consistently use Rodney White. No invented agreed next steps are included.
- COACH-02 / ANSWER-01: explicit question-search retries retain the original question ID and do not mark it delivered. Resolved questions cannot be retried; ambiguous/seller attribution is excluded. Stop cancels pending search and blocks retry/late publication after finalization.
- UX-01: progress messages are visible rather than tooltip-only; Searching docs, Answer ready, Needs confirmation and Request failed are distinct. Retry appears for failed coaching and unconfirmed answer searches. Missing evidence is not labeled a transport failure. Idle workspaces do not show an active-call audio warning.
- Synthetic verification: 18 selected regression suites passed, plus product-context, question-continuity, duplicate-cleanup and audio-activity checks. New outage/retry/stop replay passed. Native checks expanded to 13/13 for both examples and existing state/context/consent behavior.
- Still open: full presentation rehearsal, natural audio attribution/overlap acceptance, full-hour repaired recap finalization, production latency and every-vendor live acceptance. These changes do not close those gates.

Installed UI acceptance: both modes visually reviewed; mode switch updates the fictional transcript and Next Move; Coach opens Research → Competition; Exit example restores the actual 0-turn workspace. Idle warning is absent. Installed binary SHA-256: `97c6b8cffc52813d72088e268d104e01e2cdb278db4382364a1ea0122ed50c5e`. No actual call was captured for these checks.

Final retry routing carries the failed question ID in progress state; coach retries cannot select an older unresolved product question. Targeted retry/stop replay passed after this refinement.


## October 2 text readability audit (UX-01)

Implemented full wrapping in call-mode descriptions/examples, onboarding mode cards, coaching questions/answers/reasons, competition transcript quotes, speaker names/roles and saved-call titles/subtitles. Removed silent line limits and tail truncation. Call-mode settings and consent content scroll with footer actions outside the scroll region. Compact Next Move, answers, sources and errors scroll rather than ending at a line limit; workspace/transcript actions remain visible, with a separate bounded transcript scroll.

Verification: signed build and 13/13 isolated native checks passed. Installed mode settings and initial onboarding visually reviewed with both complete descriptions and examples. Rendered workspace Coach, Notes, Competition, call preparation, consent and 380-point compact window reviewed. No audio was captured or audio devices changed. Existing editors and full-content workspace sections already scroll. This closes the identified truncation defects; contributor acceptance still includes unusually long real content and narrower split panes as part of UX-01, rather than claiming every possible layout is certified.


## October 2 layered answers and whole-call SPIN (ANSWER-01 / COACH-01 / UX-01 / REL-01)

- Competitive answers use separate vendor paragraphs in generation and native rendering, including older saved comparisons. Incomplete competitive sentences fail validation rather than being presented as verified.
- Retrieve sources immediately, keep them in call-scoped evidence memory, then wait for 1.2 seconds of settled committed context and no active/pending speech before generating/publishing. Added comparison scope refines the same unresolved question ID, aborts stale work and reuses retrieved evidence. A later relevant clarification revises the answer; resolved questions are not silently reopened. Superseded answer cards are hidden during refinement and replaced in history. This is not an indefinite wait or a guarantee that future speech can be predicted. Existing public-source caches remain bounded and short-lived; no persistent people library or cloud knowledge upload was added.
- Next Move is now Next Question. The cue is an actual criteria/technical follow-up, not “a sourced answer is ready.” Search/readiness remains on answer cards in Research. Older saved status cues receive a display-only follow-up; original archived data remains intact.
- SPIN evidence retains every qualifying customer statement from throughout the call, with turn references and role uncertainty. Coverage popovers scroll through the evidence trail. Coaching/answer prompts include this whole-call SPIN record alongside recent speech, earlier relevant notes and corrections. Evidence presence alone remains partial and does not invent completion.
- Verification: 24 safe suites passed before the final formatting/history refinements; targeted layered-answer, competition, retry/stop and both-mode/local-only flow checks passed after relevant refinements. 282-turn synthetic context fixture retains early/middle/late evidence; actual 141-second fictional audio was synthesized to a file, transcribed locally with small.en, and checked for ingestion, delay, implication and need-payoff context. Native 13/13 checks and Coach/Competition visual renders passed. Reproduce audio with `bash scripts/test-holistic-audio.sh <candidate binary>` (macOS speech synthesis, ffmpeg and a local Whisper model required); no audio device is opened.
- Still open: hour-long natural multivoice/overlap/noise acceptance and production-model latency/load certification. A multi-minute synthetic file and long transcript fixture do not certify those gates.

Installed acceptance: signed final candidate passed 13/13 native checks. Fictional example visibly separates Splunk/Sumo paragraphs and shows an actual Next Question; exiting restores the normal workspace. File-only audio test reproduced successfully (141 seconds, 431 timed tokens, 31 parsed statements). Continued speech is excluded from provider timeout accounting; stop still aborts held work. No audio-device change was made.


## October 2 source research and unified Answers

User reports questioning speed is substantially better; record this as qualitative feedback, not a measured latency result. The next endurance gate is REL-03. Expert-discovery synthesis is COACH-03, including the restricted-access boundary for Bryan Ting.

Current behavior: technical and competitive answers share Research → Answers, with an All/Technical/Competitive menu and category labels. Coach links select the relevant category. Customer questions retain answered/deferred controls; neutral evaluation questions and Klue resources remain under Competitive context. Opportunities is the other Research destination. Legacy competition preview links map to the Competitive filter.

Routing: “Can Splunk ingest Datadog logs?” is a technical Splunk functionality question; “Does Datadog support log collection?” is a technical named-vendor question using that vendor’s documentation; “What is the difference between Splunk and Datadog?” is a competitive comparison. Current functionality and integration questions are not automatically competitive merely because a rival was mentioned. Explicit comparisons and contextual scope refinements remain competitive.

Source findings and precedence:

- [CI Slack guidance](https://splunk.slack.com/archives/CAVVBB6P2/p1778713672569609) points sellers to Klue for CI assets, with CI assistance for account-specific gaps. [Migration guidance](https://splunk.slack.com/archives/CAVVBB6P2/p1772629130681499) confirms compete content moved to Klue.
- [Datadog Compete Card](https://v2.app.klue.com/profile/88269/battlecard/view?cardId=4621177) was read in the authorized corporate browser. Visible review date: October 1, 2026, Alex Salesi. It contains differentiation questions, objections and mixed Core/Observability/ITSI positioning. Select the applicable section; a current card header does not make every individual claim current or customer-approved. The separate Cloud SIEM and partner cards underscore audience/scope distinctions. No battlecard body is copied into the repository.
- Webex search found Klue recommendations in “All things O11y!” (July 15, 2026) and “Splunk Americas SE All” (April 16, 2026). One shared summary explicitly says it was created with CIRCUIT; that is useful discovery context but is not itself vetted CI evidence. Do not automatically ingest every Slack/Webex message into live answers.
- [Historical CI guidance on external distribution](https://splunk.slack.com/archives/CAVVBB6P2/p1677680183717289) distinguishes internal battlecards from externally released materials. It is historical evidence, not a claim of current policy approval; confirm current audience rules with the CI owner.
- [Klue’s official Content API guide](https://klue.com/blog/how-to-connect-klue-to-chatgpt) describes published-card retrieval and card citations, with admin-created API access. The browser session can read a card, but that is not a configured API credential for SalesPilot. No new key or permissions were created.

Important implementation limit: generated comparisons still use readable documentation/local evidence. Klue links now include the verified Datadog card, but automatic retrieval of pre-vetted CI wording is **not connected**. CI-01 is the explicit deliverable for that connection; do not describe generic documentation output as CI-approved. Slack/Webex locate canonical cards, owner clarifications and updates; published Klue content is the preferred positioning source; current technical documentation supports capability assertions. Nothing was posted to Slack or Webex, and no restricted Gong call was accessed.

Installed acceptance for unified Answers: 24 selected safe suites passed, with targeted competition/product-context/layered-answer checks repeated after routing refinements. Final signed build passed 13/13 native checks. In the installed fictional example, the Coach shortcut selects Answers → Competitive, the long comparison question wraps completely, and Technical displays one pricing answer without the duplicate card. Exiting the example restores Ready with 0 turns. No recording or audio-device change was made. CI-01 and the real-time 120–180-minute REL-03 gate remain open.

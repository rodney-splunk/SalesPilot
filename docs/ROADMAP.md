# SalesPilot product and engineering roadmap

Updated October 2, 2026. Canonical roadmap for contributors. This is a prioritized plan, not a claim that every feature or customer-call scenario is certified. The presentation is next week (October 5–9); the exact day and audience requirements are not yet specified. Dates below are planning checkpoints, not promised completion dates.

## Product objective and boundaries

Help an SE listen, ask a natural next question, retain customer context and verify answers during discovery. Keep the live screen calm: Coach, Notes and Research, with Answers/Competition/Opportunities nested in Research. Start positioning from Splunk Core; premium applications require evidence of customer need.

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
| Mode chooser and onboarding | Implemented | Installed UI verified; selection persists, selector under More, six-step guide; distinct mode demos remain planned |
| Local transcription and speaker continuity | Implemented / validation open | Synthetic timed-ASR/voice checks; natural accents, devices and overlap remain open; true overlapping speech is not separated |
| Natural cues and methodology evidence | Implemented / validation open | Synthetic continuity/coverage checks and user feedback; production latency and unseen-call quality need measurement |
| Notes and question ledger | Implemented / validation open | Fragment/correction/context regressions; generated answers remain open until delivered or deferred; broader natural-call review pending |
| Sources and competitive research | Implemented / validation open | Actual Cisco comparison with official Splunk/Sumo sources passed; 12-vendor detection catalog is not 12-vendor live acceptance |
| Consent, local-only mode and Keychain | Implemented / policy review open | Negative-egress and consent checks pass; classification, retention and organizational approvals remain external |
| Private collaboration repository | Available | Source-only build passed, 18 selected engine suites and 11 native offline checks passed; coworker access/setup pending username |
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
| COACH-02 P0 | Cue display and cancellation — Validation open | Transcript and Next Move agree; new context/stop invalidates stale work; mode/detail changes preserve valid cues; interruptions do not publish obsolete suggestions. Replay corrections and rapid turn boundaries | Engine + native UI |
| PERF-01 P0 | Measured live timing — Planned | Record silence-to-final transcript, finalized-turn-to-visible cue, question-to-source-backed answer and notes freshness. Publish p50/p95/failure rates for cold/warm local and Cisco paths on reference hardware. Provisional targets: cue p95 <4s, answer p95 <10s; explicitly flag misses, do not call targets measured | Audio + engine + QA |
| ANSWER-01 P0 | Question lifecycle and context — Validation open | Direct/indirect/pronoun questions remain anchored to product context across topic changes. Ordinary “on this call” never routes to Splunk On-Call; Cloud/Enterprise ingestion comparison stays anchored. Delivered/deferred/reopened state persists; generation alone never resolves a question | Engine + QA |
| NOTES-01 P0 | Complete facts with provenance — Validation open | Preserve early-call context, product names, units and speaker; join supported fragments, retain exact correction history and transcript links. Incomplete thoughts remain incomplete; no invented completion or assumptions promoted to confirmed facts | Engine + SE reviewers |
| REL-01 P0 | Full-hour finalization — Retest pending | Repaired 60-minute fixture preserves all expected turns, notes, questions, coverage and sources; end completes recap and history within a documented bound. Repeat start/stop; isolated test does not create synthetic calls in actual history | Engine + QA |
| REL-02 P0 | Crash/recovery and outage matrix — Validation open | Native/engine/ASR crash, sleep/wake, permission loss, provider timeout, docs outage and interrupted stop have visible states and recoverable local journal; no silent loss or false Ready. Recovery sections clearly require review | Native + engine + QA |
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

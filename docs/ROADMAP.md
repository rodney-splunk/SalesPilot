# SalesPilot core platform optimization roadmap

Updated October 4, 2026. Active scope: improve the speed, quality, reliability and maintainability of the existing platform across its entire lifecycle. **No new product features, tabs, integrations, providers, persistent people library or background publishing.** The source analysis is [Architecture review](ARCHITECTURE-REVIEW.md). Previous milestone plans and acceptance records are preserved in [Roadmap history](ROADMAP-HISTORY.md); their priorities are historical, not the active queue.

## Product and compatibility contract

Preserve natural discovery and technical, business and personal value selling; whole-call context; SPIN/MEDDPICC/Challenger evidence; call-scoped identity; both existing call modes; notes, unanswered questions, technical/competitive Answers, opportunities, prep, reference imports, recap/history and compact/workspace state. Splunk Core remains the initial positioning basis; premium fit needs customer evidence. Keep generated answers distinct from delivered answers and documentation comparisons distinct from vetted CI talk tracks.

Maintain supported inherited OpenWispr dictation, hotkeys, punctuation, clipboard, recording retention and configuration compatibility until an explicit removal decision. Isolate these from live calls where dependencies are unnecessary. Preserve license notices and approved local/Cisco boundaries. No speed optimization silently drops audio/evidence, guesses identity, removes safeguards or sends data to a new destination.

## Priority and status rules

- **P1:** correctness, data preservation and measurement gates. Do these before broad customer-pilot readiness claims; urgent incidents take precedence within P1.
- **P2:** targeted speed/resource improvements after a baseline and P1 dependencies. No feature expansion.
- **P3:** maintainability, compatibility and operational hardening after critical paths stabilize.
- **P4:** measured residual tuning and long-term stewardship of existing behavior, only after higher-priority acceptance.

All CORE items below are **planned and unassigned**, including audit and verification work unless a specific evidence record says otherwise. Source findings do not mean a fix is implemented. Claim an issue with its ID, owner, dependency, source revision and acceptance evidence. “Verified” always names the exact fixture/runtime scope. An external decision stays open until its accountable owner records it. Existing P0 IDs remain searchable in the historical mapping below; active core blockers are P1.

## Lifecycle coverage

| Stage | Existing behavior to preserve | Primary work |
| --- | --- | --- |
| Install and upgrade | Own credentials/models, valid paths, compatible settings and previous records | CORE-12/14/15/23 |
| Launch and idle | Readiness, permissions, model availability, bounded idle resources | CORE-01/06/12/20 |
| Prep and start | Scoped context, mode/framework, consent, clean session state | CORE-09/12/16/19 |
| Capture and final ASR | Mic/system samples, no loss, complete utterances, honest degraded mode | CORE-05/06/10/16 |
| Attribution and context | Corrections, unknown/overlap safety, complete early/middle/late evidence | CORE-03/08/16/18 |
| Coaching and answers | Natural current question, sourced answers, cancel/retry and no stale publication | CORE-01/03/07/08/19 |
| Visible workspace | Coherent notes/evidence and responsive compact/full windows | CORE-02/04/19 |
| Pause, interruption and recovery | Device/network loss, sleep/wake, crash, privacy mode boundaries | CORE-09/10/16/20 |
| Stop and finalize | Last turns durably saved, explicit recap/archive outcome, bounded children | CORE-09/10/18 |
| Review and retention | Accurate saved calls, explicit exports, compatible deletion/holds | CORE-11/15/21 |
| Maintenance and uninstall | Reproducible release, rollback, artifact/license ownership, residual cleanup | CORE-13/14/15/17/22/23/24 |

## P1 correctness and acceptance gates

| ID | Work and source finding | Acceptance and negative cases | Dependencies |
| --- | --- | --- | --- |
| CORE-01 | Establish true end-to-end latency/resource baseline; current timers stop before UI and keep last64 samples | Correlate speech end → finalized transcript → attribution → queue/model → durable snapshot → visible validated cue/answer. Report cold/warm and local/Cisco separately, p50/p95/sample counts/timeouts/cancels/quality rejection, CPU/RSS/backlog/event-loop delay, model and token counts. Distinguish deliberate speech hold from processing and include both in user-observed latency. Proposed targets cue p95<4s and answer processing p95<10s are not measured guarantees | Existing PERF-01; QA + native/engine |
| CORE-09 | Unify call stop/finalize deadline and ownership | Rapid start-stop-start, stop during final ASR/attribution/retrieval/recap, empty call, crashed engine and slow model: every accepted turn survives; no prior-call result overwrites next call; archive written once by call ID; explicit failed recap retains transcript. Finalize within one documented budget with acknowledgement, no orphan Node/Python/Whisper or lingering timers; reproduce 25s native vs longer engine mismatch | CORE-01; REL-01/02 |
| CORE-10 | Durable ordered capture without main-thread storage stalls | Isolated storage slowdown/full disk/unwritable path/crash at each boundary; journal errors visible; accepted turns replay exactly once; ordered IDs and deletion/correction events survive; stop waits for durable barrier. Measure UI stall and writer backlog before selecting batch policy. Document maximum loss window; no casual fsync removal | CORE-01/09; GOV-02 |
| CORE-16 | Audio and identity lifecycle acceptance | 2 and 3–4 speakers, headset/speakerphone, accent/unseen/split names, AEC failure, long monologue, low volume, overlap, input/output changes, denied/revoked permission, macOS13 vs14.4+, sleep/wake. No lost initial/final speech or phantom confirmed people; ambiguous audio remains reviewable; warning clears on evidence. Compare only approved local pipelines on same ground truth | AUDIO-01/02/03; authorized audio fixtures |
| CORE-18 | Full-duration integrity and release evidence | Repaired 60-minute then 120–180-minute wall-clock isolated replay validates exact turn IDs/counts, early/middle/late and corrections, coverage/notes/question/source provenance, recap/history and child cleanup. Sample latency/backlog/resource use by call segment. Mock transport does not certify native ASR or production provider; repeat with authorized natural audio and approved provider separately | CORE-01/09/10/16/17; REL-01/03 |
| CORE-19 | Cross-feature state and context invariants | Both modes/frameworks: prep is unconfirmed context, not coverage; seller/mixed speech cannot confirm customer evidence; correct labels propagate; unresolved questions survive topic changes; generated is not answered; Cloud/Enterprise stays distinct from On-Call; functionality vs comparison correct; stop/framework/name correction invalidates stale work. Compact/workspace/transcript/history show same call and question | COACH-01/02, ANSWER-01, NOTES-01, REVIEW-01 |
| CORE-21 | Close existing data/security lifecycle gaps | Inventory raw temp WAVs, recordings, journal, caches, prep, index, logs and archives across success/cancel/crash/update/uninstall. Apply approved retention/permissions/holds and transport/Keychain boundaries, verify local-only negative egress and explicit export actions. Do not claim formal approval, complete DLP or universal deletion policy before accountable decisions | GOV-01–04; privacy/platform |

## P2 performance improvements driven by measurements

| ID | Optimization candidate | Acceptance and safety guard | Dependencies |
| --- | --- | --- | --- |
| CORE-02 | Incremental derived session state and coalesced snapshot persistence | Profile 100/300/1000-turn calls; reduce repeat notes/evidence/signals/JSON work and write frequency. Proposed gate ≥20% improvement in measured snapshot/event-loop p95, no >10% cue regression; preserves raw durable capture and correction/relabel/framework invalidation. Last state always flushed at stop; no false Ready on failure | CORE-01/10/19 |
| CORE-03 | Indexed call memory and bounded inference representation | Retain complete transcript/evidence outside prompt; use ID-indexed facts, correction chains, unresolved questions and relevant evidence selection. Compare token growth/context-build p95 and blind cue/recap quality at 100/300/1000 turns. Every early/middle/late tested fact and correction stays retrievable; no quality loss or blanket tail truncation | CORE-01/19 |
| CORE-04 | Shared native snapshots and latest-only UI reloads | Measure compact metadata + workspace decode duplication; bounded latest-version scheduling, stable turn IDs and lazy rendering where useful. Proposed decode/render p95≥20% improvement at 1000 turns; no older revision applied after newer, lost focus, source/evidence selection or scroll jump. Minimum/default size, light/dark, keyboard/VoiceOver preserved | CORE-01/02/19 |
| CORE-05 | ASR buffer/allocation and finalization efficiency | Measure audio real-time factor, sample copies, WAV writes and accumulated backlog on dual sources and >25s monologues. Bounded ring/chunk scheduling only after ground truth; no missing boundaries, extra words or final-pass quality degradation. Tick cadence/silence changes evaluated separately; stalled inference never causes unlimited retained audio | CORE-01/16 |
| CORE-06 | Model residency and local resource budgets | Benchmark cold/warm startup, dual-source shared server, 4/6-thread configurations and live/final/sidecar/Ollama contention. Keep installed-model warmup bounded and optional; no unsolicited downloads. Resident lifetime/idle release respects memory/energy and approved policy; final ASR and live cue priority validated | CORE-01/05/16 |
| CORE-07 | Cancelable, deduplicated source retrieval | Parent signal cancels fetch/embedding/MCP process; canonical public source reuse with permission/scope/freshness key and bounded cache; evaluate persistent MCP only if measurable. Test rapid refinements, outage, stale/removed sources, oversized pages, partial MCP output and stop. No stale citations or query/customer-data exposure introduced | CORE-01/19/21 |
| CORE-08 | Priority budget for live and ancillary inference | Track in-flight counts/queue wait; defer/coalesce recap/identity/cleanup/index work when live work arrives. Cancel or discard prior-call work through generation IDs. No starvation of finalization, no local GPU/CPU thrash from nominally separate lanes; measure success rate and end-to-end p95, not only model response | CORE-01/09/19 |
| CORE-11 | Bounded history and recovery work | Replace full-archive signature scans with compatible call-ID metadata where measured; load existing history without eager whole-body decode. Accept 100/1000 archives, duplicate finalization, malformed archive, missing journal, truncated tail and mixed old/new schema; no deletion or lost correction provenance | CORE-09/10/15 |
| CORE-12 | Faster startup and clean separation from inherited dictation permissions | Trace each startup permission/model/download gate; ensure live call has only necessary approved dependencies. Test fresh install/upgrade, declined Accessibility, dictation opt-in, correct bundle identity and active call. No blocking sleep loop on main and no automatic unnecessary TCC reset; existing dictation remains functional | CORE-01/16/21 |

Performance percentages are proposed experiment gates. Establish baseline variance first; if a stage is already negligible, record evidence and deprioritize instead of implementing complexity for its own sake. Quality and durability acceptance outweigh percentage gains.

## P3 maintainability and operational hardening

| ID | Work | Acceptance | Dependencies |
| --- | --- | --- | --- |
| CORE-13 | Modularize orchestration and reconcile fork leftovers | Small PRs extract state/scheduler/persistence/provider boundaries from serve/LiveHUD/StatusBarController; inventory active dictation vs live entry points. Remove only proven-unused StreamingTranscriber scaffold/disabled provider leftovers after tests; preserve API/settings/license compatibility. No wholesale rewrite | CORE-17/19; review finding ownership |
| CORE-14 | Portable runtime and approved model/dependency provenance | Resolve engine/runtime/converter resources without Rodney's clone or icon venv; fresh Mac/moved clone build and run existing workflows. Pin approved artifact version/hash/license, verify download cancel/failure/integrity and bounded wait. Supported macOS/hardware matrix explicitly reflects process-tap limits; no new runtime/provider | CORE-12/21; DEV-02, GOV-04 |
| CORE-15 | Versioned schema and compatibility contract | Validate prep/config/session/journal/index archives; migrate atomically with backups and rollback, preserve unknown supported fields and identifiers. Test legacy config/hotkeys/devices/archives, corrupt/partial settings, newer schema read, model/index mismatch and uninstall/restore. No silent default reset or raw-data loss | CORE-09/10/11/21 |
| CORE-17 | Test/benchmark tiers and reproducible release checks | Map each lifecycle invariant to hermetic engine, isolated native, file-only ASR, authorized provider and disruptive device suite. Unique temp state, no author paths, timeout/cleanup and correct exits. Required safe checks on PR; approved macOS build runner and preserved failed evidence. No customer data or secrets in CI; no device changes from default suite | DEV-03/04; CORE-19 |
| CORE-20 | Bounded recovery and idle resource cleanup | Process ownership, port bind races, launch failure, stdin/stdout backpressure/partial frames, sleep/wake, quit and canceled warmup verified. End repeated 20-call/start-stop cycle with no orphan children/temp snapshots/timers; bounded idle CPU and no monotonic leak. Recoverable degraded states remain visible | CORE-06/09/10/16 |
| CORE-22 | Maintainer/support and change discipline | Owners for native/audio/engine/security, defect severity and reproduction, protected review workflow when approved, sanitized local diagnostic evidence, release notes/rollback and frozen candidate before important calls. Source/model/version is reproducible; no automatic cloud telemetry or new diagnostic UX in this scope | CORE-01/17/21; RELEASE-02/03 |

## P4 residual tuning and existing platform stewardship

| ID | Work | Acceptance | Dependencies |
| --- | --- | --- | --- |
| CORE-23 | Upgrade and uninstall regression matrix | Approved signing/distribution/rollback tests on supported environments; document handling of existing data, retained recordings, permissions and model/runtime resources. Verify reinstall, downgrade and canceled upgrade; never destroy user records implicitly. Formal deployment decision is external | CORE-14/15/20/21; RELEASE-01 |
| CORE-24 | Evidence-led residual efficiency and fork maintenance | Re-profile after P2/P3; optimize only remaining measured CPU/memory/energy/latency bottlenecks. Review pinned upstream changes/licenses for security/correctness and keep compatible fixes; one small experiment per PR, same quality gates. No framework rewrite, vector database or model swap without demonstrated need | CORE-01–23; OSPO/model owner |

## Explicit compliance, usability and maintenance acceptance

Added October 4, 2026. These items refine existing platform work; they do not authorize new integrations, egress or automatic publishing. All are **planned, unassigned and not implemented**, unless separate evidence records prove a specific subtask. Claim each ID with an owner and revision before work begins.

| ID / Priority | Work | Acceptance and edge cases | Existing dependencies |
| --- | --- | --- | --- |
| CORE-25 / P1 | Make the existing pre-capture processing summary understandable | Explain local audio transcription, selected masked text sent to approved Cisco inference, and documentation query destinations accurately for the selected processing choice. Identify separately triggered prep lookups. Test local-only, unconfigured Cisco, unavailable connector and mode changes; summary must match actual transport behavior and remain readable in the consent window. Keep required per-call consent; do not imply policy approval or promise complete PII removal | CORE-19/21; privacy review |
| CORE-26 / P1 | Tie internal/compliance review evidence to each release | Review packet names source revision, app/build identifier, signing identity, model/dependency versions, tested controls, evidence scope, failed/pending checks and required external decisions with accountable owner when assigned. Distinguish engineering verification from formal Cisco approval. Flag superseded packets; current documents must not claim coverage from an older candidate without verified applicability | CORE-14/17/21/22/23 |
| CORE-27 / P1 | Repeated-call authorization and clean-session acceptance | Run 20 authorized start/stop cycles with both existing modes and processing choices, verifying app-session credential reuse, per-call consent, clean prep/context boundaries, speaker labels, finalization and bounded child cleanup. Include denial/retry, explicit credential refresh, quit/relaunch, stop during startup and upgrade with stable signing. No helper Keychain read per call after successful app-session authorization; no previous-call content or stale results leak. Record actual macOS prompt behavior separately from synthetic cache tests | CORE-09/12/16/19/20/21 |
| CORE-28 / P2 | Explain settings, call modes and Cisco positioning precisely | Audit every existing toggle/menu setting: description states actual effect, current/next-call timing and persistence. Rename “Cisco counterpart mode” to “Show Cisco positioning”; explain added opportunity context and clipboard handoff. Verify off/on, empty opportunities, absent Cisco evidence, persisted setting, and copy action. It must not imply changes to models, coaching, answers or external sending. Current toggle affects Opportunities presentation only; engine-adaptive Cisco coaching remains a separately scoped, parked proposal | CORE-04/19; current OpportunitiesView behavior |
| CORE-29 / P2 | Complete readability and accessibility audit | Check existing consent/onboarding/mode descriptions, prep, Coach, Notes, Research/Answers, opportunities, source/evidence details, history and compact/full windows. Long content has wrapping, scrolling or explicit expansion; no inaccessible truncation. Cover minimum/default widths, longer names, Unicode, keyboard navigation, VoiceOver, light/dark appearance and supported larger text/display settings. Preserve selection, focus and scroll position across live updates | CORE-04/19 |
| CORE-30 / P2 | Track visible question, note and answer response budgets throughout calls | Extend CORE-01 measurements to first useful note and subsequent note corrections, questions, technical and competitive answers. Correlate speech completion, intentional hold, source lookup/model processing and visible UI state; compare cold/warm, early/middle/late long-call segments, refinements, cancellation and outages. Publish p50/p95, samples/failures/backlog and quality results before claiming improvement. Optimize the measured bottleneck; preserve whole-call context, citation quality and value-selling depth | CORE-01/02/03/04/07/08/18 |
| CORE-31 / P3 | Keep build artifacts and documents clearly current | Document one current installed app, active repository/runtime and one recent rollback. Candidate/output paths avoid duplicate launchable apps in normal user folders. Provide an explicit, recoverable cleanup process for obsolete artifacts; never delete call records, unique source work, model resources, evidence or legal-held data as housekeeping. Clearly name current overview/script/review documents; presentation scripts remain local and outside GitHub. Test canceled/failed updates and rollback; retain historical evidence in its designated location | CORE-14/21/22/23 |

Recommended next sequence: CORE-28 settings clarity, CORE-27 repeated-call acceptance, and CORE-01/30 long-call measurements, while CORE-25/26 review work proceeds with the appropriate owners. Existing P1 correctness gates still precede customer-pilot readiness claims. No new “Cisco seller coaching mode” is active work under this optimization scope.

## Execution sequence

1. Claim CORE-01, CORE-09 and CORE-17 first; capture timing, reproduce finalization mismatch and make test tiers explicit. Start CORE-16/19/21 validation in parallel where authorized fixtures/owners exist.
2. Optimize CORE-02/04 together through a documented snapshot contract; CORE-03 preserves whole-call evidence; CORE-07/08 prioritize live work. Profile before touching ASR timers or changing models.
3. Close repaired one-hour and 120–180-minute acceptance after relevant fixes. Natural audio and production-provider checks remain separate from mocked endurance.
4. Only then proceed with modularization, portable packaging, schema and recovery/upgrade hardening. Do not mark customer-pilot ready merely because the demo works.

No hours/delivery dates or owners are invented. Each item needs an estimate and named owner when claimed. Calls currently in use are never restarted or have devices changed without session authorization.

## Mapping from earlier roadmap IDs

| Earlier IDs | Active core coverage |
| --- | --- |
| PERF-01 | CORE-01/02/03/04/05/06/07/08 |
| AUDIO-01/02/03 | CORE-05/06/16/18 |
| COACH-01/02, ANSWER-01, NOTES-01, REVIEW-01 | CORE-03/08/19 |
| REL-01/02/03 | CORE-09/10/18/20 |
| UX-01/02 | CORE-04/12/19; fixes to existing flows only |
| SOURCES-01 | CORE-07/19, acceptance of existing recognized sources |
| DEV-01/02/03/04 | CORE-14/15/17/22 |
| GOV-01/02/03/04, RELEASE-01/02/03 | CORE-14/21/22/23 |

Expert-call learning (COACH-03), direct Klue API integration (CI-01), new knowledge sources, CRM/email/calendar connections, agenda templates and team administration remain recorded in history but **parked during core optimization**. Existing CI links and documentation answers continue; no pre-vetted Klue generation claim. Presentation scripts remain local, outside the repository.

## Evidence and definition of done

For each optimization: record source/candidate commit, build/model hashes, hardware/OS, dataset authorization/class, elapsed-time method, samples/all outcomes, quality/identity/citation results, CPU/RSS/energy/backlog, test command and rollback. Use fictional/sanitized records only. Preserve failed runs and retests. Compare baseline/candidate on identical fixtures, preferably interleaved repeated runs rather than different days or machines.

Release gates: no lost accepted audio/turn/evidence, no cross-call output leak, no new egress, no guessed identities, no automatic customer action, complete finalization or visible durable failure, supported old records/settings readable, and measured latency/resource behavior within the agreed hardware-specific budget. Formal classification/consent/endpoint/model/deployment decisions remain external. Existing quality checks include value-selling relevance, natural language and all three impact layers without invented pain.

### October 4 review evidence

- Static inventory and cross-layer review of source revision `04fc766`; hot paths inspected in depth. Findings and unresolved assumptions are recorded in ARCHITECTURE-REVIEW.md.
- No application implementation changes, install/restart, audio capture/device change, production-provider call or natural-call acceptance performed by this review.
- Fresh `bash scripts/test-safe.sh` completed with exit 0: all 24 selected suites passed using synthetic/isolated transports. This validates the selected regression scenarios, not production latency or real audio. Prior native/audio results remain in ROADMAP-HISTORY.md with their original limits; the full-hour recap retest and 120–180-minute acceptance are still open.

### October 4 credential lifecycle fix

CORE-21/CORE-12: native app now caches authorized credentials for its running lifetime, shares them with call/readiness engines only through private stdin, supports explicit refresh, and skips automatic Keychain reads for local-only/unconfigured calls. Bootstrap messages are consumed before transcript handling. Packaging refuses to overwrite a certificate-signed app with an ad-hoc update when the signing identity is unavailable.

Validation: all 25 safe engine suites pass, including private bootstrap input guards; native cache tests cover repeated/concurrent access, refresh and retry after failure. Candidate release build passed. Outside the restricted build sandbox, the existing signing identity was available; candidate and installed app have identical designated requirements. Real macOS repeated-call authorization acceptance remains pending installation and call availability confirmation. Per-call consent remains intentional. No installed-app restart or credential ACL changes were made.

Installed candidate after the user confirmed no active call: signing verified, runtime engine synchronized, app restarted and visible in Ready state. Isolated native workspace checks passed 13/13. A rollback app is retained locally. Repeated live-call Keychain prompt behavior still requires user acceptance on actual call starts; no audio capture or consent attestation was initiated by this installation check.

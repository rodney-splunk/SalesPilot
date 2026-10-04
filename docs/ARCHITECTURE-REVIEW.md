# Core platform architecture review

Reviewed October 4, 2026 against source revision `04fc766`. Scope: repository inventory and cross-layer static review, with deeper inspection of live capture, ASR, attribution, scheduling, retrieval, persistence, UI updates and finalization. This is not a line-by-line proof of every function, an upstream diff against a pinned original release, or production profiling. Performance opportunities below are code-supported hypotheses until measured. No runtime code, model, audio device, permissions or running app is changed by this review.

## System and lifecycle

The tracked repository contains 203 files at the reviewed revision. Native Swift sources implement application startup, inherited dictation, call capture, resident Whisper processes, JSON/process transport and SwiftUI. Node modules implement the persistent call engine, context/evidence, provider transport, retrieval and archives. A Python sidecar performs local speaker embeddings and clustering. Shell/native replay tooling covers selected parts of those paths; GitHub contains templates but no workflow directory at this revision.

```mermaid
flowchart LR
    A[Startup and readiness] --> B[Call prep and consent]
    B --> C[Mic and system audio]
    C --> D[Live ASR then final ASR]
    D --> E[Capture journal and engine ingestion]
    E --> F[Async speaker attribution]
    E --> G[Context and routing]
    F --> G
    G --> H[Coaching or document retrieval]
    H --> I[Validated session snapshot]
    I --> J[Compact and workspace views]
    J --> K[Stop and final transcript drain]
    K --> L[Recap and archive]
    L --> M[History and review]
    M --> B
```

A separate inherited path runs hotkey dictation → recording → transcription → optional punctuation → clipboard insertion → dictation log. It shares startup/configuration/models with live calls but has its own lifecycle and storage. Sleep/wake handling inspected in AppDelegate acts on that dictation recorder; live-call behavior needs separate acceptance. Upgrade, uninstall and crash recovery cross both paths.

## Existing strengths to preserve

- `WhisperServerPool.swift`: resident process per model, loopback binding, prewarming and CLI fallback. Do not add another model server merely to make warm calls faster.
- `StreamingMicTranscriber.swift`: silence gating, 8-second live window, final accurate pass, 25-second utterance flush rather than silently discarding the beginning.
- `serve.mjs`: fast turn ingestion, latest-cue coalescing, cancellation and epoch checks; separate answer lane; asynchronous voice work; complete literal SPIN evidence.
- `core.mjs`, `circuit.mjs`: bounded transport, token-request sharing, Keychain-backed credentials, restricted enabled providers, fallback/circuit-breaker behavior and local-only checks.
- `answer-context.mjs`, answer validators: preserve added scope, wait for speech to settle, show confirmation when evidence is missing. Faster output must not bypass this.
- `CaptureJournal.swift`: capture retained independently of model success. Current-call identities and manual correction remain separate from cross-call enrollment.

## Findings and engineering implications

| Finding | Source evidence | Consequence and proposed optimization | Roadmap |
| --- | --- | --- | --- |
| Timing ends before native display | `engine/performance.mjs:1`, `performance-report.mjs:1`; `serve.mjs:1217` records cue before snapshot/write; `LiveCoach.swift:140`, `ReviewView.swift:440` apply later | Last 64 per-stage samples do not establish full-call or visible latency. Add correlated monotonic spans, success/failure/cancel denominators and native application timing before choosing a model or timer change | CORE-01 |
| Full session work repeats | `serve.mjs:859–940` reconciles questions, maps turns, derives signals/notes/evidence and synchronously pretty-prints/renames; called several times per turn and on stream updates | Cost grows with call length and competes with ingestion on the Node event loop. Cache derived evidence with correction invalidation; coalesce snapshot writes while preserving durable raw events | CORE-02 |
| Context recomputation and prompt growth | `serve.mjs:439,536`; `call-memory.mjs` rescans notes, ranks earlier statements and includes all SPIN evidence; note extraction uses earlier prefixes and pairwise correction matching | Some work is potentially quadratic; whole-call evidence is unbounded in the prompt. Bound the inference representation using indexed evidence, with complete source record retained and reachable. Never use a recent-tail truncation as the fix | CORE-03 |
| UI decodes the same snapshot in two places | `LiveCoach.swift:25` parses for compact metadata; `ReviewView.swift:443` queues another full decode for workspace; transcript uses `ForEach(displayedTurns.indices)` | Repeated decode/render work and an uncoalesced reload queue can lag on long calls. Measure then share immutable versioned snapshots, latest-only decode scheduling and stable turn IDs | CORE-04 |
| ASR finalization shares a serial work queue with ticks | `StreamingMicTranscriber.swift:191–264`: full buffer copied, WAV written each live pass; final pass blocks that source work queue | Final transcript latency can dominate the visible cue; ingest can accumulate beyond the nominal 25-second cap while inference is slow. Measure real-time factor, high-water marks and retained audio before changing cadence or allocation strategy | CORE-05 |
| Several callers share one server per model | `LiveHUD.swift:187–216`, `WhisperServerPool.swift:38` keys by model path, prewarms with six threads, both sources use live/final models | Mic/system concurrency, live and final passes, warm fallback and Python can compete for CPU/memory. Scheduling behavior of installed Whisper version is not assumed. Benchmark contention and thread budget; preserve final-pass priority | CORE-06 |
| Outer lookup cancellation does not cancel all underlying work | `serve.mjs:977` wraps parallel retrieval in `abortable`; `splunkdocs.mjs:8` launches one process/handshake per call; retrieval functions have independent timeouts without the parent signal | Superseded answer can leave work running to its own deadline. Propagate cancellation, share in-flight canonical reads and evaluate resident MCP only after measuring startup overhead and shutdown correctness | CORE-07 |
| Ancillary inference is only conditionally deferred | `serve.mjs:1075` running recap skips when busy at launch; identity and cleanup have their own asynchronous requests; `core.mjs:227` warms a local fallback alongside hosted auth | Work already in flight can compete with new live demand. Enforce a priority/resource budget and generation guards; defer optional jobs under pressure. Separate lanes alone do not prove local compute isolation | CORE-08 |
| Stop deadlines do not form one budget | `LiveCoach.swift:265–274` allows 25s; `serve.mjs:1324–1329` waits for queued turns/attribution then recap; default model call can allow 45s; `LiveHUD.swift:347` finishes UI after requesting recap | Stop may lose final recap/archive under slow paths; native finishing state does not prove archive acknowledgment. Single bounded finalize protocol with idempotent call ID, durable transcript first, explicit recap outcome and archive acknowledgment | CORE-09 |
| Durable capture can block main callbacks | `LiveHUD.swift:218–237` feeds finalized turns on main; `LiveCoach.swift:235` synchronously journals; `CaptureJournal.swift:21` opens/seeks/writes/synchronizes per event | Storage pressure can delay UI/ingestion. Move ordered writes off the UI thread only with documented durability, bounded queue, stop barrier and failure reporting; do not simply remove fsync | CORE-10 |
| History cost grows with archives | `CallArchive.swift:10–24` reads all archives and serializes turn signatures; `WorkspaceGuide.swift:36–38` loads history files; journal recovery uses repeated scans | Long-lived usage needs bounded history metadata loading, stable call-ID dedup and measured recovery complexity, while preserving existing archives | CORE-11 |
| Startup retains dictation-specific gates | `AppDelegate.swift:80–105`, `Permissions.swift:29–34`: upgrade reset uses inherited bundle identity, synchronous waits for accessibility; live calls do not paste into external apps | Investigate dependency separation so call startup is not held by optional dictation permission. Do not remove permission checks blindly; verify installer identity and actual active path | CORE-12 |
| Fork has multiple entry points and stale scaffolding | `StreamingTranscriber.swift` explicitly has empty inference TODO and no production constructor references in source search; `SessionCapture`, `EngineRunner`, dictation and live callers coexist; external-provider branch after whitelist in `core.mjs` is unreachable | Ownership is unclear and comments can mislead contributors. Document retained behavior, isolate/remove only proven-unused code after reachability/tests; preserve licensed upstream notices | CORE-13 |
| Portable runtime and provenance unfinished | `WorkspacePaths.swift`, `package.sh` embeds clone root; `rag.mjs:47` PDF fallback points to original machine-specific environment; model download tracks mutable main and validates magic rather than hash | Fresh-machine failures and unsupported upgrades need a compatible packaging/configuration contract, pinned approved artifacts and migrations | CORE-14/15 |
| Audio/device failures are distinct from model failures | `SystemAudioCapture.swift` needs macOS14.4 despite package macOS13; `LiveHUD` can keep mic-only state and rebuild output tap | Verify unsupported OS, input/output changes, permission loss, AEC failure, silence and overlap with observable degraded states. Do not infer identity from a channel alone | CORE-16 |
| Validation suite is not one release gate | 24 suites selected by `test-safe.sh`; others cover names, shutdown, RAG/PDF, recap and endurance separately; Swift runner depends on local SDK; legacy E2E may change devices | Publish a scenario-to-test map, isolated state and reproducible versions. Safe checks do not certify real audio, production latency or full-call finalization | CORE-17/18 |

Line references describe the reviewed revision and may shift in later commits. Complexity observations are structural, not timing measurements. A changed prompt or shorter model response must pass blind discovery-quality, context, source and speaker regressions before adoption.

## Inherited behavior disposition

| Existing subsystem | Current evidence | Core maintenance decision |
| --- | --- | --- |
| Hotkeys, push-to-talk/toggle, clipboard paste and punctuation | AppDelegate, HotkeyManager, TextInserter, RecordingLifecycle, TextPostProcessor; reachable dictation code | Preserve supported behavior; isolate from live-call readiness, settings and transcript evidence. Test focus, clipboard restoration, hotkey collisions and cancel/sleep. No removal without explicit decision |
| Retained recording history and replay | RecordingStore, configuration, StatusBarController, ReplayRunner | Document retention setting and storage alongside live temp audio; ensure cancel/failure/quit cleanup and existing history compatibility. Do not mistake recording retention for transcript retention |
| Config migration, device preference and model download | Config handles legacy hotkey and device keys; model/download/readiness helpers | Preserve backward compatibility, surface invalid settings, pin approved model artifacts; verify update/rollback |
| Streaming scaffold and provider leftovers | Empty inference scaffold and disabled provider paths | Reachability audit followed by small removal/isolation PRs; no new engine or provider |
| Local prep and reference imports | CallPrepDraft, ReferenceLibrary, RAG, existing read-only prep modules | Optimize existing import/index/cancel/error paths and local-only behavior; no new knowledge source or integration |
| Existing recap/export/CRM handoffs | WorkspaceGuide and provider/helper modules | Audit every reachable action for preview, explicit trigger, cancel/failure and least privilege. Dormant placeholders remain dormant; no automatic publishing |

## Measurement and experiment design

Use a fixed approved hardware/OS/model matrix and the same fictional workload for baseline and candidate. Include cold launch, warm call, offline/local mode, Cisco path when authorized, 2-person and 3–4-person conversations, 25s+ monologues, silence, interruptions, names/corrections and concurrent documentation questions. Run 30 repetitions for short benchmarks; retain all outcomes and sample counts. A p95 from a tiny scenario set or last-64 ring is not production certification.

Capture real-time factor, audio backlog in seconds, ASR finalization latency, voice latency, event-loop delay, journal/snapshot/decode/render duration, source startup/read latency, token count, first valid cue, and final displayed valid cue. Record process RSS/CPU/thermal condition plus child-process counts. Do not log prompts, raw customer text, secrets or customer names. Use local aggregate operational evidence and explicit sanitized exports.

Initial optimization goals are proposals, not results: live cue finalized-transcript-to-visible p95 under 4s, sourced answer processing p95 under 10s excluding separately reported intentional speech hold, and no more than 10% regression in unaffected stages. Report user-visible question-to-answer latency including hold too. Full-call memory acceptance must specify exact resource thresholds on reference hardware after baseline; start with no monotonic idle leak and no persistent queue growth, not an arbitrary universal RSS number. Quality/identity/citation regressions are a veto even if latency improves.

Run one change at a time; compare identical fixtures, quality ratings and failures. Do not shrink silence holds, bypass attribution validation, hide uncertain speakers, truncate early evidence, weaken durability, or change privacy/network policy to win a speed benchmark.

## Review limitations and verification

Fresh `bash scripts/test-safe.sh` exited 0 on October 4: all 24 selected suites passed. The safe suites use isolated synthetic transports; hosted-path mocks are not live Cisco requests. No real-time endurance, production provider benchmark, natural multivoice comparison, native UI rehearsal or upstream-version/license certification is implied. The review did not access customer transcripts or recordings. Governance decisions require their designated owners; new feature plans are parked.

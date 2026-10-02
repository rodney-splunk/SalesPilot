# SalesPilot

Internal Mac discovery assistant for Solutions Engineers. SalesPilot transcribes a call locally, suggests contextual follow-up questions, tracks discovery-framework evidence, collects notes and retrieves sourced product or competitive answers. It is a development/pilot utility, not a Cisco-approved production deployment.

## Roadmap and next presentation

The [complete roadmap](docs/ROADMAP.md) tracks presentation polish, customer-pilot acceptance and deployment gates with stable task IDs, priorities, criteria and dependencies. Use the [presentation runbook](docs/PRESENTATION.md) for next week’s rehearsal. Contributors should claim a scoped issue before parallel work; see [Contributing](CONTRIBUTING.md).

## Start here

- **Trying it:** build the app, open **More → Show example**, then follow the usage section below. The example is fictional and records nothing.
- **Developing it:** read Architecture and Development, run the safe checks, then create a feature branch.
- **Real calls:** complete **More → Before you join**, obtain the required authorization and participant consent, and choose the processing mode deliberately.

## Requirements

The supported development target is an Apple Silicon Mac. The Swift package declares macOS 13+, but system call-audio capture requires a Mac/OS supporting Core Audio process taps; use the in-app readiness check rather than assuming minimum-version capture support. Intel and other OS configurations have not been certified.

Install Apple Xcode Command Line Tools or Xcode with a working SwiftUI SDK, Node.js 22+ and Python 3. Homebrew is a convenient dependency manager. Native source has no third-party Swift package dependencies; engine modules use Node built-ins. Local transcription requires whisper.cpp CLI/server and a compatible model. Optional speaker embeddings require a separate Python environment and an approved model artifact.

```sh
xcode-select --install
brew install node python whisper-cpp
```

Install these through your organization's approved process. Homebrew's Apple Silicon binaries normally reside in `/opt/homebrew/bin`; the native launcher also checks `/usr/local/bin`. Python Pillow is optional for app-icon generation. Do not run the upstream open-wispr installer: this fork has a different app and workflow.

## Build and run

Clone this private repository to a stable location: the development app records the workspace's absolute path when built. Do not move or delete the clone while using that app; rebuild after moving it.

From the repository root:

```sh
bash open-wispr/package.sh
open "$HOME/Applications/SalesPilot.app"
```

The script builds a release binary, packages the app and uses a local `SalesPilot Self-Signed` identity if available, otherwise ad-hoc signing. It does not include Rodney's certificate or private key. Ad-hoc builds may need permissions re-granted after rebuilding. Managed signing, notarization and organization-wide distribution remain separate work.

Build a candidate without replacing your installed copy:

```sh
SALESPILOT_APP_PATH="$HOME/Applications/SalesPilot-Dev.app" bash open-wispr/package.sh
```

Do not run two app copies against the same workspace simultaneously. No node install step is required.

### Local transcription and models

The app checks `~/.config/open-wispr/models`, Homebrew whisper model directories and `~/.cache/whisper` for `ggml-<modelSize>.bin`. Its inherited configuration lives at `~/.config/open-wispr/config.json`. The default whisper model may be downloaded on first launch; use your approved download path and review its license before customer use. Models and that configuration are intentionally absent from Git.

For local coaching, install/run an approved Ollama runtime. The engine defaults to `qwen2.5:14b` for local live coaching and `qwen2.5:7b` for worker/fallback tasks. Model size affects memory and latency. Install only models permitted for your endpoint and data class. Local-only mode does not download missing models for you. Technical sources may be unconfirmed without local references because this mode blocks public retrieval.

### Optional speaker embeddings

Create `diarize/.venv` with approved `numpy` and `sherpa-onnx` packages. Provision an approved compatible speaker embedding model as `diarize/speaker.onnx`; preserve its exact version, hash and license evidence. No weights are shipped here because provenance review remains open. Without the runtime or weights the sidecar falls back to channel attribution. It cannot promise accurate individual attribution or separate simultaneous speech; correct labels in the people strip. Names are associated within a call, not saved in a people library.

### Cisco CIRCUIT setup

Each developer must obtain her own approved access. GitHub access is not CIRCUIT access. No working credential or client registration is included.

Copy `config/circuit.example.json` to `engine/.circuit.json`, then replace the non-secret endpoint/client/version placeholders with the approved registration values. Keep `credential_store` set to `macos-keychain`. Secrets use Keychain service `com.salespilot.circuit`, account `credentials`, containing JSON with `client_secret` and `app_key`.

`security/keychain-store.swift` accepts that JSON through stdin. Compile it locally with `swiftc security/keychain-store.swift -o /private/tmp/salespilot-keychain-store`. Provision secrets through your approved secure process: do not put secrets in shell arguments, command history, screenshots, commits or chat. The installed native app supplies the credential reader to its engine. For approved hosted command-line tests, set `SALESPILOT_CREDENTIAL_READER` to your built app's `Contents/MacOS/SalesPilot`. Never print the `provider-credentials` command's output.

Only approved Cisco authentication and inference hosts are enabled. Hosted model IDs are configurable; the current default is `gemini-3.1-flash-lite`, whose availability must be confirmed against your registration. Local-only mode blocks hosted inference/authentication and public documentation reads. Ghost is optional for contextual research, not required to launch SalesPilot; authenticate with your own authorized access.

## Using SalesPilot

1. Open the workspace from the menu-bar app. Onboarding begins with a mode chooser that explains both choices; your selection is saved. Choose SPIN, MEDDPICC or Challenger.
2. Choose **More → Call mode → Flexible conversation** for a mixed agenda, or **Discovery first** to understand needs today and shape a tailored demo as a possible next step. Choose before capture. Technical and competitive questions remain available in either mode.
3. Use **More → Call context** for the goal, background and current-call participants/exact name spellings. Save deliberately; an unsaved draft does not replace live context. Clear context between unrelated customers.
4. Run **More → Before you join**. Check microphone, local models, permissions and provider readiness. Obtain all required authorization and consent before capture.
5. Start a call and select **Cisco + docs** or **Local only** at the consent checkpoint. The checkbox is an operator attestation, not proof of participant consent.
6. **Coach** shows Next Move and methodology coverage. Click a coverage point for its supporting transcript and remaining gap. The transcript and compact window support following the conversation; hiding the transcript does not stop capture.
7. **Notes** gathers customer statements with evidence. Review corrections and assumptions before using them.
8. **Research** nests **Answers**, **Competition** and **Opportunities**. A competitive-answer arrow on Coach opens Competition directly. Competitor mentions produce neutral validation prompts; comparisons require readable evidence for both sides. Internal enablement links require your own Cisco access. Splunk Core is the initial positioning baseline; premium applications require an expressed need.
9. Generated answers stay unresolved until delivered/marked answered or explicitly deferred. “Needs confirmation” means the evidence is insufficient; do not present it as verified.
10. End capture when finished. Review the recap and unresolved questions; **More → Past calls** opens previous local calls. Exports are deliberate local actions, not automatic email/CRM sends.

Use **More → Show example** to demonstrate the UI without recording; **Exit example** returns to the actual workspace. **More → Quick guide** reopens onboarding. Privacy & local data provides inventory, age review and archive holds; there is no approved automatic retention period baked in.

## Architecture

| Location | Responsibility |
| --- | --- |
| `open-wispr/Sources/OpenWisprLib` | SwiftUI workspace, capture, local ASR, permission/consent, journals and archives |
| `open-wispr/Sources/OpenWispr` | Native executable and developer CLI entry points |
| `engine/serve.mjs` | Streaming call engine; stdin events and local session updates |
| `engine/core.mjs`, `circuit.mjs` | Model routing, timeouts, Cisco transport and Keychain reader |
| `engine/dialogue-plan.mjs`, `call-purpose.mjs` | Conversation intent, contextual follow-ups and discovery-only boundaries |
| `engine/question-ledger.mjs` | Open questions, search/ready states and explicit resolution |
| `engine/competition.mjs`, `splunkdocs.mjs`, `rag.mjs` | Competitive evidence, product docs and local references |
| `engine/speaker-*.mjs`, `diarize/` | Voice continuity/alignment and optional embedding sidecar |
| `frameworks/`, `engine/packs.mjs` | Human-readable frameworks and runtime packs; keep them aligned |
| `tests/`, `engine/test-*.mjs` | Synthetic regression fixtures and checks |
| `sessions/` (untracked) | Local transcript, notes, prep, reference index and call archives |

Audio → local capture/transcription → call engine → local transcript/notes/coverage. In Cisco mode, selected masked text and sanitized public evidence may go to Cisco inference; raw audio is not sent to that provider. Public competitive retrieval uses fixed vendor documentation URLs, without customer question text. The provider may still receive confidential business context: masking is not complete DLP or policy approval.

This development build uses the clone as its runtime workspace. Never commit or share `sessions/`, caches, recordings, local reference libraries, secrets or actual call fixtures. Files remain accessible to the logged-in user; endpoint encryption, approved backups and retention still matter.

## Development and checks

```sh
git switch -c feature/short-description
bash scripts/test-safe.sh
```

The safe runner selects synthetic hermetic engine cases. It neither launches the app nor changes audio devices and needs no Cisco login. It is a useful starting gate, not the complete quality certification.

Build the native package and run isolated native checks:

```sh
bash open-wispr/package.sh
SALESPILOT_ROOT="$(mktemp -d)" "$HOME/Applications/SalesPilot.app/Contents/MacOS/SalesPilot" verify-ui-offline
```

For more Swift checks, inspect `tests/swift/run.sh`. The legacy `test-all.sh`, `uitest.sh` and `tests/e2e/run.sh` are **not safe defaults during a meeting**: some launch/restart the app, stage state, require accessibility, use hosted models, play audio or change devices. Review them and use a disposable workspace, with no call running. Some legacy fixtures still assume original development paths or local artifacts and need modernization before a clean-clone full run. Live-provider test files explicitly require your own approved credentials/network.

Change coaching logic with interrupted/fragmented conversations, topic changes and explicit corrections in mind. Assert both successful output and forbidden behavior: no invented commitments, no automatically answered questions, no unsupported competitive claims and no external reads in local-only mode. Keep real customer data out of tests. Submit a small pull request explaining the user behavior changed, checks run and known limits. A developer's local tests do not establish natural-call transcription or overlap accuracy.

## Troubleshooting

- **App cannot find engine:** the clone moved or the bundle embeds another workspace. Rebuild from this clone; do not share Rodney's prebuilt app with its machine-specific path.
- **No transcription:** run readiness, verify whisper binaries/models and Mac audio permissions. Restart only after ending any active capture.
- **Channel labels or uncertain speakers:** optional speaker runtime/model may be missing, or speech is too short/overlapping. Check locally; do not invent participants.
- **No hosted answer:** check your CIRCUIT registration, Keychain access and provider readiness. Do not weaken host or certificate checks.
- **No source-backed comparison:** vendor documentation may be unavailable or evidence insufficient. Needs confirmation is expected; avoid inventing facts.
- **Slow coaching:** examine model choice and local memory pressure. Local fallback can take several seconds; production timing is not guaranteed.
- **Permission grants change after build:** signing identity changed; use the organization's approved development signing process.

## Ownership, licensing and release limits

Private repository access should be restricted to approved collaborators. The upstream open-wispr MIT notice is retained under `open-wispr/LICENSE`. That notice is not a blanket license grant for all new internal SalesPilot code or model artifacts; confirm ownership and distribution rights before broader sharing. Do not publish public releases or export internal competitive material.

Customer-call readiness still requires natural multi-party/overlap acceptance, full-hour finalization retest, production latency/outage measurement and organizational decisions on data classification, CIRCUIT terms, consent, retention/backups, EDR, model/dependency approval and signing/distribution. See `docs/ROADMAP.md` and `docs/PRIVACY.md`. This repository does not represent completed Cisco compliance approval.

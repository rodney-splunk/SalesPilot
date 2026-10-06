# SalesPilot

Internal Mac discovery assistant for Solutions Engineers. SalesPilot transcribes a call locally, suggests contextual follow-up questions, tracks discovery-framework evidence, collects notes and retrieves sourced product or competitive answers. It is a development/pilot utility, not a Cisco-approved production deployment.

## Core platform roadmap

The [complete roadmap](docs/ROADMAP.md) tracks core-platform optimization across startup, capture, coaching, answers, recovery, history and deployment, with P1–P4 priorities and measurable acceptance. Read the [architecture review](docs/ARCHITECTURE-REVIEW.md) for source findings. Other new feature work is parked; Practice Discovery is an explicitly requested addition. Contributors should claim a scoped issue before parallel work; see [Contributing](CONTRIBUTING.md).

## Start here

- **Trying it:** build the app, open **More → Show example**, then follow the usage section below. The example is fictional and records nothing.
- **Developing it:** read Architecture and Development, run the safe checks, then create a feature branch.
- **Real calls:** complete **More → Before you join**, obtain the required authorization and participant consent, and choose the processing mode deliberately.

## Install SalesPilot on your Mac

Follow these steps to install and run SalesPilot on your Mac. The current distribution is **build from source**; there is no standalone installer yet. Start with [the private repository](https://github.com/rodney-splunk/SalesPilot) and build your own app using the instructions below.

### 1 Get repository access

Sign into GitHub with the account that has been invited to the private repository. If the link shows 404 or cloning says repository not found, check that account and ask the maintainer to grant access to your verified username. GitHub access does not grant Cisco provider or documentation access.

After prerequisites below are installed, clone once into a stable folder:

```sh
mkdir -p "$HOME/Developer"
git clone https://github.com/rodney-splunk/SalesPilot.git "$HOME/Developer/SalesPilot"
cd "$HOME/Developer/SalesPilot"
```

Use your organization's approved GitHub sign-in method. Do not put a GitHub token into the clone URL. If you already cloned the repository, use that existing folder instead of creating another copy.

### 2 Check the Mac and tools

Use Apple Silicon and **macOS 14.4 or later for customer system-audio capture**. macOS 13 is the package minimum, not full-call capture support. Check **Apple menu → About This Mac** for chip and OS. Install the prerequisites in Requirements through the approved process, then verify:

```sh
xcode-select -p
swift --version
node --version
python3 --version
command -v whisper-cli
command -v whisper-server
```

Node must be 22 or later. The app searches Homebrew's `/opt/homebrew/bin` and `/usr/local/bin` locations for Node and Whisper, so a tool available only through a terminal version manager may not be found by the app. Whisper CLI is required; the resident server improves repeated transcription and is recommended. There is no `npm install` step. Full Xcode may be needed if the installed Command Line Tools SDK cannot compile SwiftUI.

### 3 Build the app

From the clone root, with SalesPilot quit and no call being captured:

```sh
bash open-wispr/package.sh
```

Expected final output includes `Built:` and your `~/Applications/SalesPilot.app` path. The package script replaces that destination; it does not create a portable installer. Keep the clone at this location because the app embeds its runtime workspace path. It must be rebuilt if you move the clone.

### 4 Prepare transcription models

Provision approved Whisper model files as described in Local transcription and models. For English calls, the current live path prefers `small.en` and the final pass prefers `medium.en`, then `large-v3-turbo`, then the available live model. First launch also checks the configured default model. Missing models can trigger a download; models are not included in Git.

If your approved process allows the bundled downloader, these supported commands install models into the inherited model folder:

```sh
"$HOME/Applications/SalesPilot.app/Contents/MacOS/SalesPilot" download-model small.en
"$HOME/Applications/SalesPilot.app/Contents/MacOS/SalesPilot" download-model medium.en
"$HOME/Applications/SalesPilot.app/Contents/MacOS/SalesPilot" set-model small.en
```

The current downloader reads the upstream model repository and checks file format, not a pinned approved hash. Use an approved artifact source and verify its license/hash for customer use; these commands do not establish organizational approval. Downloads can take time. Do not run them during a customer call.

### 5 Launch and complete first-use permissions

```sh
open "$HOME/Applications/SalesPilot.app"
```

SalesPilot runs as a menu-bar app, so look for its menu-bar icon if no Dock icon is visible. Open its workspace. Complete the requested **Microphone**, **Accessibility** and, when system capture is started, **audio capture** permissions. Accessibility is still a startup dependency inherited from dictation/clipboard behavior; separating it from live calls is tracked in CORE-12. If setup appears stuck waiting for Accessibility, use **System Settings → Privacy & Security → Accessibility**, approve the locally built app through the allowed device process, and retry when no call is active. Managed-device restrictions require the endpoint support process.

Do not disable Gatekeeper or other endpoint protections if macOS blocks the development build. Signing/notarized distribution is still an open release gate. Follow the approved development-signing/support process.

Choose a call mode in onboarding. Open **More → Show example** for a fictional walkthrough; use **Exit example** afterward. The example needs no Cisco credentials or actual call recording, but it does not bypass native first-launch prerequisites. **More → Quick guide** reopens the guide.

### 6 Choose how actual calls will be processed

| Path | What to configure | Expected behavior |
| --- | --- | --- |
| Fictional UI example | Native build and startup prerequisites | Curated data; no live capture or model-quality test |
| Local-only coaching | Approved running Ollama and required installed local models | Local ASR/coaching; public documentation and hosted calls blocked; local references optional |
| Cisco coaching and docs | Your approved CIRCUIT registration/configuration, Keychain credentials, local Whisper models and separate docs connector | Local ASR; selected text can reach Cisco; sourced answers depend on readable evidence and connector/network availability |

If your approved process permits Ollama, start its local service and provision `qwen2.5:14b` and `qwen2.5:7b` as described below. Confirm available models with `ollama list`; a running service with some other model is not proof the configured coaching models are installed. On Macs with insufficient resources, ask for an approved configuration rather than assuming the default models will perform well.

For Cisco setup, follow Cisco CIRCUIT setup below. Obtain the non-secret configuration and authorization from the registration owner, provision your own secrets through the approved secure process, and run connection checks. Use your own authorized credentials; do not copy another user's Keychain or registration secrets.

For real Splunk documentation retrieval, the current engine expects the existing Ghost Splunk docs MCP server at `~/.config/ghost/mcp-servers/dist/servers/splunk-docs/server.js`, or a documented `SALESPILOT_DOCS_SERVER` override passed to the engine environment. Ghost alone being installed does not prove this connector exists. Arrange the approved connector setup with the maintainer and check **More → Before you join**; run its connection checks for readable docs. Local reference imports remain an alternative, and public competitive-source reads have a separate path. A missing connector must remain visible as unavailable evidence.

### 7 Confirm readiness before a real call

- [ ] App launches and the fictional example opens/exits correctly.
- [ ] **More → Before you join** reports the actual microphone/model/provider/documentation state. Read each result; a configured credential or installed model is not complete acceptance.
- [ ] Optional speaker runtime status is understood; missing weights means channel-based attribution and manual review, not reliable multi-person identification.
- [ ] Call context is saved for this customer, framework/mode chosen, and prior customer's context cleared.
- [ ] Applicable approval and participant consent are in place; choose **Local only** or **Cisco + docs** deliberately at Start call.
- [ ] In an authorized test, both microphone and customer audio are actually present. Then stop, inspect recap/history and confirm no active capture remains.

A fresh second-Mac installation has **not yet been certified**. Report exact failed step, app/source version and sanitized error through the repository's bug template. Never attach real call content or credentials. This checklist guides installation; it does not replace the customer-pilot release gates.

### Updating your copy

End the call, wait for finalization and quit SalesPilot first. From your clone, preserve any local changes before updating; do not use a forced reset:

```sh
git status --short
git pull --ff-only
bash open-wispr/package.sh
open "$HOME/Applications/SalesPilot.app"
```

If pull reports local conflicts/divergence, coordinate with the maintainer. Rebuilding can require permissions again if the signing identity changes. Never run two copies against the same workspace.

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
6. **Coach** shows the next question and methodology coverage. Click a coverage point for its complete supporting evidence trail and remaining gap. Early, middle and late SPIN statements remain available to coaching. The transcript and compact window support following the conversation; hiding the transcript does not stop capture.
7. **Notes** gathers customer statements with evidence. Review corrections and assumptions before using them.
8. **Research** contains **Answers** and **Opportunities**. Answers combines technical and competitive responses; its menu filters All answers, Technical or Competitive. A competitive-answer arrow on Coach opens Answers with the Competitive filter. Competitor mentions produce neutral validation prompts; comparisons require readable evidence for both sides. Vendor explanations use separate paragraphs. Retrieved documentation is staged in call-scoped memory while the customer finishes adding scope; the latest context refines the same unresolved comparison, and superseded answers stay hidden. This is a short quiet-period gate, not a prediction of future speech. Search status lives with the answer; the next-question card stays a follow-up cue. Internal enablement links require your own Cisco access. Klue cards are currently linked resources; generated comparisons are documentation-backed, not automatically CI-approved talk tracks. A supported Klue Content API connection requires an approved integration key and audience/product-scope controls; that feature is parked in the historical CI-01 plan during core optimization. Splunk Core is the initial positioning baseline; premium applications require an expressed need.
9. Generated answers stay unresolved until delivered/marked answered or explicitly deferred. Unconfirmed answers offer Retry search during a live call; retry preserves the same question. Request failed differs from insufficient evidence. “Needs confirmation” means the evidence is insufficient; do not present it as verified.
10. End capture when finished. Review the recap and unresolved questions; **More → Past calls** opens previous local calls. Exports are deliberate local actions, not automatic email/CRM sends.

Use **More → Show example** to demonstrate the UI without recording; each mode has a distinct response to the same immediate demo request. Switch via More → Call mode to compare them; **Exit example** returns to the actual workspace. **More → Quick guide** reopens onboarding. Privacy & local data provides inventory, age review and archive holds; there is no approved automatic retention period baked in.

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
- **Repeated Keychain prompts:** the native app caches authorized Cisco credentials in memory for its running session and supplies new call engines through a private pipe. Quitting clears that cache. “Privacy & local data → Check Cisco credential access” explicitly reloads credentials after rotation. Keep the app path and signing identity stable across updates; macOS may require authorization again if either changes. Call consent remains a separate checkpoint for each meeting.
- **No hosted answer:** check your CIRCUIT registration, Keychain access and provider readiness. Do not weaken host or certificate checks.
- **No source-backed comparison:** vendor documentation may be unavailable or evidence insufficient. Needs confirmation is expected; avoid inventing facts.
- **Slow coaching:** examine model choice and local memory pressure. Local fallback can take several seconds; production timing is not guaranteed.
- **Permission grants change after build:** signing identity changed; use the organization's approved development signing process.

## Ownership, licensing and release limits

Private repository access should be restricted to approved collaborators. The upstream open-wispr MIT notice is retained under `open-wispr/LICENSE`. That notice is not a blanket license grant for all new internal SalesPilot code or model artifacts; confirm ownership and distribution rights before broader sharing. Do not publish public releases or export internal competitive material.

Customer-call readiness still requires natural multi-party/overlap acceptance, full-hour finalization retest, production latency/outage measurement and organizational decisions on data classification, CIRCUIT terms, consent, retention/backups, EDR, model/dependency approval and signing/distribution. See `docs/ROADMAP.md` and `docs/PRIVACY.md`. This repository does not represent completed Cisco compliance approval.


To replay the fictional multi-minute audio through actual local ASR and verify whole-call SPIN memory, run `bash scripts/test-holistic-audio.sh` after building. The script writes speech to a file, uses an isolated workspace and leaves its fictional artifacts in a temporary directory. It requires ffmpeg and an installed local Whisper model; it does not open or change microphone/speaker devices. The safe suite includes a 282-turn context fixture and a real-engine layered comparison replay. Natural multivoice calls still require their own acceptance.

## Practice Discovery

Open **More → Practice Discovery** when no call is active. Confirm fictional-only use and review the current processing choice. Practice is separate from saved customer prep and live-call history.

- **Interactive practice:** the fictional customer introduces herself. Speak naturally; a question is sent automatically after about 1.25 seconds of sustained silence. Brief pauses stay within the same turn; a 60-second limit bounds continuous speech. Sustained speech during a reply stops playback and captures your interruption. **Mute microphone** discards unfinished input and cancels the current reply; **Resume microphone** starts listening again. Microphone capture continues during playback and processing, using one voice-processed audio engine for echo cancellation. A headset is recommended; residual echo and noisy environments still need device-specific validation. The AI selects relevant, vetted responses from a bounded fictional customer scenario, rather than generating arbitrary customer facts.
- **Watch a demo:** both fictional voices play automatically. No microphone capture is used. Transcription, coaching, notes and source retrieval run against the spoken scenario rather than a prefilled example card.

Generated speech files are played and transcribed through the local Whisper path. This verifies audio-to-transcript processing, not system-audio capture from Webex or a production customer's accent/voice. macOS speech voices, Node, and an approved Whisper model are required. Interactive replies also need the selected Cisco/local inference setup. Local-only processing blocks hosted inference and public searches; source answers require the normal configured documentation transport when Cisco processing is selected. No customer reference library or saved prep is read in practice.

Use **End practice** before returning to customer calls. Practice sessions are stored separately under `sessions/practice`; temporary audio is cleaned up after use. Treat your recorded practice speech according to organizational retention requirements and avoid real customer information. Interrupted or failed practice should be restarted; no automatic recap, export or customer action occurs. Already accepted speech segments are transcribed in order even if you resume speaking; obsolete AI replies are canceled. Only completed customer replies are added to the transcript; interrupted replies are omitted rather than shown as fully heard. Device changes fail visibly and require restarting practice. Watch a demo still uses no microphone. Hands-free endpoint and interruption behavior should be accepted on your actual microphone/headset before a stakeholder demonstration.

Developers can run `bash scripts/test-practice-audio.sh` on macOS for microphone-free endpoint checks. The equivalent XCTest cases require a full Xcode installation; this machine’s Command Line Tools do not provide XCTest. These tests do not validate physical echo cancellation.

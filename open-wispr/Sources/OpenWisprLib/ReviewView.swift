// ReviewView.swift — the "Discovery workspace" window.
// Shows the transcript LIVE as you speak (from LiveState), and overlays coaching (coverage +
// SAY NEXT) once you run Analyze Call, which reads latest.json produced by build-session.mjs.

import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let reloadSession = Notification.Name("ReloadSession")
    /// Posted the instant a new call starts, so the previous call leaves the screen immediately
    /// instead of lingering until the audio engine finishes coming up.
    static let clearSession = Notification.Name("ClearSession")
    static let analysisStarted = Notification.Name("AnalysisStarted")
    static let callPrepChanged = Notification.Name("CallPrepChanged")
}

// MARK: - Session schema (matches engine/build-session.mjs output)
struct VoiceFragment: Codable { var text: String; var who: String; var start: Double; var end: Double }
struct TurnData: Codable { var me: Bool; var who: String; var time: String; var text: String; var coachTarget: String?; var coachQ: String?; var startedAt: Double? = nil; var side: String? = nil; var rawText: String? = nil; var speakerStatus: String? = nil; var voiceFragments: [VoiceFragment]? = nil }
struct CoachProgress: Codable { var state: String; var message: String; var questionId: Int? = nil }
struct CustomerQuestion: Codable, Identifiable { var id: Int; var q: String; var speaker: String; var status: String; var kind: String; var turnIds: [Int]; var answer: LiveAnswer? = nil }
struct CoverageDetail: Codable { var id: String; var name: String; var status: String; var quote: String?; var turnId: Int?; var speakerUnconfirmed: Bool; var criterion: String; var remaining: String }
struct CovData: Codable { var name: String; var status: String }
struct NextQData: Codable { var q: String; var tag: String; var reason: String? = nil }
struct SpeakerData: Codable { var clusterId: Int; var label: String; var side: String; var organization: String? = nil }
struct LiveAnswer: Codable { var q: String; var answer: String; var sources: [String]?; var status: String? = nil; var sourceTitles: [String: String]? = nil; var category: String? = nil; var requestFailed: Bool? = nil }
struct MentionedPerson: Codable { var name: String; var role: String; var organization: String; var inferred: Bool; var attendance: String; var quote: String; var who: String; var turnId: Int? }
struct Person: Codable { var name: String; var role: String?; var decisionMaker: Bool?; var side: String? = nil; var organization: String? = nil; var nameEvidence: String? = nil }
/// How you're DELIVERING, not what you're asking. These are the four things discovery is actually
/// scored on, and all four are silent failures: you cannot feel yourself talking 65% of the time.
struct SolutionArea: Codable { var id: String; var name: String; var area: String; var score: Int; var probes: [String]; var evidence: [String] }
/// What the CUSTOMER keeps returning to, with the words that earned it. Deliberately not a
/// recommendation: discovery is meant to find this out, not assume it.
struct SolutionSignals: Codable { var status: String; var areas: [SolutionArea]; var note: String? }

struct DeliveryData: Codable {
    var talkRatio: Int; var fillerPerMin: Int; var longestMonologueSec: Int; var openingFramed: Bool?
}
struct SessionData: Codable {
    var title: String; var subtitle: String; var framework: String; var coveragePct: Int
    var turns: [TurnData]; var coverage: [CovData]; var nextq: [NextQData]
    var customerQuestions: [CustomerQuestion]? = nil
    var coachProgress: CoachProgress? = nil
    var coverageDetails: [CoverageDetail]? = nil
    var notes: [CallNote]? = nil
    var followups: [String]? = nil
    var recap: String? = nil
    var nextSteps: [String]? = nil
    var customerName: String? = nil
    var customerRole: String? = nil
    var roster: [Person]? = nil
    var speakers: [SpeakerData]? = nil
    var mentionedPeople: [MentionedPerson]? = nil
    var liveAnswer: LiveAnswer? = nil
    var answerHistory: [LiveAnswer]? = nil
    var competition: [CompetitiveSignal]? = nil
    var callPurpose: String? = nil
    var opportunities: [SolutionOpportunity]? = nil
    var delivery: DeliveryData? = nil
    var phase: String? = nil       // open -> discover -> close
    var audioWarning: String? = nil
    var solutions: SolutionSignals? = nil
    var name: String? = nil        // set when archived — the call's title
    var recoveryNotice: String? = nil
    var engineError: String? = nil
}

/// Single source of truth for which methodology is selected. Three separate places used to hardcode
/// "meddic"/"MEDDPICC", so a call always STARTED on MEDDPICC no matter what the picker said; only
/// switching mid-call worked, because that went through a different path.
enum Coaching {
    static let names = ["meddic": "MEDDPICC", "spin": "SPIN", "challenger": "Challenger"]
    static let elements: [String: [String]] = [
        "meddic": ["Metrics", "Economic Buyer", "Decision Criteria", "Decision Process",
                   "Paper Process", "Identify Pain", "Champion", "Competition"],
        "spin": ["Situation", "Problem", "Implication", "Need-payoff"],
        "challenger": ["Warmer", "Reframe / Teach", "Rational Drowning", "Emotional Impact",
                       "Value Proposition", "Take Control"],
    ]
    /// Read fresh every time: a `static let` would freeze whatever was selected at type-init.
    static var selectedID: String { UserDefaults.standard.string(forKey: "coachFramework") ?? "meddic" }
    static var selectedName: String { names[selectedID] ?? "MEDDPICC" }
    static var selectedElements: [String] { elements[selectedID] ?? elements["meddic"]! }
}

enum SessionStore {
    static var showingExample = false
    static var reviewSelection: SessionData? = nil
    static var reviewingLatest = false
    static var showingReady = true
    static func workspace() -> SessionData {
        if showingExample { return DemoSession.make() }
        if let reviewSelection { return reviewSelection }
        if showingReady && !reviewingLatest && !LiveState.shared.listening && !LiveState.shared.starting && !LiveState.shared.finishing { return fallback }
        if reviewingLatest || LiveState.shared.listening || LiveState.shared.starting || LiveState.shared.finishing || !LiveState.shared.turns.isEmpty { return load() }
        return fallback
    }
    static func showExample() {
        guard !LiveState.shared.listening, !LiveState.shared.starting, !LiveState.shared.finishing else { return }
        showingExample = true
        ReviewWindow.shared.show()
        NotificationCenter.default.post(name: .reloadSession, object: nil)
    }

    static var url: URL {
        WorkspacePaths.session
    }
    static func load() -> SessionData {
        return loadOptional() ?? fallback
    }
    /// Returns nil on a missing/torn/partial file, so callers can keep the last good session.
    static func loadOptional() -> SessionData? {
        if showingExample { return DemoSession.make() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: data)
    }
    /// Computed, not stored: it has to reflect the methodology selected RIGHT NOW.
    static var fallback: SessionData {
        SessionData(
            title: "Discovery workspace",
            subtitle: "Choose your framework, add context and start a call",
            framework: Coaching.selectedName, coveragePct: 0,
            turns: [],
            coverage: Coaching.selectedElements.map { CovData(name: $0, status: "open") },
            nextq: [])
    }

    /// A clean session shown the instant a live call starts (before any turn is coached).
    static func emptyLive() -> SessionData {
        SessionData(title: "Discovery workspace", subtitle: "Listening…",
                    framework: Coaching.selectedName,
                    coveragePct: 0, turns: [],
                    coverage: Coaching.selectedElements.map { CovData(name: $0, status: "open") },
                    nextq: [], followups: [], recap: nil, nextSteps: [])
    }
}

func coverageColor(_ s: String) -> Color { s == "done" ? .green : (s == "partial" ? .orange : .gray) }

/// Green while you're inside the target, amber approaching it, red past it. Thresholds are the ones
/// discovery is graded against: talk under 44%, under 5 fillers a minute, no monologue past 30s.
func metricColor(_ v: Int, good: Int, warn: Int) -> Color { v <= good ? .green : (v <= warn ? .orange : .red) }

/// One glanceable number. Big enough to read out of the corner of your eye mid-sentence.
struct MetricTile: View {
    let value: String, label: String, color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - View
struct ReviewView: View {
    @State private var session = SessionStore.workspace()
    @State private var showingExample = SessionStore.showingExample
    @ObservedObject private var live = LiveState.shared
    @State private var frameworkDisplay = Coaching.selectedName
    @State private var analyzing = false
    @State private var showGuide = false
    @State private var showCallMode = false
    @State private var showHistory = false
    @State private var showRecap = false
    @State private var showInsights = false
    @AppStorage("salesPilotGuideSeenV2") private var guideSeen = false
    @State private var showTranscript = true
    @State private var showReadiness = false
    @State private var showPrivacy = false
    @State private var showReferences = false
    @State private var workspaceTab = "coach"
    @State private var researchSection = "answers"
    @AppStorage("callPurpose") private var callPurpose = "standard"
    @State private var selectedCoverage: String? = nil
    @State private var selectedEvidence: String? = nil
    @State private var speakerNames: [Int: String] = [:]
    @AppStorage("coachCueMode") private var cueMode = "autopilot"
    /// Bumped whenever the view is deliberately cleared. A session read that started before the
    /// bump is stale by the time it finishes, and applying it put the LAST call's transcript, name
    /// and roster back on screen for a second or two every time a new call started.
    @State private var sessionEpoch = 0
    /// Serial: the engine can print @@updated@@ several times a second while an answer streams, and
    /// on a concurrent queue an older snapshot could finish last and overwrite a newer one.
    private static let reloadQueue = DispatchQueue(label: "review.session.reload", qos: .userInitiated)
    init(notes: Bool = false, section: String? = nil) {
        let research = ["answers", "competition", "opportunities"].contains(section ?? "")
        _workspaceTab = State(initialValue: research ? "research" : section ?? (notes ? "notes" : "coach"))
        _researchSection = State(initialValue: research ? section! : "answers")
    }

    private let frameworks = ["MEDDPICC", "SPIN", "Challenger"]
    private let fwID = ["MEDDPICC": "meddic", "SPIN": "spin", "Challenger": "challenger"]

    /// Match coaching to the captured turn, not another speaker repeating the same words.
    private func coaching(for turn: TurnData) -> (target: String, q: String)? {
        let key = SpeakerLookup.key(text: turn.text, startedAt: turn.startedAt, mic: turn.me)
        let exact = session.turns.filter {
            SpeakerLookup.key(text: $0.text, startedAt: $0.startedAt, mic: $0.me) == key
        }
        let candidates = exact.isEmpty ? session.turns.filter { $0.text == turn.text && $0.me == turn.me } : exact
        guard candidates.count == 1, let source = candidates.first, let q = source.coachQ, !q.isEmpty else { return nil }
        return (source.coachTarget ?? "Discovery", q)
    }

    /// Who the engine says spoke each customer line, keyed by the line itself.
    private var whoByText: [String: String] {
        return SpeakerLookup.labels(session.turns.flatMap { t in [SpeakerEvidence(text: t.text, startedAt: t.startedAt, mic: t.me, name: t.who)] + (t.rawText.map { [SpeakerEvidence(text: $0, startedAt: t.startedAt, mic: t.me, name: t.who)] } ?? []) })
    }

    /// Live turns take over the transcript while a session is running; otherwise show the analyzed one.
    private var displayedTurns: [TurnData] {
        if live.listening || !live.turns.isEmpty {
            let byText = whoByText
            // Fall back to a generic label only when we have several people AND no per-turn answer:
            // stamping the primary name on everyone misattributes lines on a multi-person call.
            return live.turns.map { captured in
                let matching = session.turns.filter { t in t.me == (captured.speaker == "you") && (captured.startedAt != nil && t.startedAt == captured.startedAt || t.rawText == captured.text || t.text == captured.text) }
                let resolved = matching.count == 1 ? matching.first : nil
                return TurnData(me: captured.speaker == "you",
                         who: byText[SpeakerLookup.key(text: captured.text, startedAt: captured.startedAt, mic: captured.speaker == "you")] ?? byText[captured.text] ?? (captured.speaker == "you" ? (byText[SpeakerLookup.microphoneKey] ?? "Microphone") : "Call audio"),
                         time: "", text: resolved?.text ?? captured.text, coachTarget: nil, coachQ: nil, startedAt: captured.startedAt, speakerStatus: resolved?.speakerStatus, voiceFragments: resolved?.voiceFragments)
            }
        }
        return session.turns
    }

    private var headerTitle: String { live.listening ? "Discovery workspace" : (session.name ?? session.title) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path").font(.system(size: 21, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SalesPilot").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(showingExample ? "Fictional example" : live.finishing ? "Finishing your transcript" : (live.starting ? "Preparing your call" : (live.listening ? "Your discovery workspace" : session.turns.isEmpty ? "Ready for your next call" : "Call review")))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Label(live.starting ? "Starting" : (live.listening ? "Live" : "Ready"), systemImage: live.listening ? "record.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(live.listening ? SalesPilotStyle.accent : Color.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(SalesPilotStyle.accent.opacity(0.08), in: Capsule())
                Menu {
                    Picker("Methodology", selection: $frameworkDisplay) { ForEach(frameworks, id: \.self) { Text($0) } }
                } label: { Label(frameworkDisplay, systemImage: "slider.horizontal.3") }.fixedSize().help("Choose SPIN, MEDDPICC or Challenger before you join. Switching during a call changes future coaching; past-call coverage keeps its original framework.")

                Menu {
                    Button("Call mode…") { showCallMode = true }.disabled(live.listening || live.starting || live.finishing)
                    Divider()
                    Button("Past calls") { showHistory = true }.disabled(live.listening || live.starting || live.finishing)
                    Button("Call context") { CallPrepWindow.shared.show() }
                    Button("Before you join") { showReadiness = true }
                    Button("Privacy & local data") { showPrivacy = true }
                    Button("Knowledge library") { showReferences = true }
                    Divider()
                    Button("Review recap") { showRecap = true }
                    Button("Speaking insights") { showInsights = true }
                    Button("Quick guide") { showGuide = true }
                    Picker("Coaching detail", selection: $cueMode) {
                        Text("Full question").tag("autopilot")
                        Text("Short nudge").tag("nudge")
                        Text("Coverage gap").tag("gap")
                    }
                    Divider()
                    if !live.listening && !live.starting && !live.finishing {
                        Button(showingExample ? "Exit example" : "Show example") {
                            if showingExample {
                                SessionStore.showingExample = false
                                NotificationCenter.default.post(name: .reloadSession, object: nil)
                            } else { SessionStore.showExample() }
                        }
                    }
                } label: { Label("More", systemImage: "ellipsis.circle") }.fixedSize().help("Prepare call context, add knowledge, review a recap, check speaking insights or reopen the quick guide.")
                if live.listening {
                    Button { LiveHUD.shared.showCompact() } label: { Image(systemName: "rectangle.compress.vertical") }
                        .help("Switch to compact view").accessibilityLabel("Compact view")
                }
                Toggle(isOn: $showTranscript) { Label("Transcript", systemImage: "text.alignleft") }
                    .toggleStyle(.button).help(showTranscript ? "Hide the transcript for more coaching space. Speech capture continues while the call is live." : "Show the customer’s words beside Coach. The transcript opens automatically when you start a call.")
                Button { LiveHUD.shared.toggle() } label: {
                    Label(live.finishing ? "Finishing" : (live.listening ? "End call" : "Start call"), systemImage: live.listening ? "stop.fill" : "waveform")
                }.buttonStyle(.plain).help(live.listening ? "End capture and finish this call’s transcript and recap." : "Start microphone and call-audio capture with the selected framework and saved context. The transcript opens automatically.")
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(live.listening ? Color.orange : SalesPilotStyle.buttonFill, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .disabled(live.starting || live.finishing)
            }.padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            if showingExample {
                HStack {
                    Label("Fictional demo", systemImage: "sparkles").fontWeight(.semibold)
                    Text("Curated discovery example. No call is being recorded.")
                    Spacer()
                    Button("Exit example") { SessionStore.showingExample = false; NotificationCenter.default.post(name: .reloadSession, object: nil) }
                    Spacer()
                }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 10)
                    .background(SalesPilotStyle.accent.opacity(0.08))
            }
            if !showingExample && SessionStore.reviewSelection != nil && !live.listening {
                HStack {
                    Label("Past call review", systemImage: "clock")
                    Spacer()
                    Button("Ready for a new call") {
                        SessionStore.reviewSelection = nil
                        SessionStore.reviewingLatest = false
                        SessionStore.showingReady = true
                        NotificationCenter.default.post(name: .reloadSession, object: nil)
                    }
                }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 8)
            }
            HSplitView {
                if showTranscript { transcript.frame(minWidth: 300, idealWidth: 460) }
                VStack(spacing: 0) {
                    Picker("Workspace section", selection: $workspaceTab) {
                        Text("Coach").tag("coach").help("One next question and your framework coverage. Use these as listening cues, not a script.")
                        Text("Notes").tag("notes").help("Customer statements collected by topic, with corrections and links back to the transcript.")
                        Text("Research").tag("research").help("Answers, competition and opportunities in one place. Coach links directly to the relevant view.")
                    }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
                    if let people = session.roster, !people.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 18) {
                                ForEach(people.indices, id: \.self) { i in
                                    let person = people[i]
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(person.name + (person.nameEvidence?.contains("voice not yet confirmed") == true ? " · expected" : "")).font(.system(size: 12, weight: .semibold))
                                        Text([person.side == "seller" ? "My team" : person.side == "customer" ? "Customer" : "Team unconfirmed", person.role ?? person.organization ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }.frame(maxWidth: 220, alignment: .leading)
                                }
                            }.padding(.horizontal, 24).padding(.vertical, 8)
                        }.fixedSize(horizontal: false, vertical: true).accessibilityLabel("People on the call").help("Names tied to speaker evidence. Team and job roles come from introductions or corrections; mentioned people are shown separately.")
                        Divider()
                    }
                    if workspaceTab == "notes" {
                        CallNotesView(notes: session.notes ?? []) { quote in
                            selectedEvidence = quote
                            showTranscript = true
                        }
                    } else if workspaceTab == "research" {
                        VStack(spacing: 0) {
                            Picker("Research view", selection: $researchSection) {
                                Text("Answers").tag("answers"); Text("Competition").tag("competition"); Text("Opportunities").tag("opportunities")
                            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.vertical, 12)
                            if researchSection == "competition" {
                                CompetitionView(signals: session.competition ?? [], current: session.liveAnswer, history: session.answerHistory ?? [], questions: session.customerQuestions ?? [], canResolve: live.listening) { quote in selectedEvidence = quote; showTranscript = true }
                            } else if researchSection == "opportunities" {
                                OpportunitiesView(opportunities: session.opportunities ?? []) { quote in selectedEvidence = quote; showTranscript = true }
                            } else {
                                LiveAnswersView(current: session.liveAnswer?.category == "competition" ? nil : session.liveAnswer, history: (session.answerHistory ?? []).filter { $0.category != "competition" }, questions: session.customerQuestions ?? [], canResolve: live.listening)
                            }
                        }
                    } else { rail }
                }.frame(minWidth: 360, idealWidth: 430, maxWidth: .infinity)
            }
            .overlay { if analyzing { analyzingOverlay } }


        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if !guideSeen { showGuide = true; guideSeen = true } }
        .sheet(isPresented: $showGuide) { WorkspaceGuide(canChangeMode: !(live.listening || live.starting || live.finishing)) }
        .sheet(isPresented: $showCallMode) { CallModeSettings() }
        .sheet(isPresented: $showHistory) { PastCallsView() }
        .sheet(isPresented: $showRecap) { RecapReview(session: session) }
        .sheet(isPresented: $showInsights) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Speaking insights").font(.title2.bold())
                Text("A reflection tool for your delivery. Review this after the call or when you need a quick check.").foregroundStyle(.secondary)
                if let d = session.delivery {
                    Text("You talked: \(d.talkRatio)% · Fillers/min: \(d.fillerPerMin) · Longest turn: \(d.longestMonologueSec)s")
                    if let warning = session.audioWarning { Text(warning).foregroundStyle(.orange) }
                } else { Text("Insights appear after speech is captured.").foregroundStyle(.secondary) }
                Button("Done") { showInsights = false }
            }.padding(24).frame(width: 500)
        }
        .sheet(isPresented: $showReadiness) { CallReadiness() }
        .sheet(isPresented: $showPrivacy) { PrivacyControls() }
        .sheet(isPresented: $showReferences) { ReferenceLibrary() }
        .onChange(of: callPurpose) { _ in
            if showingExample { session = DemoSession.make() }
            else if session.turns.isEmpty { session = SessionStore.fallback }
        }
        .onChange(of: frameworkDisplay) { newValue in
            let id = fwID[newValue] ?? "meddic"
            UserDefaults.standard.set(id, forKey: "coachFramework")   // so "Show Example Call" matches
            if showingExample { session = DemoSession.make() }
            else if session.turns.isEmpty { session = SessionStore.fallback }
            if live.listening {
                LiveCoach.shared.setFramework(id)   // live: tell the running engine to re-coach
            }
        }
        .onChange(of: cueMode) { mode in
            if live.listening { LiveCoach.shared.setMode(mode) }
        }
        // No reset on live.listening: it flips seconds after the engine has already written its first
        // session (prep-seeded name, role and coverage), and resetting here discarded exactly that.
        // .clearSession is posted at the right moment by LiveHUD.start() and is the single owner.
        .onReceive(NotificationCenter.default.publisher(for: .clearSession)) { _ in
            SessionStore.showingExample = false
            SessionStore.reviewSelection = nil
            SessionStore.reviewingLatest = false
            SessionStore.showingReady = false
            showingExample = false
            selectedEvidence = nil
            speakerNames = [:]
            sessionEpoch += 1
            session = SessionStore.emptyLive()
            showTranscript = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisStarted)) { _ in SessionStore.reviewingLatest = true; analyzing = true }
        .onReceive(NotificationCenter.default.publisher(for: .showPastCalls)) { _ in showHistory = true }
        .onReceive(NotificationCenter.default.publisher(for: .showRecapReview)) { _ in showRecap = true }
        .onReceive(NotificationCenter.default.publisher(for: .showSpeakingInsights)) { _ in showInsights = true }
        .onReceive(NotificationCenter.default.publisher(for: .reloadSession)) { _ in
            showingExample = SessionStore.showingExample
            let epoch = sessionEpoch
            ReviewView.reloadQueue.async {   // decode off the main thread, one at a time so two
                let loaded: SessionData? = SessionStore.workspace()   // reads cannot land out of order
                DispatchQueue.main.async {
                    guard epoch == sessionEpoch else { return }   // cleared while we were reading
                    if let s = loaded { session = s }   // keep the last good session on a torn read
                    analyzing = false
                }
            }
        }
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.05)
            VStack(spacing: 10) {
                ProgressView()
                Text("Analyzing your call in \(frameworkDisplay)…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(live.listening ? "Live transcript" : session.subtitle).font(.title3.bold())
                    Text("Conversation · \(displayedTurns.count) turns").font(.caption).foregroundStyle(.secondary)
                    if selectedEvidence != nil {
                        Button("Resume following the call") { selectedEvidence = nil; proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    if let notice = session.recoveryNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
                    if let e = live.engineError {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(e).font(.system(size: 12, weight: .medium))
                        }
                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    ForEach(displayedTurns.indices, id: \.self) { i in
                        let t = displayedTurns[i]
                        turnRow(who: t.who, me: isTeamTurn(t), text: t.text, coach: coaching(for: t), attribution: t.speakerStatus, fragments: t.voiceFragments)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedEvidence.map { t.text.contains($0) } == true ? SalesPilotStyle.accent.opacity(0.14) : (isTeamTurn(t) ? Color.clear : Color(nsColor: .controlBackgroundColor)), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isTeamTurn(t) ? Color.clear : SalesPilotStyle.accent.opacity(0.10)))
                            .id("turn-\(i)")
                    }

                    // In-progress lines (committed solid + provisional grey), per speaker
                    if !live.youCommitted.isEmpty || !live.youProvisional.isEmpty {
                        liveRow(who: live.whoByText[SpeakerLookup.microphoneKey] ?? "You", me: true, committed: live.youCommitted, provisional: live.youProvisional)
                    }
                    if !live.custCommitted.isEmpty || !live.custProvisional.isEmpty {
                        liveRow(who: "Call audio",
                                me: false, committed: live.custCommitted, provisional: live.custProvisional)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { if let quote = selectedEvidence, let i = displayedTurns.firstIndex(where: { $0.text.contains(quote) }) { proxy.scrollTo("turn-\(i)", anchor: .center) } }
            .onChange(of: selectedEvidence) { quote in
                if let quote, let i = displayedTurns.firstIndex(where: { $0.text.contains(quote) }) { withAnimation { proxy.scrollTo("turn-\(i)", anchor: .center) } }
            }
            .onChange(of: live.turns.count) { _ in if selectedEvidence == nil { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            .onChange(of: live.custProvisional) { _ in if selectedEvidence == nil { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: live.youProvisional) { _ in if selectedEvidence == nil { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    private func isTeamTurn(_ turn: TurnData) -> Bool {
        if turn.side == "customer" { return false }
        if turn.side == "seller" { return true }
        if let side = session.roster?.first(where: { $0.name == turn.who })?.side { return side == "seller" }
        return turn.me
    }

    private func coveragePanel(_ item: CovData) -> some View {
        let detail = session.coverageDetails?.first { $0.name == item.name }
        return VStack(alignment: .leading, spacing: 12) {
            Text(item.name).font(.headline)
            Text(detail?.remaining ?? (session.turns.isEmpty ? "This point has not been discussed yet. Customer evidence will appear here during the call." : "No saved evidence breakdown is available for this older call. Review its transcript.")).font(.callout)
            if let quote = detail?.quote {
                Text(quote).font(.callout).textSelection(.enabled)
                if detail?.speakerUnconfirmed == true { Text("Speaker role unconfirmed").font(.caption).foregroundStyle(.orange) }
                Button("Show in transcript") { selectedEvidence = quote; showTranscript = true; selectedCoverage = nil }
            } else if detail != nil {
                Text("No matching literal customer statement was captured for this point. Review before treating it as established.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(width: 340)
    }

    private func turnRow(who: String, me: Bool, text: String, coach: (target: String, q: String)?, attribution: String? = nil, fragments: [VoiceFragment]? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 52pt fitted "YOU" and "CUSTOMER" and nothing else. Real names arrive now, so the column
            // has to hold one without clipping while staying fixed so every row still lines up.
            Text(who.uppercased()).font(.system(size: 10, weight: .bold))
                .foregroundStyle(me ? Color.accentColor : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if attribution == "ambiguous" || attribution == "mixed" {
                    Label(attribution == "mixed" ? "Overlapping voices" : "Identity needs review", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
                if let fragments = fragments, !fragments.isEmpty {
                    ForEach(Array(fragments.enumerated()), id: \.offset) { _, fragment in
                        VStack(alignment: .leading, spacing: 3) { Text(fragment.who).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(fragment.text).font(.system(size: 14)) }
                    }
                } else { Text(text).font(.system(size: 14)) }
                if let c = coach {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("◇ SUGGESTED FOLLOW-UP · \(c.target)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.accentColor)
                        Text("\u{201C}\(c.q)\u{201D}").font(.system(size: 13))
                    }
                    .padding(10).background(Color.accentColor.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func liveRow(who: String, me: Bool, committed: String, provisional: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 52pt fitted "YOU" and "CUSTOMER" and nothing else. Real names arrive now, so the column
            // has to hold one without clipping while staying fixed so every row still lines up.
            Text(who.uppercased()).font(.system(size: 10, weight: .bold))
                .foregroundStyle(me ? Color.accentColor : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 80, alignment: .leading)
            (Text(committed).foregroundColor(.primary)
             + Text(committed.isEmpty ? "" : " ")
             + Text(provisional).foregroundColor(.secondary))
                .font(.system(size: 14))
        }
    }

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let answer = session.liveAnswer {
                    Button { researchSection = answer.category == "competition" ? "competition" : "answers"; workspaceTab = "research" } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "books.vertical")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(answer.category == "competition" ? (answer.status == "searching" ? "Checking competitive sources" : answer.status == "unverified" ? "Competitive answer needs confirmation" : "Competitive answer ready") : answer.status == "searching" ? "Searching for an answer" : answer.status == "unverified" ? "Answer needs confirmation" : "Answer ready").font(.system(size: 12, weight: .semibold))
                                Text(answer.q).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                                Text(answer.answer).font(.system(size: 13)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                Text(answer.status == "unverified" ? "Needs confirmation · open sources" : "Open answer and sources").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(12).background(SalesPilotStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).foregroundStyle(SalesPilotStyle.accent)
                }
                if live.listening && !live.customerAvailable {
                    Label("Call audio unavailable. Check audio capture before continuing.", systemImage: "waveform.slash")
                        .font(.callout).foregroundStyle(.red)
                }
                if let notice = live.audioNotice {
                    Label(notice, systemImage: "ear.badge.waveform").font(.system(size: 12)).foregroundStyle(.orange)
                }
                if live.listening, let warning = session.audioWarning, !warning.isEmpty, !warning.hasPrefix("Duplicate call audio detected and removed"), !warning.hasPrefix("Possible speakerphone bleed:") {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("NEXT MOVE", systemImage: "sparkle").font(.system(size: 11, weight: .semibold)).foregroundStyle(SalesPilotStyle.accent)
                        Spacer()
                        Text(session.phase == "close" ? "Next steps" : "Discovery")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if live.listening, let progress = session.coachProgress {
                        HStack(spacing: 7) {
                            if ["generating", "searching"].contains(progress.state) { ProgressView().controlSize(.mini) }
                            Text(progress.state == "generating" ? "Generating a follow-up" : progress.state == "searching" ? "Searching docs" : progress.state == "failed" ? "Request failed" : progress.state == "needs_confirmation" ? "Needs confirmation" : progress.state == "ready" ? "Answer ready" : "Listening")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(progress.state == "failed" ? Color.orange : Color.secondary)
                        }
                        Text(progress.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    let openQuestions = (session.customerQuestions ?? []).filter { !["answered", "deferred"].contains($0.status) }
                    if !openQuestions.isEmpty {
                        Button("\(openQuestions.count) unanswered question\(openQuestions.count == 1 ? "" : "s")") { researchSection = openQuestions.allSatisfy { $0.kind == "competition" } ? "competition" : "answers"; workspaceTab = "research" }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(SalesPilotStyle.accent)
                    }
                    if live.listening, session.coachProgress?.state == "failed" {
                        Button("Retry") {
                            if let id = session.coachProgress?.questionId { LiveCoach.shared.retryRequest(id: id) }
                            else { LiveCoach.shared.retryRequest() }
                        }.font(.caption).help("Retry without marking the customer question answered.")
                    }
                    if let cue = session.nextq.first {
                        Text(cue.q).font(.system(size: 19, weight: .medium, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(cue.reason.map { "Why: " + $0 } ?? ("Explore " + cue.tag)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(live.listening ? "Listen for their next thought." : "Ready for your next conversation.")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                        Text(live.listening ? "A suggestion appears when there is something useful to explore." : "Start a call to get contextual questions and sourced answers.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SalesPilotStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SalesPilotStyle.accent.opacity(0.18)))

                if (session.callPurpose ?? callPurpose) == "discovery" { DiscoveryFocusView() }

                CollapsibleSection("Discovery coverage", detail: session.turns.isEmpty ? frameworkDisplay : session.framework, initialExpanded: true) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(session.coverage.indices, id: \.self) { i in
                            let item = session.coverage[i]
                            Button { selectedCoverage = item.name } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.system(size: 12, weight: .medium))
                                    Label(item.status == "done" ? "Covered" : (item.status == "partial" ? "Explore more" : "Open"), systemImage: item.status == "done" ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11)).foregroundStyle(coverageColor(item.status))
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .help("See the customer evidence and what still needs validation.")
                            .popover(isPresented: Binding(get: { selectedCoverage == item.name }, set: { if !$0 { selectedCoverage = nil } })) {
                                coveragePanel(item)
                            }
                        }
                    }.padding(.top, 10)
                }
                if let mentioned = session.mentionedPeople, !mentioned.isEmpty {
                    CollapsibleSection("Mentioned people", detail: "Attendance unconfirmed", initialExpanded: true) {
                        ForEach(mentioned.indices, id: \.self) { i in
                            let person = mentioned[i]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name).font(.system(size: 12, weight: .semibold))
                                Text([person.role, person.organization, person.inferred ? "Inferred from context" : "Role stated on call"].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                Button("Show mention") { selectedEvidence = person.quote; showTranscript = true }.font(.caption)
                            }.padding(.top, 8)
                        }
                    }
                }
                if let speakers = session.speakers, !speakers.isEmpty {
                    CollapsibleSection("Speaker roles") {
                        Text("Tell the coach who is on your team so their words do not count as customer evidence.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(speakers, id: \.clusterId) { speaker in
                            HStack {
                                TextField("Speaker name", text: Binding(get: { speakerNames[speaker.clusterId] ?? speaker.label }, set: { speakerNames[speaker.clusterId] = $0 }))
                                    .font(.system(size: 12)).textFieldStyle(.roundedBorder).frame(minWidth: 100)
                                    .disabled(!live.listening)
                                Button("Save") { LiveCoach.shared.setSpeakerSide(clusterId: speaker.clusterId, side: speaker.side, name: speakerNames[speaker.clusterId] ?? speaker.label) }
                                    .font(.system(size: 11)).disabled(!live.listening || speakerNames[speaker.clusterId] == nil)
                                Spacer()
                                Picker("Role", selection: Binding(get: { speaker.side }, set: { LiveCoach.shared.setSpeakerSide(clusterId: speaker.clusterId, side: $0, name: speakerNames[speaker.clusterId] ?? speaker.label) })) {
                                    Text("Unknown").tag("unknown")
                                    Text("My team").tag("seller")
                                    Text("Presenting").tag("presenter")
                                    Text("Customer").tag("customer")
                                }.labelsHidden().frame(width: 120).disabled(!live.listening)
                            }.padding(.top, 6)
                        }
                    }
                }
                if let recap = session.recap, !recap.isEmpty {
                    CollapsibleSection("Call summary") {
                        Text(recap).font(.system(size: 13)).textSelection(.enabled).padding(.top, 8)
                        if let steps = session.nextSteps {
                            ForEach(steps, id: \.self) { step in Label(step, systemImage: "arrow.right").font(.system(size: 12)).padding(.top, 4) }
                        }
                    }
                }
            }.padding(24)
        }
    }

}

struct CollapsibleSection<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content
    @State private var expanded: Bool
    init(_ title: String, detail: String? = nil, initialExpanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
        _expanded = State(initialValue: initialExpanded)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                    Text(title)
                    Spacer()
                    if let detail { Text(detail).foregroundStyle(.secondary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content }
        }
    }
}

// MARK: - Window presenter
private final class WorkspaceWindow: NSWindow {
    override func miniaturize(_ sender: Any?) {
        if LiveState.shared.listening {
            LiveHUD.shared.showCompact()
        } else {
            super.miniaturize(sender)
        }
    }
}

final class ReviewWindow: NSObject, NSWindowDelegate {
    static let shared = ReviewWindow()
    private var window: NSWindow?
    func verifyHiddenReopen() -> Bool {
        show(activate: false)
        guard let previous = window, !previous.isReleasedWhenClosed,
              previous.styleMask.contains(.miniaturizable), !previous.isVisible else { return false }
        previous.close()
        show(activate: false)
        return window === previous && previous.contentView != nil && !previous.isVisible
    }
    func hideForCompact() { window?.orderOut(nil) }
    func windowDidMiniaturize(_ notification: Notification) {
        if LiveState.shared.listening { LiveHUD.shared.showCompact() }
    }
    func windowWillClose(_ notification: Notification) {
        if LiveState.shared.listening { LiveHUD.shared.showCompact() }
    }
    func show(activate: Bool = true) {
        if window == nil {
            let w = WorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "SalesPilot"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.minSize = NSSize(width: 960, height: 600)
            w.titlebarAppearsTransparent = true
            w.contentView = NSHostingView(rootView: ReviewView())
            w.center()
            window = w
        }
        if activate {
            LiveHUD.shared.hideCompact()
            if window?.isMiniaturized == true { window?.deminiaturize(nil) }
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .reloadSession, object: nil)
        }
    }
}

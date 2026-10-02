import AppKit
import SwiftUI

final class CallConsentWindow {
    static let shared = CallConsentWindow()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "SalesPilot · Before capture"; panel.isReleasedWhenClosed = false; panel.center(); window = panel
        }
        window?.contentView = NSHostingView(rootView: CallConsent())
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func close() { window?.orderOut(nil) }
}
struct CallConsent: View {
    @State private var confirmed = false
    @AppStorage("callPurpose") private var purpose = "standard"
    @AppStorage("callProcessingMode") private var mode = "circuit"
    private var notice: String { mode == "local" ? "I’d like to transcribe this conversation locally on my Mac and use local assistance for notes and follow-up questions. Is everyone comfortable with that?" : "I’d like to use an internal assistant to transcribe this conversation and suggest follow-up questions. Audio is processed on my Mac, and selected transcript text may be processed through Cisco’s AI service. Is everyone comfortable with that?" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("INTERNAL SE ASSISTANT", systemImage: "waveform.path").font(.caption.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
            Text("Notify everyone before capture").font(.title2.weight(.semibold))
            Text(purpose == "discovery" ? "Discovery only · define needs today and a tailored demo as a possible next step." : "Standard discovery · follow the conversation and its next steps.").font(.caption.weight(.medium)).foregroundStyle(SalesPilotStyle.accent)
            Text("Use the customer-approved wording and your organization’s recording rules. Capture has not started.").font(.callout).foregroundStyle(.secondary)
            Picker("Live processing", selection: $mode) { Text("Cisco + docs").tag("circuit"); Text("Local only").tag("local") }.pickerStyle(.segmented).onChange(of: mode) { _ in confirmed = false }
            Text(notice).font(.system(size: 15)).padding(16).background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            Button("Copy suggested notice") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(notice, forType: .string) }
            Text("Names and voice groups are assigned within this call. Transcripts, notes and recaps are stored locally; generated suggestions need your review. No email or CRM update is sent automatically. Masking reduces known contact details; it is not a complete sensitive-data detector.").font(.caption).foregroundStyle(.secondary)
            Toggle("I have notified all participants and confirmed the required consent and authorization for this call.", isOn: $confirmed).font(.callout)
            Spacer(minLength: 0)
            HStack { Button("Cancel") { CallConsentWindow.shared.close() }; Spacer(); Button("Start with consent confirmed") { CallConsentWindow.shared.close(); LiveHUD.shared.start(consentConfirmed: true) }.buttonStyle(.borderedProminent).tint(SalesPilotStyle.buttonFill).disabled(!confirmed) }
        }.padding(26).frame(width: 630, height: 600).background(Color(nsColor: .windowBackgroundColor))
    }
}

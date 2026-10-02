import SwiftUI

struct CallModeChoices: View {
    @AppStorage("callPurpose") private var purpose = "standard"
    var canChange = true
    private func choice(_ id: String, _ title: String, _ icon: String, _ description: String, _ example: String) -> some View {
        Button { purpose = id } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: icon).font(.headline)
                    Spacer()
                    Image(systemName: purpose == id ? "checkmark.circle.fill" : "circle").foregroundStyle(SalesPilotStyle.accent)
                }
                Text(description).font(.callout).foregroundStyle(.secondary)
                Text(example).font(.callout.weight(.medium))
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(SalesPilotStyle.accent.opacity(purpose == id ? 0.09 : 0.025), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SalesPilotStyle.accent.opacity(purpose == id ? 0.6 : 0.15), lineWidth: 1))
        }.buttonStyle(.plain).disabled(!canChange)
            .accessibilityLabel("\(title). \(description). \(purpose == id ? "Selected" : "Select mode")")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            choice("standard", "Flexible conversation", "bubble.left.and.bubble.right", "Follow the customer's needs across discovery, technical discussion and demo-related next steps. No discovery-only boundary.", "Use for: a mixed agenda or a conversation that may include a demo.")
            choice("discovery", "Discovery first", "scope", "Keep this meeting focused on workflows, challenges and impact. Redirect requests for a demo today toward a tailored follow-up demo.", "Say next: Let's understand your workflow today so we can tailor a useful demo for our next conversation.")
            Text("Both modes provide notes, methodology coverage and technical or competitive answers. Choose before starting a call; your choice is saved for future calls.").font(.caption).foregroundStyle(.secondary)
            if !canChange { Text("End the active call before changing its mode.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct CallModeSettings: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("SALESPILOT / CALL MODE", systemImage: "scope").font(.caption.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
            Text("How do you want to lead the call?").font(.title2.bold())
            CallModeChoices()
            HStack { Text("Reopen through More → Call mode").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(SalesPilotStyle.buttonFill) }
        }.padding(28).frame(width: 620)
    }
}

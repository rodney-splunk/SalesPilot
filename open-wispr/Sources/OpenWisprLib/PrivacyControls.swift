import AppKit
import Foundation
import Security
import SwiftUI

public enum ProviderCredentials {
    private static let sessionCache = SessionCredentialCache()
    static var isConfigured: Bool {
        guard let data = try? Data(contentsOf: WorkspacePaths.engine.appendingPathComponent(".circuit.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return config["credential_store"] as? String == "macos-keychain"
    }
    static func data(refresh: Bool = false) throws -> Data {
        try sessionCache.read(refresh: refresh) { try readKeychain() }
    }
    private static func readKeychain() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.salespilot.circuit", kSecAttrAccount as String: "credentials", kSecReturnData as String: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              value["client_secret"] != nil, value["app_key"] != nil else {
            throw NSError(domain: "SalesPilotCredential", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Cisco credentials are unavailable. Check SalesPilot access in macOS Keychain."])
        }
        return data
    }
    // Private subprocess IPC. Caller captures stdout; never invoke in a logging terminal.
    public static func writeToPrivatePipe() {
        do { FileHandle.standardOutput.write(try data()) }
        catch { fputs("Cisco Keychain access unavailable.\n", stderr); exit(1) }
    }
}

struct PrivacyControls: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var live = LiveState.shared
    @AppStorage("callProcessingMode") private var mode = "circuit"
    @State private var policy = RetentionPolicy.load()
    @State private var days = ""
    @State private var files: [URL] = []
    @State private var status: String?
    @State private var checking = false
    private var history: URL { SessionCapture.sessionsDir.appendingPathComponent("history") }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Privacy & local data").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                Text("LIVE CALL PROCESSING").font(.caption.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
                Picker("Processing", selection: $mode) { Text("Cisco CIRCUIT + official docs").tag("circuit"); Text("Local only").tag("local") }.pickerStyle(.segmented).disabled(live.listening || live.starting || live.finishing)
                Text(mode == "local" ? "Call text stays in local inference and references. Hosted AI, public doc queries and pricing-page retrieval are blocked. An installed local model is required. Explicit account preparation lookups are a separate action." : "Audio transcription stays on the Mac. Selected masked text may go to Cisco; product questions may query public documentation. Use only approved data and obtain required consent.").font(.callout).foregroundStyle(.secondary)
                Text("The selection applies at the next call start. A processing choice is not Cisco policy approval.").font(.caption).foregroundStyle(.secondary)
                Button(checking ? "Checking Keychain…" : "Check Cisco credential access") {
                    checking = true
                    DispatchQueue.global().async {
                        let ok = (try? ProviderCredentials.data(refresh: true)) != nil
                        DispatchQueue.main.async { checking = false; status = ok ? "SalesPilot can access its Cisco credentials in Keychain." : "Access unavailable. Allow only SalesPilot for its app-specific item in Keychain; do not allow all applications." }
                    }
                }.disabled(checking)
                Divider()
                Text("LOCAL STORAGE").font(.caption.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
                Text(SessionCapture.sessionsDir.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("Files remain readable by your account. FileVault, approved backup/sync exclusions and Cisco retention rules are still required. Exported inventories contain filenames; choose an approved location.").font(.callout).foregroundStyle(.secondary)
                HStack { Button("Review local files") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: SessionCapture.sessionsDir.path) }; Button("Export data inventory") { exportInventory() } }
                Divider()
                Text("RETENTION REVIEW & LEGAL HOLDS").font(.caption.weight(.semibold)).foregroundStyle(SalesPilotStyle.accent)
                Text("Record the approved policy, then review calls beyond that age. This screen does not automatically delete calls or invent a retention period. Holds exclude a call from the review list.").font(.callout).foregroundStyle(.secondary)
                HStack { TextField("Approved days", text: $days).frame(width: 130); TextField("Policy reference / owner", text: $policy.reference) }
                Button("Save retention review policy") {
                    guard let value = Int(days), value > 0, !policy.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Enter positive days and the approved policy reference. No policy was changed."; return }
                    policy.days = value; policy.reviewedAt = ISO8601DateFormatter().string(from: Date()); savePolicy()
                }
                ForEach(files, id: \.path) { file in
                    let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    HStack { VStack(alignment: .leading) { Text(file.deletingPathExtension().lastPathComponent).font(.caption); Text(policy.needsReview(file: file, modified: date) ? "Beyond policy age · review" : policy.holds.contains(file.lastPathComponent) ? "On hold · retained" : "Retained").font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("Hold", isOn: Binding(get: { policy.holds.contains(file.lastPathComponent) }, set: { held in policy.holds.removeAll { $0 == file.lastPathComponent }; if held { policy.holds.append(file.lastPathComponent) }; savePolicy() })).toggleStyle(.checkbox).fixedSize() }
                }
                Text("Internal SE assistant · suggestions require human review · no automatic email, Slack or Salesforce writes.").font(.caption).foregroundStyle(.secondary)
            } }
            if let status { Text(status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(24).frame(width: 720, height: 700).background(Color(nsColor: .windowBackgroundColor)).onAppear { days = policy.days > 0 ? String(policy.days) : ""; files = ((try? FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent } }
    }
    private func savePolicy() { do { try policy.save(); status = "Review policy saved locally. No call was deleted."; ComplianceAudit.record("retention-review-policy-updated") } catch { status = "Could not save the policy." } }
    private func exportInventory() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SalesPilot-data-inventory.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enumerator = FileManager.default.enumerator(at: SessionCapture.sessionsDir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            let rows = (enumerator?.allObjects as? [URL] ?? []).compactMap { file -> [String: Any]? in
                guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]), info.isRegularFile == true, info.isSymbolicLink != true else { return nil }
                return ["file": file.path.replacingOccurrences(of: SessionCapture.sessionsDir.path + "/", with: ""), "bytes": info.fileSize ?? 0, "modifiedAt": info.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "", "held": policy.holds.contains(file.lastPathComponent)]
            }
            let data = try JSONSerialization.data(withJSONObject: ["scope": "Local file metadata; no transcript contents or credentials", "files": rows], options: [.prettyPrinted, .sortedKeys]); try data.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); status = "Inventory saved. No call content was exported."; ComplianceAudit.record("data-inventory-exported")
        } catch { status = "Could not export the inventory." }
    }
}

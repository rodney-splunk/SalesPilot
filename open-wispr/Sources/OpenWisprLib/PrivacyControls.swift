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
    static func data(refresh: Bool = false, allowInteraction: Bool = false) throws -> Data {
        try sessionCache.read(refresh: refresh) { try readKeychain(allowInteraction: allowInteraction) }
    }
    private static func readKeychain(allowInteraction: Bool) throws -> Data {
        // The legacy login keychain does not consistently honor per-query UI flags.
        // Scope the process interaction policy to this serialized credential read.
        var wasAllowed: DarwinBoolean = false
        SecKeychainGetUserInteractionAllowed(&wasAllowed)
        SecKeychainSetUserInteractionAllowed(allowInteraction)
        defer { SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.salespilot.circuit", kSecAttrAccount as String: "credentials", kSecReturnData as String: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess, !allowInteraction,
           ProcessInfo.processInfo.environment["SALESPILOT_DISABLE_CREDENTIAL_HELPER"] != "1",
           let preserved = try? stableCredentialData() { item = preserved as CFData }
        guard let data = item as? Data,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              value["client_secret"] != nil, value["app_key"] != nil else {
            throw NSError(domain: "SalesPilotCredential", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Cisco credentials are unavailable. Use Connect Cisco in Privacy & local data; automatic calls never request a password."])
        }
        return data
    }
    private static func stableCredentialData() throws -> Data {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CredentialAccess.app")
        var ownCode: SecStaticCode?, requirement: SecRequirement?, helperCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &ownCode) == errSecSuccess, let ownCode,
              SecCodeCopyDesignatedRequirement(ownCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(helper as CFURL, [], &helperCode) == errSecSuccess,
              let helperCode,
              SecStaticCodeCheckValidity(helperCode, [], requirement) == errSecSuccess
        else { throw NSError(domain: "SalesPilotCredentialHelper", code: 1) }
        let process = Process(), output = Pipe()
        process.executableURL = helper.appendingPathComponent("Contents/MacOS/SalesPilot")
        process.arguments = ["provider-credentials"]
        var environment = ProcessInfo.processInfo.environment
        environment["SALESPILOT_DISABLE_CREDENTIAL_HELPER"] = "1"
        environment["SALESPILOT_ROOT"] = WorkspacePaths.root.path
        process.environment = environment; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 65536 else { throw NSError(domain: "SalesPilotCredentialHelper", code: 2) }
        return data
    }
    /// Rebind only this app-specific item to the calling signed app. Never trust all apps.
    /// Explicit user action only: macOS may require one authorization to update the ACL.
    static func connect() throws -> Data {
        let data = try self.data(refresh: true, allowInteraction: true)
        var access: SecAccess?
        let created = SecAccessCreate("SalesPilot Cisco credentials" as CFString, nil, &access)
        guard created == errSecSuccess, let access else { throw NSError(domain: "SalesPilotCredentialAccess", code: Int(created)) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.salespilot.circuit", kSecAttrAccount as String: "credentials"]
        let result = SecItemUpdate(query as CFDictionary, [kSecAttrAccess as String: access] as CFDictionary)
        guard result == errSecSuccess else { throw NSError(domain: "SalesPilotCredentialAccess", code: Int(result)) }
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
                Button(checking ? "Connecting…" : "Connect Cisco / repair saved access") {
                    checking = true
                    DispatchQueue.global().async {
                        let ok = (try? ProviderCredentials.connect()) != nil
                        DispatchQueue.main.async { checking = false; status = ok ? "Cisco connected. Saved access is restricted to SalesPilot; automatic calls do not open password dialogs." : "Could not connect. Unlock the login keychain and retry this explicit action. No automatic password requests will be made." }
                    }
                }.disabled(checking || live.listening || live.starting || live.finishing)
                Text("Only this Connect action can request macOS authorization. It repairs access for SalesPilot’s own Cisco item; credentials remain in Keychain.").font(.caption).foregroundStyle(.secondary)
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

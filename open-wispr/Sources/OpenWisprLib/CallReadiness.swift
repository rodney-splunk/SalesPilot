import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

struct ReadinessCheck: Identifiable, Decodable {
    let id: String
    let state: String
    let detail: String
    var title: String { ["microphone": "Microphone permission", "device": "Audio input", "capture": "Customer audio permission", "transcription": "Transcription", "coaching": "Coaching provider", "documentation": "Official documentation", "voices": "Speaker separation", "references": "Local references"][id] ?? id }
}
struct ReadinessReport: Decodable { let checks: [ReadinessCheck] }

final class CallReadinessModel: ObservableObject {
    @Published var checks: [ReadinessCheck] = []
    @Published var busy = false
    @Published var checkedAt: Date?
    func refresh(online: Bool = false) {
        guard !busy else { return }
        busy = true
        let cfg = Config.load()
        let devices = AudioDeviceManager.listInputDevices()
        var local: [ReadinessCheck] = []
        let authorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        local.append(.init(id: "microphone", state: authorized ? "available" : "unavailable", detail: authorized ? "Permission granted." : "Allow SalesPilot in System Settings → Privacy & Security → Microphone."))
        let configured = cfg.audioInputDeviceUID.map { uid in devices.first { $0.uid == uid } } ?? cfg.audioInputDeviceID.flatMap { id in devices.first { $0.id == id } }
        let selected = configured ?? devices.first { $0.isDefault }
        let missing = (cfg.audioInputDeviceUID != nil || cfg.audioInputDeviceID != nil) && configured == nil
        local.append(.init(id: "device", state: selected == nil ? "unavailable" : missing ? "review" : "available", detail: selected.map { missing ? "Saved input disconnected. Current default is \($0.name); review it before joining." : "Selected input: \($0.name). No device changes were made." } ?? "No microphone input found."))
        if #available(macOS 14.4, *) {
            local.append(.init(id: "capture", state: "configured", detail: "Customer audio uses a local Core Audio process tap. Audio-recording authorization and received audio are verified at call start; this check does not start capture."))
        } else {
            local.append(.init(id: "capture", state: "unavailable", detail: "Customer audio capture requires macOS 14.4 or newer."))
        }
        let live = ["small.en", "base.en", cfg.modelSize].first { Transcriber.modelExists(modelSize: $0) }
        local.append(.init(id: "transcription", state: live != nil && Transcriber.findWhisperBinary() != nil ? "available" : "unavailable", detail: live.map { "Local transcription model: \($0)." } ?? "No transcription model found. Install a model before starting."))
        checks = local
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            var remote: [ReadinessCheck] = []
            if let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                process.executableURL = URL(fileURLWithPath: node)
                process.arguments = [WorkspacePaths.engine.appendingPathComponent("readiness.mjs").path] + (online ? ["--online"] : [])
                var environment = ProcessInfo.processInfo.environment
                environment["SALESPILOT_CREDENTIAL_READER"] = Bundle.main.executableURL?.path
                environment["SALESPILOT_CREDENTIAL_INPUT"] = "stdin"
                if UserDefaults.standard.string(forKey: "callProcessingMode") == "local" { environment["SALESPILOT_LOCAL_ONLY"] = "1" }
                process.environment = environment
                let input = Pipe(); process.standardInput = input
                let credentials: Any = online && environment["SALESPILOT_LOCAL_ONLY"] != "1" && ProviderCredentials.isConfigured ? ((try? ProviderCredentials.data()).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]) : [:]
                let bootstrap = try? JSONSerialization.data(withJSONObject: ["cmd": "provider-credentials", "credentials": credentials])
                let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                do { try process.run(); if let bootstrap { try input.fileHandleForWriting.write(contentsOf: bootstrap + Data([10])) }; try input.fileHandleForWriting.close(); let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }; DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: deadline); defer { deadline.cancel() }; let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); remote = (try? JSONDecoder().decode(ReadinessReport.self, from: data))?.checks ?? [] } catch {}
            }
            if remote.isEmpty { remote = [.init(id: "coaching", state: "unavailable", detail: "Could not check the local engine. Transcript capture and coaching readiness are separate.")] }
            DispatchQueue.main.async { self.checks = local + remote; self.busy = false; self.checkedAt = Date() }
        }
    }
}
struct CallReadiness: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CallReadinessModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Before you join").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Text("Check capture, models and sources without starting a call. Configured means installed; Available means this check succeeded.").font(.callout).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(model.checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.state == "available" ? "checkmark.circle.fill" : check.state == "unavailable" ? "exclamationmark.circle" : "info.circle").foregroundStyle(check.state == "available" ? Color.green : check.state == "unavailable" ? Color.orange : SalesPilotStyle.accent)
                    VStack(alignment: .leading, spacing: 4) { Text(check.title).font(.headline); Text(check.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Spacer(); Text(check.state.capitalized).font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(SalesPilotStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            } } }
            HStack { Button(model.busy ? "Checking…" : "Check connections") { model.refresh(online: true) }.disabled(model.busy); Button("Refresh local checks") { model.refresh() }.disabled(model.busy); Spacer(); if let date = model.checkedAt { Text(date, style: .time).font(.caption).foregroundStyle(.secondary) } }
        }.padding(24).frame(width: 680, height: 640).background(Color(nsColor: .windowBackgroundColor)).onAppear { model.refresh() }
    }
}

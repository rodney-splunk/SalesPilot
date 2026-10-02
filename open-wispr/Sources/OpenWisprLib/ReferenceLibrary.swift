import AppKit
import SwiftUI

struct ReferenceLibrary: View {
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var status: String? = nil
    @State private var importing = false
    private var directory: URL { SessionCapture.sessionsDir.appendingPathComponent("docs", isDirectory: true) }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge library").font(.title2.weight(.semibold))
                    Text("Add product guides, approved FAQs and technical references. Live answers also search official Splunk documentation.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            if files.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Official sources work without an upload", systemImage: "books.vertical").font(.headline)
                    Text("Add approved FAQs, product notes, or technical guides for your team. Customer questions and sourced answers appear in the Answers section during a call. Details that cannot be verified stay marked for follow-up.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SalesPilotStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            } else {
                List(files, id: \.path) { file in Label(file.lastPathComponent, systemImage: "doc.text").font(.callout) }
                    .frame(height: 220)
            }
            if let status = status { Text(status).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button(importing ? "Adding references…" : "Add documents") { chooseFiles() }
                    .buttonStyle(.borderedProminent).disabled(importing)
                if !files.isEmpty {
                    Button("Refresh search") { indexReferences() }.disabled(importing)
                }
                Text("PDF, Word, text, or Markdown").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(26) }.frame(width: 680, height: 460).background(Color(nsColor: .windowBackgroundColor)).onAppear { reload() }
    }
    private func reload() {
        files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["pdf", "docx", "txt", "md", "markdown"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["pdf", "docx", "txt", "md", "markdown"]
        guard panel.runModal() == .OK else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for source in panel.urls {
                var destination = directory.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    destination = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString.prefix(6) + "." + source.pathExtension)
                }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            reload()
            indexReferences()
        } catch { status = "Could not add a document: \(error.localizedDescription)" }
    }
    private func indexReferences() {
        importing = true
        status = "Preparing your references for search…"
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                DispatchQueue.main.async { importing = false; status = "Documents were saved. Search preparation is unavailable." }
                return
            }
            process.executableURL = URL(fileURLWithPath: node)
            process.arguments = [WorkspacePaths.engine.appendingPathComponent("rag.mjs").path, "index", "--json"]
            process.currentDirectoryURL = WorkspacePaths.engine
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                // Read while the child runs so a long skipped-file report cannot fill its pipe.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let skipped = report?["skipped"] as? [String] ?? []
                let readable = report?["readableFiles"] as? Int ?? 0
                DispatchQueue.main.async {
                    importing = false
                    if !skipped.isEmpty {
                        status = "Could not read: " + skipped.joined(separator: ", ") + ". Empty or scanned documents may need a text version. " + (readable > 0 ? "\(readable) readable references are ready." : "No references are ready yet.")
                    } else {
                        status = process.terminationStatus == 0 ? "Your knowledge library is ready. New questions will use it." : "Documents were saved, but search preparation failed. Use Refresh search to retry."
                    }
                }
            } catch {
                DispatchQueue.main.async { importing = false; status = "Documents were saved. Search preparation is unavailable." }
            }
        }
    }
}

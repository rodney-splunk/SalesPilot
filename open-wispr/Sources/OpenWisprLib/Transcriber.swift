import Foundation

public class Transcriber {
    private let createdAt = Date()
    private let modelSize: String
    private let language: String
    private let whisperPrompt: String?
    private let threads: Int?
    private let beamSize: Int?   // nil = greedy (fast, for the live scroll); 5 = beam search (accurate, for the final turn)
    public var spokenPunctuation: Bool = false

    /// Domain vocabulary hint for sales/security calls. Measured effect: "legacy sim" -> "legacy SIEM",
    /// "SOC to audit" -> "SOC 2 audit", "mistreat our flaws" -> "mistriage SLAs". Config's
    /// `whisperPrompt`, when set, replaces this.
    /// Kept deliberately SHORT. whisper takes this as prior context, and a longer list dilutes the
    /// bias rather than adding to it: measured across two clips, a 516-char list lost MEDDPICC that a
    /// 200-char list gets right. Every term here earns its place; adding more is a regression risk,
    /// so re-measure with `SalesPilot dictate <wav>` before extending it.
    public static let salesVocabulary =
        "Splunk, MEDDPICC, SPIN, Challenger, APM, SOAR, ITSI, SIEM, SOC 2, SLA, SLAs, MTTR, PII, "
        + "Edge Processor, Enterprise Security, risk-based alerting, correlation search, "
        + "observability, Cisco, POC, renewal."

    /// Names expected on this call, pulled from call prep. Uncommon proper nouns are exactly what
    /// whisper has no prior for: measured on degraded audio, "Nilanjana Nair" came back as "Island
    /// Cheninare" and "island generator" unprimed, and correctly every time once the name was in the
    /// prompt. Supports an explicit "Attendees: A, B" line, else picks capitalised name-like pairs.
    public static func attendeeNames(fromPrep prep: String) -> [String] {
        NameHints.names(from: prep)
    }

    public init(modelSize: String = "base.en", language: String = "en", whisperPrompt: String? = nil, threads: Int? = nil, beamSize: Int? = 5) {
        self.modelSize = modelSize
        self.language = language
        self.whisperPrompt = whisperPrompt
        self.threads = threads
        self.beamSize = beamSize
    }

    func transcribeDetailed(audioURL: URL) throws -> (String, [TimedWord]) {
        if let model = Transcriber.findModel(modelSize: modelSize),
           let url = WhisperServerPool.shared.inferenceURL(forModelPath: model, threads: threads ?? 4),
           let raw = try? Transcriber.postInference(url: url, audioURL: audioURL, prompt: effectiveWhisperPrompt, format: "verbose_json"),
           let data = raw.data(using: .utf8), let result = try? JSONDecoder().decode(TimedTranscript.self, from: data) {
            return (Transcriber.stripWhisperMarkers(result.text), result.segments.flatMap { $0.words ?? [] }.filter { $0.valid })
        }
        return (try transcribe(audioURL: audioURL), [])
    }

    public func transcribe(audioURL: URL) throws -> String {
        guard let modelPath = Transcriber.findModel(modelSize: modelSize) else {
            throw TranscriberError.modelNotFound(modelSize)
        }

        // Fast path: a resident whisper-server (no per-call model reload). Falls back to whisper-cli
        // below until the server is ready, or if whisper-server isn't installed.
        if let url = WhisperServerPool.shared.inferenceURL(forModelPath: modelPath, threads: threads ?? 4),
           let text = try? Transcriber.postInference(url: url, audioURL: audioURL, prompt: effectiveWhisperPrompt) {
            return Transcriber.stripWhisperMarkers(text)
        }

        guard let whisperPath = Transcriber.findWhisperBinary() else {
            throw TranscriberError.whisperNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = arguments(modelPath: modelPath, audioURL: audioURL)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: deadline)
        defer { deadline.cancel() }

        var stderrData = Data()
        let stderrThread = Thread {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        stderrThread.start()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        while !stderrThread.isFinished { Thread.sleep(forTimeInterval: 0.01) }
        process.waitUntilExit()

        let output = Transcriber.stripWhisperMarkers(
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderr.isEmpty { fputs("whisper-cpp: \(stderr)\n", Foundation.stderr) }
            throw TranscriberError.transcriptionFailed
        }

        return output
    }

    /// POST audio to a whisper-server /inference endpoint (multipart), returning the plain-text result.
    static func postInference(url: URL, audioURL: URL, prompt: String? = nil, format: String = "text") throws -> String {
        let boundary = "owb-\(UUID().uuidString)"
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 30
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("temperature", "0")
        field("response_format", format)
        if format == "verbose_json" { field("token_timestamps", "true") }
        // Domain vocabulary hint — turns "legacy sim"/"SOC to audit" into "legacy SIEM"/"SOC 2 audit".
        if let p = prompt, !p.isEmpty { field("prompt", p) }
        let fileData = try Data(contentsOf: audioURL)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let sem = DispatchSemaphore(value: 0)
        var out = ""; var failed = false
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            if err != nil { failed = true }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 { failed = true }
            if let d = data, let s = String(data: d, encoding: .utf8) { out = s }
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 30) == .timedOut { task.cancel(); throw TranscriberError.transcriptionFailed }
        if failed { throw TranscriberError.transcriptionFailed }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func arguments(modelPath: String, audioURL: URL) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", language,
            "--no-timestamps",
            "-nt",
        ]
        if let bs = beamSize { args += ["-bs", String(bs)] }   // beam search on the accurate pass; greedy on the fast live scroll
        if let threads = threads {
            args += ["-t", String(threads)]
        }
        if let prompt = effectiveWhisperPrompt {
            args += ["--prompt", prompt]
        }
        if spokenPunctuation {
            args += ["--suppress-regex", "[,\\.\\?!;:\\-—]"]
        }

        return args
    }

    private var effectiveWhisperPrompt: String? {
        var prompt = whisperPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sessionURL = WorkspacePaths.session
        if let attributes = try? FileManager.default.attributesOfItem(atPath: sessionURL.path),
           let updated = attributes[.modificationDate] as? Date, updated >= createdAt,
           let data = try? Data(contentsOf: sessionURL),
           let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let names = NameHints.callNames(session)
            if !names.isEmpty { prompt += " On this call: " + names.joined(separator: ", ") + "." }
        }
        return prompt.isEmpty ? nil : prompt
    }

    private static let knownMarkers: Set<String> = [
        "BLANK_AUDIO", "blank_audio",
        "Music", "MUSIC", "music",
        "Applause", "APPLAUSE", "applause",
        "Laughter", "LAUGHTER", "laughter",
        "silence", "Silence", "SILENCE",
        "SOUND", "Sound", "sound",
        "NOISE", "Noise", "noise",
        "INAUDIBLE", "inaudible",
    ]

    private static let markerRegex = try! NSRegularExpression(
        pattern: "[\\[\\(]\\s*([^\\]\\)]+?)\\s*[\\]\\)]"
    )

    public static func stripWhisperMarkers(_ text: String) -> String {
        let nsText = text as NSString
        let matches = markerRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var result = text
        for match in matches.reversed() {
            let innerRange = match.range(at: 1)
            let inner = nsText.substring(with: innerRange)
            if knownMarkers.contains(inner) {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: "")
            }
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func findWhisperBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        for name in ["whisper-cli", "whisper-cpp"] {
            let which = Process()
            which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            which.arguments = [name]
            let pipe = Pipe()
            which.standardOutput = pipe
            which.standardError = Pipe()
            try? which.run()
            which.waitUntilExit()

            let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let result = result, !result.isEmpty {
                return result
            }
        }

        return nil
    }

    public static func modelExists(modelSize: String) -> Bool {
        return findModel(modelSize: modelSize) != nil
    }

    static func findModel(modelSize: String) -> String? {
        let modelFileName = "ggml-\(modelSize).bin"

        let candidates = [
            "\(Config.configDir.path)/models/\(modelFileName)",
            "/opt/homebrew/share/whisper-cpp/models/\(modelFileName)",
            "/usr/local/share/whisper-cpp/models/\(modelFileName)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cache/whisper/\(modelFileName)",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }
}

enum TranscriberError: LocalizedError {
    case whisperNotFound
    case modelNotFound(String)
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper-cpp not found. Install it with: brew install whisper-cpp"
        case .modelNotFound(let size):
            return "Whisper model '\(size)' not found. Download it with: open-wispr download-model \(size)"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}

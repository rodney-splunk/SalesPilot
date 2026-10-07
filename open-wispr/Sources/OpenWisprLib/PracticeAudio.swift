import AVFoundation
import Foundation

/// One voice-processed engine supplies both the microphone and the playback reference.
/// Queue ownership keeps file writes and endpoint state away from the audio render thread.
final class PracticeAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let voice = AVAudioPlayerNode()
    private let silentInput = AVAudioMixerNode()
    private(set) var startupStage = "voice processing"
    private let queue = DispatchQueue(label: "SalesPilot.practice.audio")
    private var gate = PracticeTurnGate()
    private var enabled = true
    private var playing = false
    private var stopped = false
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollDuration = 0.0
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var startedAt = 0.0
    private var playbackID = UUID()
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    private let root: URL
    private let began: @Sendable () -> Void
    private let ended: @Sendable (URL, Double, Double) -> Void
    private let failed: @Sendable () -> Void
    private let level: @Sendable (Double) -> Void
    private var meterElapsed = 0.0
    private var diagnosticElapsed = 0.0
    private var bufferCount = 0
    private var maximumDB = -120.0
    private var detectedTurns = 0
    init(root: URL, began: @escaping @Sendable () -> Void, ended: @escaping @Sendable (URL, Double, Double) -> Void, failed: @escaping @Sendable () -> Void, level: @escaping @Sendable (Double) -> Void) {
        self.root = root; self.began = began; self.ended = ended; self.failed = failed; self.level = level
    }
    func start() throws {
        try engine.inputNode.setVoiceProcessingEnabled(true)
        guard engine.inputNode.isVoiceProcessingEnabled else { throw NSError(domain: "PracticeEcho", code: 1) }
        startupStage = "audio graph"
        let deviceFormat = engine.inputNode.outputFormat(forBus: 0)
        guard deviceFormat.sampleRate > 0, deviceFormat.channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: deviceFormat.sampleRate, channels: 1)
        else { throw NSError(domain: "PracticeInput", code: 1) }
        engine.attach(voice); engine.attach(silentInput)
        silentInput.outputVolume = 0
        // VoiceProcessingIO requires matching client input/output formats. Keep the I/O
        // graph at microphone rate with a mono client format. Do not average a
        // device's extra input channels into the speech sent to transcription.
        engine.connect(engine.inputNode, to: silentInput, format: format)
        engine.connect(silentInput, to: engine.mainMixerNode, format: format)
        engine.connect(voice, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength), let src = buffer.floatChannelData, let dst = copy.floatChannelData else { return }
            copy.frameLength = buffer.frameLength
            for channel in 0..<Int(buffer.format.channelCount) { dst[channel].update(from: src[channel], count: Int(buffer.frameLength)) }
            self.queue.async { self.consume(copy) }
        }
        tapInstalled = true
        startupStage = "engine start"
        engine.prepare(); try engine.start()
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.failed() }
    }
    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard enabled, !stopped, let samples = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        // Meter every channel: voice-processed and multichannel devices can put
        // useful microphone data outside channel zero.
        var energy = 0.0
        for channel in 0..<Int(buffer.format.channelCount) {
            var channelEnergy = 0.0
            for i in 0..<Int(buffer.frameLength) { channelEnergy += Double(samples[channel][i] * samples[channel][i]) }
            energy = max(energy, channelEnergy)
        }
        let db = 10 * log10(max(1e-12, energy / Double(buffer.frameLength)))
        bufferCount += 1; maximumDB = max(maximumDB, db)
        meterElapsed += duration; diagnosticElapsed += duration
        if meterElapsed >= 0.10 { meterElapsed = 0; level(db) }
        if diagnosticElapsed >= 5 {
            diagnosticElapsed = 0
            // Aggregate signal levels only; never raw audio, text, names or credentials.
            let data: [String: Any] = ["buffers": bufferCount, "maximumDB": maximumDB, "detectedTurns": detectedTurns, "sampleRate": buffer.format.sampleRate, "channels": buffer.format.channelCount]
            if let encoded = try? JSONSerialization.data(withJSONObject: data) { try? encoded.write(to: root.appendingPathComponent("microphone-health.json"), options: .atomic) }
        }
        let wasSpeaking = gate.speaking
        let event = gate.ingest(db: db, duration: duration, playback: playing)
        do {
            if !wasSpeaking {
                preRoll.append(buffer); preRollDuration += duration
                while preRollDuration > 0.5, preRoll.count > 1 { preRollDuration -= Double(preRoll.removeFirst().frameLength) / buffer.format.sampleRate }
            }
            if event == .began {
                detectedTurns += 1
                let url = root.appendingPathComponent(UUID().uuidString + ".caf")
                fileURL = url; file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                startedAt = Date().timeIntervalSince1970 - preRollDuration
                for chunk in preRoll { try file?.write(from: chunk) }
                preRoll = []; preRollDuration = 0; began()
            } else if wasSpeaking { try file?.write(from: buffer) }
            if event == .ended, let url = fileURL {
                file = nil; fileURL = nil; ended(url, startedAt, Date().timeIntervalSince1970)
            }
        } catch { discard(); enabled = false; failed() }
    }
    func setMuted(_ muted: Bool) { queue.sync { enabled = !muted; discard() } }
    private func discard() {
        file = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil; preRoll = []; preRollDuration = 0; gate.reset()
    }
    func play(_ url: URL) throws -> UUID {
        let audio = try AVAudioFile(forReading: url)
        let id = UUID()
        queue.sync { playbackID = id; playing = true }
        voice.scheduleFile(audio, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.queue.async { if self.playbackID == id { self.playing = false } }
        }
        voice.play(); return id
    }
    func isPlaying(_ id: UUID) -> Bool { queue.sync { playing && playbackID == id && !stopped } }
    func interrupt() { voice.stop(); queue.sync { playbackID = UUID(); playing = false } }
    func stop() {
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer); configurationObserver = nil }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        voice.stop(); engine.stop()
        queue.sync { stopped = true; enabled = false; playing = false; discard() }
    }
}

import Foundation
import AVFoundation
import CoreAudio

// Route audio to a NAMED device, and get/set the system default input & output.
// Lets the harness put the REP's voice on the mic channel (via a loopback device) and the
// CUSTOMER's voice on the speakers (captured by the app's system-audio tap) independently.

func devices() -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                       mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
    return ids
}
func name(_ d: AudioObjectID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                       mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v: Unmanaged<CFString>?; var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(d, &a, 0, nil, &s, &v) == noErr else { return "?" }
    return (v?.takeRetainedValue()) as String? ?? "?"
}
func find(_ n: String) -> AudioObjectID? { devices().first { name($0) == n } }
func getDefault(_ sel: AudioObjectPropertySelector) -> AudioObjectID {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var d = AudioObjectID(0); var s = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &s, &d); return d
}
@discardableResult
func setDefault(_ sel: AudioObjectPropertySelector, _ d: AudioObjectID) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v = d
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &v) == noErr
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: audiotool play|setin|setout|getin|getout ..."); exit(2) }

switch args[1] {
case "getout": print(name(getDefault(kAudioHardwarePropertyDefaultOutputDevice)))
case "getin":  print(name(getDefault(kAudioHardwarePropertyDefaultInputDevice)))
case "setout", "setin":
    guard args.count >= 3, let d = find(args[2]) else { print("device not found: \(args.count >= 3 ? args[2] : "")"); exit(1) }
    let sel = args[1] == "setout" ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    setDefault(sel, d)
    usleep(400_000)
    let now = name(getDefault(sel))
    print(now == args[2] ? "ok \(now)" : "FAILED (still \(now))")
    exit(now == args[2] ? 0 : 1)
case "serve":
    // Long-lived player: one stable PID for the whole call, so the app can exclude it from the
    // global tap. Reads "<device>|<wav>|<volume>" lines on stdin, plays each, prints "ok".
    print("pid \(ProcessInfo.processInfo.processIdentifier)")
    fflush(stdout)
    while let line = readLine(strippingNewline: true) {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 2, let dev = find(parts[0]), let file = try? AVAudioFile(forReading: URL(fileURLWithPath: parts[1])) else {
            print("err"); fflush(stdout); continue
        }
        let vol = parts.count >= 3 ? (Float(parts[2]) ?? 1.0) : 1.0
        let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
        engine.attach(player)
        var devID = dev
        AudioUnitSetProperty(engine.outputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        engine.mainMixerNode.outputVolume = vol
        do { try engine.start() } catch { print("err"); fflush(stdout); continue }
        // scheduleFile's completion fires when the buffer has been CONSUMED, not when it has been
        // played out of the device. Stopping on that signal clipped the last word off every clip,
        // which then showed up as a truncated transcript and provoked whisper hallucinations on the
        // silence. Wait out the real duration instead.
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        player.scheduleFile(file, at: nil, completionHandler: nil)
        player.play()
        Thread.sleep(forTimeInterval: seconds + 0.6)
        engine.stop()
        print("ok"); fflush(stdout)
    }
case "play":
    // play <device name> <wav> [volume]
    guard args.count >= 4, let dev = find(args[2]) else { print("device not found"); exit(1) }
    let url = URL(fileURLWithPath: args[3])
    let vol = args.count >= 5 ? Float(args[4]) ?? 1.0 : 1.0
    guard let file = try? AVAudioFile(forReading: url) else { print("cannot read \(url.path)"); exit(1) }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    // Point the engine's OUTPUT at the requested device before starting it.
    var devID = dev
    let au = engine.outputNode.audioUnit!
    let st = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                  &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
    guard st == noErr else { print("cannot target device: OSStatus \(st)"); exit(1) }
    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
    engine.mainMixerNode.outputVolume = vol
    do { try engine.start() } catch { print("engine: \(error)"); exit(1) }
    let done = DispatchSemaphore(value: 0)
    player.scheduleFile(file, at: nil) { done.signal() }
    player.play()
    _ = done.wait(timeout: .now() + 120)
    usleep(250_000)
    engine.stop()
default: print("unknown command"); exit(2)
}

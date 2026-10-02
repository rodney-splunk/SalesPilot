// SystemAudioCapture.swift — M3: capture ANOTHER app's audio (the customer on Webex/Zoom) via a
// Core Audio PROCESS TAP. Audio-only: no Screen-Recording permission, no purple indicator.
// Requires macOS 14.4+. Ported from the call sequence in insidegui/AudioCap.
//
// Emits 16 kHz mono Float samples via onSamples (ready for the streaming transcriber).

import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import AppKit

/// Finds a running app whose audio we'd want to tap (the customer's conferencing/browser app).
enum TargetApp {
    static let hints = ["webex", "zoom", "teams", "meet", "slack", "facetime",
                        "discord", "chrome", "safari", "arc", "firefox", "edge"]
    static func current() -> (name: String, pid: pid_t)? {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = (app.localizedName ?? "").lowercased()
            let bid = (app.bundleIdentifier ?? "").lowercased()
            if hints.contains(where: { name.contains($0) || bid.contains($0) }) {
                return (app.localizedName ?? bid, app.processIdentifier)
            }
        }
        return nil
    }
}

@available(macOS 14.4, *)
final class SystemAudioCapture {
    /// Resampled 16 kHz mono float samples from the tapped app's output.
    var onSamples: (([Float]) -> Void)?
    var onAudioDetected: (() -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private var tapFormat: AVAudioFormat?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let ioQueue = DispatchQueue(label: "system.audio.tap")

    /// True once any non-silent audio has arrived on this tap.
    private(set) var sawRealAudio = false

    /// Name of the device we are tapping, for the HUD and the logs.
    private(set) var tappedDeviceName = ""
    /// Fired when the system default output device changes while we are capturing. A conferencing
    /// app swapping the default-output slot mid-call used to strand the tap on the old device and
    /// silently produce a one-sided transcript, so the owner rebuilds the tap when this fires.
    var onOutputDeviceChanged: (() -> Void)?
    private var deviceListenerInstalled = false
    private lazy var deviceListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self = self else { return }
        let now = SystemAudioCapture.tapTargetDevice()?.name ?? ""
        guard now != self.tappedDeviceName else { return }   // slot changed but our device did not
        NSLog("[SalesPilot] output device changed ('\(self.tappedDeviceName)' -> '\(now)') — rebuilding customer capture")
        DispatchQueue.main.async { self.onOutputDeviceChanged?() }
    }

    // MARK: - Core Audio helpers
    private static func processObject(forPID pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var pidValue = pid
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &pidValue) { pidPtr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<pid_t>.size), pidPtr, &size, &obj)
        }
        return (status == noErr && obj != AudioObjectID(kAudioObjectUnknown)) ? obj : nil
    }

    // Webex (and Teams, and anything with a "virtual audio device") installs a HAL plug-in and makes
    // ITSELF the system default output while a meeting runs, then hands the slot back when it ends.
    // The far-end voice still plays out of the real speaker; the virtual device carries none of it.
    // Tapping whatever happens to hold the default-output slot therefore captures silence for the
    // whole call and the transcript comes back one-sided. So: never tap a virtual or aggregate
    // device — resolve to real hardware.
    private static let syntheticTransports: Set<UInt32> = [
        kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate,
    ]

    private static func transportType(_ dev: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr else { return 0 }
        return v
    }

    private static func outputChannelCount(_ dev: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func uid(of dev: AudioObjectID) -> CFString? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v?.takeRetainedValue()
    }

    static func name(of dev: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr else { return "unknown" }
        return (v?.takeRetainedValue()) as String? ?? "unknown"
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return dev
    }

    private static func allOutputDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { outputChannelCount($0) > 0 }
    }

    /// The last real hardware device to hold the default-output slot. When a conferencing app takes
    /// the slot, this is the speaker the human is still listening through, so it is the device the
    /// call audio is actually coming out of — and the right one to tap.
    private static var lastRealDefaultUID: CFString?

    /// The device to build the capture aggregate around: the system default output when that is real
    /// hardware, otherwise the real hardware device the call audio is actually coming out of.
    static func tapTargetDevice() -> (uid: CFString, name: String)? {
        if let def = defaultOutputDevice(), !syntheticTransports.contains(transportType(def)), let u = uid(of: def) {
            lastRealDefaultUID = u
            return (u, name(of: def))
        }
        let real = allOutputDevices().filter { !syntheticTransports.contains(transportType($0)) }
        // Best: the real device that held the slot before the conferencing app grabbed it.
        if let remembered = lastRealDefaultUID,
           let dev = real.first(where: { uid(of: $0).map { ($0 as String) == (remembered as String) } ?? false }) {
            NSLog("[SalesPilot] default output is a virtual device; tapping '\(name(of: dev))', the speaker in use before the meeting started")
            return (remembered, name(of: dev))
        }
        // Nothing remembered (we started mid-meeting). A person on a call is far more likely to be
        // on a headset or desk device than on the built-in speakers, so try external hardware first.
        let external = real.filter { transportType($0) != kAudioDeviceTransportTypeBuiltIn }
        guard let dev = external.first ?? real.first, let u = uid(of: dev) else { return nil }
        NSLog("[SalesPilot] default output is a virtual device; tapping real hardware '\(name(of: dev))' instead")
        return (u, name(of: dev))
    }

    private static func defaultOutputDeviceUID() -> CFString? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var usize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &usize, &uid)
        return st == noErr ? uid?.takeRetainedValue() : nil
    }

    private func readTapUID() -> CFString? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &uid)
        return st == noErr ? uid?.takeRetainedValue() : nil
    }

    private func readTapFormat() -> AVAudioFormat? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd) == noErr else { return nil }
        return AVAudioFormat(streamDescription: &asbd)
    }

    // MARK: - Lifecycle
    func start(pid: pid_t) -> Bool {
        guard let procObj = SystemAudioCapture.processObject(forPID: pid) else { return false }
        return configure(CATapDescription(stereoMixdownOfProcesses: [procObj]))
    }

    /// Global tap: capture ALL system audio output except the given processes (e.g. ourselves).
    /// More reliable than per-app for browsers, which render audio in hidden helper processes.
    func startGlobal(excluding pids: [pid_t]) -> Bool {
        let exclude = pids.compactMap { SystemAudioCapture.processObject(forPID: $0) }
        return configure(CATapDescription(stereoGlobalTapButExcludeProcesses: exclude))
    }

    private func configure(_ desc: CATapDescription) -> Bool {
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted

        // Log the exact failure point. A failed tap silently turns every call into a one-sided
        // transcript, and "it just didn't work" is impossible to diagnose after the fact.
        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTap)
        guard tapStatus == noErr, newTap != AudioObjectID(kAudioObjectUnknown) else {
            NSLog("[SalesPilot] system-audio tap FAILED to create: OSStatus \(tapStatus). Check System Settings > Privacy & Security > Screen & System Audio Recording.")
            return false
        }
        tapID = newTap

        guard let tapUID = readTapUID() else { NSLog("[SalesPilot] tap created but UID unreadable"); stop(); return false }
        guard let target = SystemAudioCapture.tapTargetDevice() else {
            NSLog("[SalesPilot] no real OUTPUT device — cannot build the capture aggregate"); stop(); return false
        }
        let outUID = target.uid
        tappedDeviceName = target.name
        guard let fmt = readTapFormat() else { NSLog("[SalesPilot] tap format unreadable"); stop(); return false }
        tapFormat = fmt
        converter = AVAudioConverter(from: fmt, to: outFormat)

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "SalesCopilotAgg",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey as String: outUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: outUID]],
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapDriftCompensationKey as String: true,
                kAudioSubTapUIDKey as String: tapUID,
            ]],
        ]
        var agg = AudioObjectID(0)
        let aggStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &agg)
        guard aggStatus == noErr else {
            NSLog("[SalesPilot] aggregate device FAILED: OSStatus \(aggStatus) around output \(outUID)")
            stop(); return false
        }
        aggregateID = agg

        let block: AudioDeviceIOBlock = { [weak self] _, inInputData, _, _, _ in
            self?.handle(inInputData)
        }
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue, block) == noErr, ioProcID != nil else {
            NSLog("[SalesPilot] capture IOProc could not be installed"); stop(); return false
        }
        guard AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            NSLog("[SalesPilot] capture aggregate refused to start"); stop(); return false
        }
        NSLog("[SalesPilot] customer audio capture STARTED on '\(target.name)'")
        startWatchingDefaultOutputDevice()
        return true
    }

    private func handle(_ inInputData: UnsafePointer<AudioBufferList>) {
        guard let tapFormat = tapFormat, let converter = converter,
              let inBuf = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inInputData) else { return }
        let ratio = outFormat.sampleRate / tapFormat.sampleRate
        let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 16)
        guard cap > 0, let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
        var err: NSError?
        var fed = false
        converter.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil, let ch = outBuf.floatChannelData?[0] else { return }
        let n = Int(outBuf.frameLength)
        guard n > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: ch, count: n))
        // A tap can start cleanly and still deliver nothing but digital silence — that is exactly
        // what happens when it lands on a device the call is not playing through. Record the first
        // real audio so the HUD can tell "capturing" apart from "attached to the wrong device".
        if !sawRealAudio, samples.contains(where: { abs($0) > 0.0005 }) {
            sawRealAudio = true
            DispatchQueue.main.async { [weak self] in self?.onAudioDetected?() }
        }
        onSamples?(samples)
    }

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private func startWatchingDefaultOutputDevice() {
        guard !deviceListenerInstalled else { return }
        let st = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                     &SystemAudioCapture.defaultOutputAddress,
                                                     ioQueue, deviceListenerBlock)
        deviceListenerInstalled = (st == noErr)
    }

    private func stopWatchingDefaultOutputDevice() {
        guard deviceListenerInstalled else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &SystemAudioCapture.defaultOutputAddress,
                                               ioQueue, deviceListenerBlock)
        deviceListenerInstalled = false
    }

    func stop() {
        stopWatchingDefaultOutputDevice()
        if let ioProcID = ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        converter = nil; tapFormat = nil
    }
}

import Foundation
import CoreAudio
func processObject(forPID pid: pid_t) -> AudioObjectID? {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var p = pid; var obj = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let st = withUnsafeMutablePointer(to: &p) { ptr in
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), ptr, &size, &obj)
    }
    return (st == noErr && obj != AudioObjectID(kAudioObjectUnknown)) ? obj : nil
}
let pid = pid_t(CommandLine.arguments[1])!
if let o = processObject(forPID: pid) { print("pid \(pid) -> audio object \(o)  (CAN be excluded)") }
else { print("pid \(pid) -> NO audio object  (exclusion silently does nothing)") }

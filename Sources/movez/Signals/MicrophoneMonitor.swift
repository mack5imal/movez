import CoreAudio
import Foundation

/// Whether the default input device is in use.
///
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` is a property read, not a capture, so it never
/// triggers the microphone permission prompt and never sees any audio.
final class MicrophoneMonitor: MicSource {
    func isInUse() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private func defaultInputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }
}

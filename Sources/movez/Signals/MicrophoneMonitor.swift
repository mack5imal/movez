import CoreAudio
import Darwin
import Foundation

/// Whether anything other than Movez is recording from a microphone.
///
/// On macOS 14.2 and later CoreAudio lists the processes doing audio IO and says, per process,
/// whether it has an input stream running. That is the precise answer: it covers every device, it
/// tells a call from music playing through a headset, and it leaves Movez's own chimes out.
/// Before 14.2 the fallback is every device that has input streams and is running. It still
/// cannot tell direction on a device that also plays sound, but it no longer misses a call on a
/// microphone that is not the default one, which is what reading only the default device did.
///
/// Both are property reads, not captures, so they never trigger the microphone permission prompt
/// and never see any audio.
final class MicrophoneMonitor: MicSource {
    /// One process doing audio IO.
    struct AudioProcess: Equatable {
        var pid: pid_t
        var isRunningInput: Bool
    }

    /// One audio device.
    struct AudioDevice: Equatable {
        var hasInputStreams: Bool
        var isRunningSomewhere: Bool
    }

    private let ownPID: pid_t

    init(ownPID: pid_t = getpid()) {
        self.ownPID = ownPID
    }

    func isInUse() -> Bool {
        Self.isInUse(processes: Self.audioProcesses(), ownPID: ownPID, devices: Self.inputDevices)
    }

    /// The decision on its own, so it can be tested with made-up lists. `processes` is nil when
    /// this macOS cannot list them, or the list could not be read; only then are the devices
    /// asked, which is why they are passed in lazily.
    static func isInUse(processes: [AudioProcess]?, ownPID: pid_t, devices: () -> [AudioDevice]) -> Bool {
        if let processes {
            return processes.contains { $0.pid != ownPID && $0.isRunningInput }
        }
        return devices().contains { $0.hasInputStreams && $0.isRunningSomewhere }
    }

    // MARK: - CoreAudio

    /// Every process CoreAudio knows about, or nil before macOS 14.2 or when the list fails.
    static func audioProcesses() -> [AudioProcess]? {
        guard #available(macOS 14.2, *) else { return nil }
        guard let objects = objectList(kAudioHardwarePropertyProcessObjectList) else { return nil }
        return objects.compactMap { object in
            guard let pid: pid_t = read(object, kAudioProcessPropertyPID, initial: 0),
                  let input: UInt32 = read(object, kAudioProcessPropertyIsRunningInput, initial: 0) else { return nil }
            return AudioProcess(pid: pid, isRunningInput: input != 0)
        }
    }

    /// Every audio device, with whether it has an input stream and whether its IO is running.
    static func inputDevices() -> [AudioDevice] {
        (objectList(kAudioHardwarePropertyDevices) ?? []).map { device in
            let running: UInt32 = read(device, kAudioDevicePropertyDeviceIsRunningSomewhere, initial: 0) ?? 0
            return AudioDevice(hasInputStreams: hasInputStreams(device), isRunningSomewhere: running != 0)
        }
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return status == noErr && size > 0
    }

    /// An array of object ids held by the system object.
    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// A fixed-size scalar property in the global scope.
    private static func read<Value: FixedWidthInteger>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        initial: Value
    ) -> Value? {
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}

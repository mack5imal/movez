import XCTest
@testable import movez

/// The device and process selection, without CoreAudio.
final class MicrophoneMonitorTests: XCTestCase {
    private let ownPID: pid_t = 500

    private func inUse(
        processes: [MicrophoneMonitor.AudioProcess]?,
        devices: [MicrophoneMonitor.AudioDevice] = []
    ) -> Bool {
        MicrophoneMonitor.isInUse(processes: processes, ownPID: ownPID, devices: { devices })
    }

    // MARK: - Per process (macOS 14.2+)

    func testAProcessRecordingIsACall() {
        XCTAssertTrue(inUse(processes: [
            .init(pid: 100, isRunningInput: false),
            .init(pid: 200, isRunningInput: true)
        ]))
    }

    /// Music through a headset runs the device, but only output: the device-wide property read
    /// that as a call and deferred every break for as long as the music played.
    func testPlayingSoundIsNotACall() {
        XCTAssertFalse(inUse(
            processes: [.init(pid: 100, isRunningInput: false)],
            devices: [.init(hasInputStreams: true, isRunningSomewhere: true)]
        ), "the process list is the answer when there is one; the device list is never consulted")
    }

    func testMovezsOwnInputDoesNotCount() {
        XCTAssertFalse(inUse(processes: [.init(pid: ownPID, isRunningInput: true)]))
    }

    func testNoAudioProcessesIsNoCall() {
        XCTAssertFalse(inUse(processes: []))
    }

    // MARK: - Per device (before macOS 14.2)

    /// A call app set to a USB headset while the default input is the built-in mic ran a device
    /// that was never looked at.
    func testAnyInputDeviceRunningCountsNotOnlyTheDefault() {
        XCTAssertTrue(inUse(processes: nil, devices: [
            .init(hasInputStreams: true, isRunningSomewhere: false),
            .init(hasInputStreams: true, isRunningSomewhere: true)
        ]))
    }

    func testAnOutputOnlyDeviceRunningIsNotACall() {
        XCTAssertFalse(inUse(processes: nil, devices: [
            .init(hasInputStreams: false, isRunningSomewhere: true),
            .init(hasInputStreams: true, isRunningSomewhere: false)
        ]), "speakers playing sound are not a microphone")
    }

    func testNoDevicesIsNoCall() {
        XCTAssertFalse(inUse(processes: nil, devices: []))
    }

    /// The real CoreAudio reads run without the microphone permission prompt and without
    /// crashing, whichever path this macOS takes. What they return depends on the machine.
    func testTheRealMonitorReads() {
        _ = MicrophoneMonitor().isInUse()
        _ = MicrophoneMonitor.inputDevices()
        if #available(macOS 14.2, *) {
            XCTAssertNotNil(MicrophoneMonitor.audioProcesses(), "the process list is readable on 14.2 and later")
        }
    }
}

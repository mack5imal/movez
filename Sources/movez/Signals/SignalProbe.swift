import Foundation

/// `movez --probe-signals`: reads every real monitor once a second for five seconds and prints
/// what it found.
///
/// This exists because the four adapters are the only part of movez that cannot be unit tested —
/// they talk to CoreGraphics, CoreAudio, the window server and the process table. The probe is
/// how a build proves they run on a real machine without crashing.
enum SignalProbe {
    static let samples = 5

    /// Cleanliness note: the prints here are the output of a command-line tool, not debug logging.
    @MainActor
    static func run(completion: @escaping (Int32) -> Void) {
        let idle = IdleMonitor()
        let mic = MicrophoneMonitor()
        let capture = ScreenCaptureMonitor()
        let fullscreen = FullscreenMonitor()

        var remaining = samples
        func sample() {
            let reading = fullscreen.reading(exceptions: [])
            let line = [
                "idle=\(Int(idle.idleSeconds()))",
                "mic=\(mic.isInUse())",
                "captured=\(capture.isCaptured())",
                "fullscreen=\(reading.isFullscreen)",
                "frontmost=\(reading.bundleId ?? "-")"
            ].joined(separator: " ")
            print(line)
            fflush(stdout)

            remaining -= 1
            guard remaining > 0 else {
                print("probe ok")
                fflush(stdout)
                completion(0)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { sample() }
        }
        sample()
    }
}

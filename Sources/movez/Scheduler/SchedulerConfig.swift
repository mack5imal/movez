import Foundation

/// Every tunable the scheduler reads, with the defaults from research §6.
struct SchedulerConfig: Codable, Equatable, Hashable {
    var sitSeconds: Int = 55 * 60
    /// Five one-minute movements, each after a five-second lead-in. The scheduler never looks
    /// inside a routine, so the figure is restated here rather than read off one; a test holds the
    /// two together.
    var breakSeconds: Int = 325
    var microEnabled: Bool = true
    var microEverySeconds: Int = 1800
    var microMinGapBeforeFullSeconds: Int = 600
    /// The longest a micro-break runs: two thirty-second movements and the lead-in between them.
    /// A single per-side movement runs sixty, and the panel, which knows which it is, ends it
    /// then; this is the backstop, and the length the half rule is measured against.
    var microSeconds: Int = 65
    var microCountInSeconds: Int = 30
    var headsUpSeconds: Int = 60
    var inputPauseSeconds: Int = 10
    var inputWaitCapSeconds: Int = 60
    var snoozeSeconds: Int = 300
    var maxSnoozesPerBreak: Int = 2
    var skipDelaySeconds: Int = 3
    var completionFraction: Double = 0.5
    var awayThresholdSeconds: Int = 180
    var fullCreditSeconds: Int = 300
    var wakeQuietSeconds: Int = 60
    var postSuppressionGraceSeconds: Int = 120
    var deferredBadgeSeconds: Int = 1800
    var deferredSnoozeAllowance: Int = 1
    var workingHours: WorkingHours = .standard
    var calendar: Calendar = .current

    /// The smallest sit interval a break can be completed at, in seconds — used by the
    /// completion rule's time half.
    var completionSeconds: Int { Int(Double(breakSeconds) * completionFraction) }

    /// Custom presets run 15–120 minutes in five-minute steps.
    static let customSitRangeMinutes = 15...120
    static let customSitStepMinutes = 5

    /// Builds the config a preset implies. The 25/5 preset never serves micro-breaks: its bouts
    /// are already under the 30-minute threshold the micro-break exists to break up.
    static func from(
        preset: PresetId,
        customSitMinutes: Int? = nil,
        microOn: Bool = true,
        calendar: Calendar = .current
    ) -> SchedulerConfig {
        var config = SchedulerConfig()
        config.calendar = calendar
        switch preset {
        case .twentyFiveFive:
            config.sitSeconds = 25 * 60
            config.microEnabled = false
        case .fiftyFiveFive:
            config.sitSeconds = 55 * 60
            config.microEnabled = microOn
        case .eightyFiveFive:
            config.sitSeconds = 85 * 60
            config.microEnabled = microOn
        case .custom:
            let minutes = clampCustom(customSitMinutes ?? 55)
            config.sitSeconds = minutes * 60
            config.microEnabled = microOn && minutes > 40
        }
        return config
    }

    static func clampCustom(_ minutes: Int) -> Int {
        let stepped = (minutes / customSitStepMinutes) * customSitStepMinutes
        return min(customSitRangeMinutes.upperBound, max(customSitRangeMinutes.lowerBound, stepped))
    }

    /// A hash that is stable across launches, unlike `hashValue`. Stored in the snapshot so a
    /// resumed session can tell whether the settings changed while it was gone.
    var stableHash: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ value: Int) {
            hash = (hash ^ UInt64(bitPattern: Int64(value))) &* 0x0000_0100_0000_01B3
        }
        mix(sitSeconds)
        mix(breakSeconds)
        mix(microEnabled ? 1 : 0)
        mix(microEverySeconds)
        mix(microMinGapBeforeFullSeconds)
        mix(headsUpSeconds)
        mix(snoozeSeconds)
        mix(maxSnoozesPerBreak)
        mix(awayThresholdSeconds)
        mix(fullCreditSeconds)
        mix(postSuppressionGraceSeconds)
        for day in workingHours.days {
            mix(day.enabled ? 1 : 0)
            mix(day.startMinutes)
            mix(day.endMinutes)
        }
        return hash
    }
}

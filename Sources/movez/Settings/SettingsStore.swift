import Foundation
import SwiftUI

/// Every user-steerable setting, backed by the `movez` UserDefaults suite.
///
/// Each key has a default that matches the brief, and nothing is stored until the user changes it.
@MainActor
final class SettingsStore: ObservableObject {
    enum Key {
        static let preset = "preset"
        static let customSitMinutes = "customSitMinutes"
        static let microEnabled = "microEnabled"
        static let workingHours = "workingHours"
        static let equipment = "equipment"
        static let difficultyCap = "difficultyCap"
        static let excludedMovementIds = "excludedMovementIds"
        static let focus = "focus"
        static let wallAvailable = "wallAvailable"
        static let floorAvailable = "floorAvailable"
        static let stairsAvailable = "stairsAvailable"
        static let suppressMic = "suppressMic"
        static let suppressCapture = "suppressCapture"
        static let suppressFullscreen = "suppressFullscreen"
        static let fullscreenExceptions = "fullscreenExceptions"
        static let awayThresholdMinutes = "awayThresholdMinutes"
        static let awayBehaviour = "awayBehaviour"
        static let soundsEnabled = "soundsEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let debugTimeScale = "debugTimeScale"
        static let debugExpanded = "debugExpanded"
        static let acceptedNoticeVersion = "acceptedNoticeVersion"
        static let acceptedNoticeAt = "acceptedNoticeAt"
        // The mode and Strength's own settings. New keys only: an upgrade finds none of them and
        // reads the defaults, so every movement-mode key above keeps the value it had.
        static let mode = "mode"
        static let strengthSetUp = "strengthSetUp"
        static let strengthEquipment = "strengthEquipment"
        static let strengthSolidWallNearby = "strengthSolidWallNearby"
        static let strengthBreaksPerDay = "strengthBreaksPerDay"
        static let strengthDifficultyCap = "strengthDifficultyCap"
        static let strengthFocus = "strengthFocus"
        static let strengthExcludedIds = "strengthExcludedIds"
    }

    static let suiteName = "movez"
    /// The range the "Count me away after" select offers, in minutes.
    static let awayThresholdRange = 2...10
    /// The strength breaks a day the Settings segments offer, and the default the owner chose.
    nonisolated static let strengthBreaksRange = 1...4
    nonisolated static let strengthBreaksDefault = 3
    /// Strength starts at Beginner, below the movement cap's Moderate: loaded work is the riskier
    /// place to start too high.
    nonisolated static let strengthDifficultyDefault = 1

    private let defaults: UserDefaults

    @Published var preset: PresetId { didSet { write(preset.rawValue, Key.preset) } }
    @Published var customSitMinutes: Int { didSet { write(customSitMinutes, Key.customSitMinutes) } }
    @Published var microEnabled: Bool { didSet { write(microEnabled, Key.microEnabled) } }
    @Published var workingHours: WorkingHours { didSet { writeJSON(workingHours, Key.workingHours) } }
    @Published var equipment: Set<Equipment> { didSet { write(equipment.map(\.rawValue).sorted(), Key.equipment) } }
    @Published var difficultyCap: Int { didSet { write(difficultyCap, Key.difficultyCap) } }
    @Published var excludedMovementIds: Set<String> {
        didSet { write(excludedMovementIds.sorted(), Key.excludedMovementIds) }
    }
    @Published var focus: Focus { didSet { write(focus.rawValue, Key.focus) } }
    /// Whether there is a wall to lean on, floor the user is willing to get down on, and stairs
    /// nearby. All three default to yes, which serves the whole library.
    @Published var wallAvailable: Bool { didSet { write(wallAvailable, Key.wallAvailable) } }
    @Published var floorAvailable: Bool { didSet { write(floorAvailable, Key.floorAvailable) } }
    @Published var stairsAvailable: Bool { didSet { write(stairsAvailable, Key.stairsAvailable) } }
    @Published var suppressMic: Bool { didSet { write(suppressMic, Key.suppressMic) } }
    @Published var suppressCapture: Bool { didSet { write(suppressCapture, Key.suppressCapture) } }
    @Published var suppressFullscreen: Bool { didSet { write(suppressFullscreen, Key.suppressFullscreen) } }
    @Published var fullscreenExceptions: [String] { didSet { write(fullscreenExceptions, Key.fullscreenExceptions) } }
    @Published var awayThresholdMinutes: Int { didSet { write(awayThresholdMinutes, Key.awayThresholdMinutes) } }
    @Published var awayBehaviour: AwayBehaviour { didSet { write(awayBehaviour.rawValue, Key.awayBehaviour) } }
    @Published var soundsEnabled: Bool { didSet { write(soundsEnabled, Key.soundsEnabled) } }
    @Published var launchAtLogin: Bool { didSet { write(launchAtLogin, Key.launchAtLogin) } }
    @Published var debugTimeScale: Double { didSet { write(debugTimeScale, Key.debugTimeScale) } }
    @Published var debugExpanded: Bool { didSet { write(debugExpanded, Key.debugExpanded) } }
    /// The version of the health and safety notice the user accepted, and when. Nil until they
    /// have; a newer notice version asks again.
    @Published var acceptedNoticeVersion: String? {
        didSet { writeOptional(acceptedNoticeVersion, Key.acceptedNoticeVersion) }
    }
    @Published var acceptedNoticeAt: Date? { didSet { writeOptional(acceptedNoticeAt, Key.acceptedNoticeAt) } }

    /// The mode the next break is served in. Change it through `ModeSwitch`, which holds back a
    /// first switch until the mode has been set up.
    @Published var mode: BreakMode { didSet { write(mode.rawValue, Key.mode) } }
    /// Whether the user has confirmed the Strength setup once. Until then a switch to Strength
    /// opens the setup and leaves the mode alone.
    @Published var strengthSetUp: Bool { didSet { write(strengthSetUp, Key.strengthSetUp) } }
    @Published var strengthEquipment: Set<StrengthEquipment> {
        didSet { write(strengthEquipment.map(\.rawValue).sorted(), Key.strengthEquipment) }
    }
    @Published var strengthSolidWallNearby: Bool {
        didSet { write(strengthSolidWallNearby, Key.strengthSolidWallNearby) }
    }
    @Published var strengthBreaksPerDay: Int { didSet { write(strengthBreaksPerDay, Key.strengthBreaksPerDay) } }
    @Published var strengthDifficultyCap: Int { didSet { write(strengthDifficultyCap, Key.strengthDifficultyCap) } }
    @Published var strengthFocus: StrengthFocus { didSet { write(strengthFocus.rawValue, Key.strengthFocus) } }
    @Published var strengthExcludedIds: Set<String> {
        didSet { write(strengthExcludedIds.sorted(), Key.strengthExcludedIds) }
    }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
        self.defaults = defaults

        preset = PresetId(rawValue: defaults.string(forKey: Key.preset) ?? "") ?? .fiftyFiveFive
        customSitMinutes = defaults.object(forKey: Key.customSitMinutes) as? Int ?? 45
        microEnabled = defaults.object(forKey: Key.microEnabled) as? Bool ?? true
        workingHours = Self.readJSON(WorkingHours.self, Key.workingHours, from: defaults) ?? .standard
        equipment = Set((defaults.stringArray(forKey: Key.equipment) ?? []).compactMap(Equipment.init(rawValue:)))
        difficultyCap = defaults.object(forKey: Key.difficultyCap) as? Int ?? 2
        excludedMovementIds = Set(defaults.stringArray(forKey: Key.excludedMovementIds) ?? [])
        focus = Focus(rawValue: defaults.string(forKey: Key.focus) ?? "") ?? .none
        wallAvailable = defaults.object(forKey: Key.wallAvailable) as? Bool ?? true
        floorAvailable = defaults.object(forKey: Key.floorAvailable) as? Bool ?? true
        stairsAvailable = defaults.object(forKey: Key.stairsAvailable) as? Bool ?? true
        suppressMic = defaults.object(forKey: Key.suppressMic) as? Bool ?? true
        suppressCapture = defaults.object(forKey: Key.suppressCapture) as? Bool ?? true
        suppressFullscreen = defaults.object(forKey: Key.suppressFullscreen) as? Bool ?? true
        fullscreenExceptions = defaults.stringArray(forKey: Key.fullscreenExceptions) ?? []
        awayThresholdMinutes = defaults.object(forKey: Key.awayThresholdMinutes) as? Int ?? 3
        awayBehaviour = AwayBehaviour(rawValue: defaults.string(forKey: Key.awayBehaviour) ?? "") ?? .reset
        soundsEnabled = defaults.object(forKey: Key.soundsEnabled) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        debugTimeScale = defaults.object(forKey: Key.debugTimeScale) as? Double ?? 1
        debugExpanded = defaults.object(forKey: Key.debugExpanded) as? Bool ?? false
        acceptedNoticeVersion = defaults.string(forKey: Key.acceptedNoticeVersion)
        acceptedNoticeAt = defaults.object(forKey: Key.acceptedNoticeAt) as? Date

        mode = BreakMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .fallback
        strengthSetUp = defaults.object(forKey: Key.strengthSetUp) as? Bool ?? false
        strengthEquipment = Set(
            (defaults.stringArray(forKey: Key.strengthEquipment) ?? []).compactMap(StrengthEquipment.init(rawValue:))
        )
        strengthSolidWallNearby = defaults.object(forKey: Key.strengthSolidWallNearby) as? Bool ?? true
        let storedBreaks = defaults.object(forKey: Key.strengthBreaksPerDay) as? Int ?? Self.strengthBreaksDefault
        strengthBreaksPerDay = min(max(storedBreaks, Self.strengthBreaksRange.lowerBound), Self.strengthBreaksRange.upperBound)
        strengthDifficultyCap = defaults.object(forKey: Key.strengthDifficultyCap) as? Int ?? Self.strengthDifficultyDefault
        strengthFocus = StrengthFocus(rawValue: defaults.string(forKey: Key.strengthFocus) ?? "") ?? .none
        strengthExcludedIds = Set(defaults.stringArray(forKey: Key.strengthExcludedIds) ?? [])
    }

    /// What the user has said they do not have, so no movement that needs it is served.
    var unavailableRequirements: Set<Requirement> {
        var unavailable: Set<Requirement> = []
        if !wallAvailable { unavailable.insert(.wall) }
        if !floorAvailable { unavailable.insert(.floor) }
        if !stairsAvailable { unavailable.insert(.stairs) }
        return unavailable
    }

    /// The scheduler config these settings imply.
    var schedulerConfig: SchedulerConfig {
        var config = SchedulerConfig.from(
            preset: preset,
            customSitMinutes: customSitMinutes,
            microOn: microEnabled
        )
        config.workingHours = workingHours
        config.awayThresholdSeconds = awayThresholdMinutes * 60
        config.awayBehaviour = awayBehaviour
        return config
    }

    /// The micro-break toggle is hidden for short sit intervals: the bout is already under the
    /// thirty-minute threshold a micro-break exists to break up.
    var microToggleAvailable: Bool {
        switch preset {
        case .twentyFiveFive: return false
        case .custom: return customSitMinutes > 40
        case .fiftyFiveFive, .eightyFiveFive: return true
        }
    }

    private func write(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func writeOptional(_ value: Any?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// Records that the user accepted this version of the notice, now.
    func acceptNotice(version: String, at date: Date) {
        acceptedNoticeVersion = version
        acceptedNoticeAt = date
    }

    private func writeJSON<Value: Encodable>(_ value: Value, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func readJSON<Value: Decodable>(
        _ type: Value.Type,
        _ key: String,
        from defaults: UserDefaults
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

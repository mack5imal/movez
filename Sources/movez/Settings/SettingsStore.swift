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
        static let soundsEnabled = "soundsEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let debugTimeScale = "debugTimeScale"
        static let debugExpanded = "debugExpanded"
    }

    static let suiteName = "movez"
    /// The range the "Count me away after" select offers, in minutes.
    static let awayThresholdRange = 2...10

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
    @Published var soundsEnabled: Bool { didSet { write(soundsEnabled, Key.soundsEnabled) } }
    @Published var launchAtLogin: Bool { didSet { write(launchAtLogin, Key.launchAtLogin) } }
    @Published var debugTimeScale: Double { didSet { write(debugTimeScale, Key.debugTimeScale) } }
    @Published var debugExpanded: Bool { didSet { write(debugExpanded, Key.debugExpanded) } }

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
        soundsEnabled = defaults.object(forKey: Key.soundsEnabled) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        debugTimeScale = defaults.object(forKey: Key.debugTimeScale) as? Double ?? 1
        debugExpanded = defaults.object(forKey: Key.debugExpanded) as? Bool ?? false
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

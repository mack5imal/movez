import Foundation

/// The decoded contents of `movement-library-v4.json`.
///
/// Foundation-only by design: the routine builder, the scheduler and the tests all read the
/// library without pulling in AppKit or SwiftUI.
struct MovementLibrary: Codable, Hashable {
    let library: String
    let version: String
    /// The date of the last edit. The JSON is the library itself; nothing generates it.
    let updated: String
    let schema: LibrarySchema
    let designRules: DesignRules
    let sittingEffects: [SittingEffect]
    let buckets: [BucketInfo]
    let families: [FamilyInfo]
    let presets: [Preset]
    let customPresetRule: String
    let microBreak: MicroBreakSpec
    let chainingRules: [String]
    let balanceProgression: [String]
    let movements: [Movement]
    let routines: [RoutineTemplate]
    let microRoutines: [MicroRoutineTemplate]
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case library, version, updated, schema, buckets, families, presets, movements, routines, notes
        case designRules = "design_rules"
        case sittingEffects = "sitting_effects"
        case customPresetRule = "custom_preset_rule"
        case microBreak = "micro_break"
        case chainingRules = "chaining_rules"
        case balanceProgression = "balance_progression"
        case microRoutines = "micro_routines"
    }

    // MARK: - Lookups

    func movement(id: String) -> Movement? {
        movements.first { $0.id == id }
    }

    func movements(in bucket: Bucket) -> [Movement] {
        movements.filter { $0.bucket == bucket }
    }

    func movements(in region: Region) -> [Movement] {
        movements.filter { $0.regions.contains(region) }
    }

    var microEligible: [Movement] {
        movements.filter(\.microEligible)
    }

    var byRegion: [Region: [Movement]] {
        var result: [Region: [Movement]] = [:]
        for movement in movements {
            for region in movement.regions {
                result[region, default: []].append(movement)
            }
        }
        return result
    }

    var byBucket: [Bucket: [Movement]] {
        Dictionary(grouping: movements, by: \.bucket)
    }

    var defaultPreset: Preset? {
        presets.first(where: \.isDefault) ?? presets.first
    }

    func preset(id: PresetId) -> Preset? {
        presets.first { $0.id == id }
    }

    /// Resolves the movements of a routine template in block order; nil if any block is dangling.
    func resolve(_ template: RoutineTemplate) -> [Movement]? {
        let resolved = template.blocks.compactMap { movement(id: $0.movementId) }
        return resolved.count == template.blocks.count ? resolved : nil
    }
}

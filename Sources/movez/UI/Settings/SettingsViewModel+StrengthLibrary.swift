import Foundation

/// What the Strength library browser reads: the library's own buckets, the filtered list and each
/// row's meta line.
///
/// Every code, name and bucket name comes from the strength library itself, so the browser never
/// carries a movement of its own and stays right when the library is revised.
extension SettingsViewModel {
    /// The category chips after All, in the order the library declares its buckets, each with
    /// the library's own name for it.
    var strengthBucketChips: [(bucket: StrengthBucket, name: String)] {
        (strengthLibrary?.buckets ?? []).map { ($0.id, $0.name) }
    }

    /// "Squat & lunge", as the library names the bucket.
    func strengthBucketName(_ bucket: StrengthBucket) -> String {
        strengthLibrary?.buckets.first { $0.id == bucket }?.name ?? bucket.rawValue
    }

    /// Name or code, case-insensitive, inside the chosen bucket.
    func matchingStrengthMovements() -> [StrengthMovement] {
        let query = librarySearch.trimmingCharacters(in: .whitespaces).lowercased()
        return (strengthLibrary?.movements ?? []).filter { movement in
            guard strengthLibraryBucket == nil || movement.bucket == strengthLibraryBucket else { return false }
            guard !query.isEmpty else { return true }
            return movement.name.lowercased().contains(query) || movement.id.lowercased().contains(query)
        }
    }

    var strengthShownLine: String { "\(matchingStrengthMovements().count) shown" }

    func isStrengthExcluded(_ movementId: String) -> Bool {
        settings.strengthExcludedIds.contains(movementId)
    }

    /// "Squat & lunge · Diff 1 · dumbbell or kettlebell · /side · micro"
    func strengthMeta(for movement: StrengthMovement) -> String {
        var meta = "\(strengthBucketName(movement.bucket)) · Diff \(movement.difficulty)"
        if let equipment = Self.equipmentText(movement.equipment) { meta += " · \(equipment)" }
        if movement.perSide { meta += " · /side" }
        if movement.microEligible { meta += " · micro" }
        return meta
    }

    /// The equipment a loaded move takes, in the design's lower-case words; nothing for a
    /// bodyweight move.
    static func equipmentText(_ equipment: [StrengthEquipment]) -> String? {
        let words = StrengthEquipment.allCases.filter(equipment.contains).map { item -> String in
            switch item {
            case .dumbbells: return "dumbbell"
            case .kettlebell: return "kettlebell"
            }
        }
        return words.isEmpty ? nil : words.joined(separator: " or ")
    }

    func openStrengthLibrary() {
        openSheet = .modeLibrary
    }
}

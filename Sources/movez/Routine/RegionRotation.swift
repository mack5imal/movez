import Foundation

/// The six-slot region rotation a day walks through, so consecutive breaks do not work the same
/// tissue twice (brief §6).
enum RotationSlot: String, CaseIterable, Hashable, Codable {
    case hip
    case tSpineChest
    case neckShoulder
    case posteriorChain
    case core
    case ankleFoot

    var regions: [Region] {
        switch self {
        case .hip: return [.hip, .glute, .quad, .adductor]
        case .tSpineChest: return [.thoracic, .chest, .shoulder]
        case .neckShoulder: return [.neck, .shoulder]
        case .posteriorChain: return [.hamstring, .glute]
        case .core: return [.lumbarCore]
        case .ankleFoot: return [.calfAnkle, .footShin]
        }
    }

    /// The slot for a given position in the day's rotation.
    static func slot(forRotationIndex index: Int) -> RotationSlot {
        let count = allCases.count
        let wrapped = ((index % count) + count) % count
        return allCases[wrapped]
    }
}

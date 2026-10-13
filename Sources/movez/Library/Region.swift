import Foundation

/// Body regions as normalised by the library generator. Raw values match `schema.regions` exactly.
enum Region: String, Codable, CaseIterable, Hashable {
    case adductor = "Adductor"
    case arm = "Arm"
    case breath = "Breath"
    case calfAnkle = "Calf/Ankle"
    case chest = "Chest"
    case eyes = "Eyes"
    case footShin = "Foot/Shin"
    case full = "Full"
    case glute = "Glute"
    case hamstring = "Ham"
    case hip = "Hip"
    case lumbarCore = "L-spine/Core"
    case neck = "Neck"
    case quad = "Quad"
    case shoulder = "Shoulder"
    case thoracic = "T-spine"
    case wristForearm = "Wrist/Forearm"

    var displayName: String { rawValue }
}

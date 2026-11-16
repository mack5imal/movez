import Foundation

/// The micro-break panel's content for whichever mode built the micro-break.
///
/// It lives in `Modes/` because choosing between the modes' micro-breaks is a mode branch, and
/// those live only here (DECISIONS 54). The panel itself reads the shared `MicroPanelBreak` and
/// never asks which mode it is showing.
extension MicroPanelBreak {
    init(_ planned: PlannedMicro) {
        switch planned {
        case let .movement(micro): self.init(micro)
        case let .strength(micro): self.init(micro)
        }
    }
}

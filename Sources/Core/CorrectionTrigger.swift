import Foundation

public enum CorrectionTrigger: String, Codable, Equatable, Sendable {
    case automaticBoundary
    case hotkey
    case layoutSwitch
}

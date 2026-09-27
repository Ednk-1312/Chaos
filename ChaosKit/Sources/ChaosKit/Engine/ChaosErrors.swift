import Foundation

public enum ChaosError: LocalizedError {
    case experimentAlreadyRunning
    case safetyNotConfirmed
    case noFaultsSelected
    case faultUnsupported(FaultID)
    case privilegeDenied(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .experimentAlreadyRunning: return "An experiment is already running. Stop it first."
        case .safetyNotConfirmed: return "Safety confirmation is required before starting this experiment."
        case .noFaultsSelected: return "This experiment has no faults to run."
        case .faultUnsupported(let id): return "macOS does not permit direct simulation of '\(id.rawValue)'. Use the guided alternative."
        case .privilegeDenied(let why): return "Authorization was declined: \(why)"
        case .invalidConfiguration(let why): return "Invalid experiment: \(why)"
        }
    }
}

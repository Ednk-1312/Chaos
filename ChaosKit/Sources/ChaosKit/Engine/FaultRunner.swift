import Foundation

/// Context passed to every fault activation/restoration call.
public struct FaultContext {
    public var config: ExperimentConfig
    public var binding: FaultBinding
    public var seed: UInt64
    public var workingDirectory: URL
    public var emit: @Sendable (ExperimentEvent) -> Void

    public init(config: ExperimentConfig, binding: FaultBinding, seed: UInt64,
                workingDirectory: URL, emit: @escaping @Sendable (ExperimentEvent) -> Void) {
        self.config = config; self.binding = binding; self.seed = seed
        self.workingDirectory = workingDirectory; self.emit = emit
    }

    public func param(_ key: String, default value: String) -> String {
        binding.parameters[key] ?? value
    }

    public func intParam(_ key: String, default value: Int) -> Int {
        binding.parameters[key].flatMap(Int.init) ?? value
    }

    public func doubleParam(_ key: String, default value: Double) -> Double {
        binding.parameters[key].flatMap(Double.init) ?? value
    }
}

/// What a fault reports back to the engine.
public struct ActivationResult {
    public var ok: Bool
    public var message: String
    public var cleanup: (@Sendable () -> Void)?
    public var initContext: @Sendable () -> [String: String] = { [:] }

    public init(ok: Bool, message: String, cleanup: (@Sendable () -> Void)? = nil) {
        self.ok = ok; self.message = message; self.cleanup = cleanup
    }

    public static func success(_ message: String, cleanup: (@Sendable () -> Void)? = nil) -> ActivationResult {
        ActivationResult(ok: true, message: message, cleanup: cleanup)
    }

    public static func failure(_ message: String) -> ActivationResult {
        ActivationResult(ok: false, message: message)
    }
}

/// The engine's view of one fault kind. Concrete faults live in Faults/ and register here.
public protocol FaultRunner {
    var id: FaultID { get }
    /// Activate the fault. Must be idempotent-ish and always leave cleanup possible.
    func activate(_ context: FaultContext) async -> ActivationResult
    /// Restore any state this fault changed. Called on stop, duration end, and emergency stop.
    func restore(_ context: FaultContext) async -> Bool
}

/// Registry of all available fault runners. Populated at startup; testable with fakes.
public final class FaultRegistry: @unchecked Sendable {
    private var runners: [FaultID: FaultRunner] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(_ runner: FaultRunner) {
        lock.lock(); defer { lock.unlock() }
        runners[runner.id] = runner
    }

    public func runner(for id: FaultID) -> FaultRunner? {
        lock.lock(); defer { lock.unlock() }
        return runners[id]
    }

    public var registeredIDs: [FaultID] {
        lock.lock(); defer { lock.unlock() }
        return Array(runners.keys)
    }

    /// True when the engine has a real (non-guided) implementation for a fault id.
    public func canExecute(_ id: FaultID) -> Bool {
        runner(for: id) != nil
    }
}

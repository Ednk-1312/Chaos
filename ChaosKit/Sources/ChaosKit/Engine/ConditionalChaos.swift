import Foundation

/// Conditional Chaos: rules that inject a fault when an observable condition occurs.
///
/// Only triggers Chaos can genuinely observe are exposed:
/// - processExit: a target pid disappears from the process table
/// - processAppears: an executable name appears in the process table
/// - memoryPressureExceeds: the memory-pressure estimate crosses a percent threshold
/// - endpointDown: a host:port stops accepting connections (1s nc probe)
/// - faultActivated: another fault in this experiment began actively applying
///
/// No fake "request began" detection — that is not observable without app-side hooks.
public struct ChaosRule: Codable, Hashable, Identifiable, Sendable {
    public enum TriggerKind: String, Codable, CaseIterable, Sendable {
        case processExit, processAppears, memoryPressureExceeds, endpointDown, faultActivated
    }

    public var id: UUID
    public var trigger: TriggerKind
    public var subject: String          // pid, process name, percent threshold, host:port, fault rawValue
    public var actionFaultID: FaultID
    public var actionParameters: [String: String]
    public var actionDuration: TimeInterval
    public var startOffset: TimeInterval // earliest time the rule may fire (seconds into experiment)
    public var enabled: Bool
    public var label: String

    public init(id: UUID = UUID(), trigger: TriggerKind, subject: String,
                actionFaultID: FaultID, actionParameters: [String: String] = [:],
                actionDuration: TimeInterval = 30, startOffset: TimeInterval = 0,
                enabled: Bool = true, label: String? = nil) {
        self.id = id; self.trigger = trigger; self.subject = subject
        self.actionFaultID = actionFaultID; self.actionParameters = actionParameters
        self.actionDuration = actionDuration; self.startOffset = startOffset
        self.enabled = enabled
        self.label = label ?? "\(trigger.rawValue) \(subject) → \(actionFaultID.rawValue)"
    }
}

/// Runs alongside an experiment, polling observable conditions and injecting
/// bound faults when rules fire. Each rule fires at most once per experiment.
public final class RuleEngine: @unchecked Sendable {
    private let rules: [ChaosRule]
    private let grace: TimeInterval
    private let emit: (ExperimentEvent) -> Void
    private var firedRuleIDs: Set<UUID> = []
    private var injectedBindings: [FaultBinding] = []
    private let lock = NSLock()

    public init(rules: [ChaosRule], grace: TimeInterval = 2.0, emit: @escaping (ExperimentEvent) -> Void) {
        self.rules = rules.filter(\.enabled)
        self.grace = max(0.5, grace)
        self.emit = emit
    }

    public var injectedPlan: [FaultBinding] {
        lock.lock(); defer { lock.unlock() }
        return injectedBindings
    }

    /// One poll tick. Returns bindings to activate now (caller activates via the engine).
    public func evaluate(
        now: Date,
        experimentStartedAt: Date,
        targetPIDs: [Int32],
        activeFaults: [FaultID]
    ) -> [FaultBinding] {
        lock.lock(); defer { lock.unlock() }
        let now2 = Date()
        let elapsed = now2.timeIntervalSince(experimentStartedAt)

        // Observe
        let procs = ProcessScanner.snapshot()
        let alivePIDs = Set(procs.map(\.pid))
        let names = Set(procs.map(\.shortName))
        let pressure = ExperimentMonitor.memoryPressurePercent()

        var toInject: [FaultBinding] = []
        for rule in rules where !firedRuleIDs.contains(rule.id) && elapsed >= rule.startOffset {
            let conditionMet: Bool
            switch rule.trigger {
            case .processExit:
                if let pid = Int32(rule.subject) {
                    // Fired when a previously-seen pid is now gone.
                    if seenPIDs.contains(pid), !alivePIDs.contains(pid) {
                        conditionMet = true
                    } else {
                        seenPIDs.insert(pid)
                        conditionMet = false
                    }
                } else { conditionMet = false }
            case .processAppears:
                conditionMet = names.contains(rule.subject)
            case .memoryPressureExceeds:
                conditionMet = pressure >= (Double(rule.subject) ?? 90)
            case .endpointDown:
                if ExperimentMonitor.probe(host: rule.subject) == false {
                    conditionMet = true
                } else { conditionMet = false }
            case .faultActivated:
                conditionMet = activeFaults.contains { $0.rawValue == rule.subject }
            }

            if conditionMet {
                firedRuleIDs.insert(rule.id)
                let binding = FaultBinding(
                    faultID: rule.actionFaultID,
                    name: "Rule: \(rule.label)",
                    startOffset: elapsed,
                    duration: rule.actionDuration,
                    parameters: rule.actionParameters
                )
                injectedBindings.append(binding)
                toInject.append(binding)
                emit(ExperimentEvent(
                    kind: .info,
                    message: "Conditional rule fired: \(rule.label) — injecting \(FaultCatalog.descriptor(for: rule.actionFaultID)?.name ?? rule.actionFaultID.rawValue)."
                ))
            }
        }
        return toInject
    }

    var seenPIDs: Set<Int32> = []
}

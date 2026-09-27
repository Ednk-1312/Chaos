import Foundation

// MARK: - Targets

/// What an experiment acts on.
public struct TargetDescriptor: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable {
        case application, process, processGroup, directory, dependency, system
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var bundleID: String?
    public var path: String?
    public var pid: Int32?
    public var iconData: Data?
    public var isChaosLaunched: Bool

    public init(
        id: String = UUID().uuidString, kind: Kind, name: String,
        bundleID: String? = nil, path: String? = nil, pid: Int32? = nil,
        iconData: Data? = nil, isChaosLaunched: Bool = false
    ) {
        self.id = id; self.kind = kind; self.name = name
        self.bundleID = bundleID; self.path = path; self.pid = pid
        self.iconData = iconData; self.isChaosLaunched = isChaosLaunched
    }
}

// MARK: - Fault Configurations

/// A configured fault: which fault, with what parameters, starting when, lasting how long.
public struct FaultBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var faultID: FaultID
    public var name: String
    public var parameters: [String: String]
    public var startOffset: TimeInterval      // seconds into the experiment
    public var duration: TimeInterval         // 0 = for the whole experiment
    public var severity: Severity
    public var targetID: String?
    public var enabled: Bool

    public init(
        id: UUID = UUID(), faultID: FaultID, name: String? = nil,
        startOffset: TimeInterval = 0, duration: TimeInterval = 60,
        parameters: [String: String] = [:], severity: Severity? = nil, targetID: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.faultID = faultID
        self.name = name ?? FaultCatalog.descriptor(for: faultID)?.name ?? faultID.rawValue
        self.parameters = parameters
        self.startOffset = startOffset
        self.duration = duration
        self.severity = severity ?? FaultCatalog.descriptor(for: faultID)?.severity ?? .moderate
        self.targetID = targetID
        self.enabled = enabled
    }

    // Backward-compatible decoding: older persisted plans lack `enabled`.
    private enum CodingKeys: String, CodingKey {
        case id, faultID, name, parameters, startOffset, duration, severity, targetID, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        faultID = try c.decode(FaultID.self, forKey: .faultID)
        name = try c.decode(String.self, forKey: .name)
        parameters = try c.decode([String: String].self, forKey: .parameters)
        startOffset = try c.decode(TimeInterval.self, forKey: .startOffset)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        severity = try c.decode(Severity.self, forKey: .severity)
        targetID = try c.decodeIfPresent(String.self, forKey: .targetID)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

// MARK: - Scenarios

/// A reusable, named composition of faults. Shipped presets + user scenarios share this model.
public struct Scenario: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var category: String
    public var symbolName: String
    public var isBuiltin: Bool
    public var isExtreme: Bool
    public var bindings: [FaultBinding]
    public var purpose: String
    public var recommendedFor: [String]
    public var expectedBehavior: String
    public var safetyNote: String
    public var recommendedAssertions: [Assertion]

    public init(
        id: String = UUID().uuidString, name: String, category: String,
        summary: String, symbolName: String, isBuiltin: Bool = false,
        isExtreme: Bool = false, purpose: String = "", recommendedFor: [String] = [],
        expectedBehavior: String = "", safetyNote: String = "", bindings: [FaultBinding],
        recommendedAssertions: [Assertion] = []
    ) {
        self.id = id; self.name = name; self.category = category
        self.summary = summary; self.symbolName = symbolName
        self.isBuiltin = isBuiltin; self.isExtreme = isExtreme; self.bindings = bindings
        self.purpose = purpose; self.recommendedFor = recommendedFor
        self.expectedBehavior = expectedBehavior; self.safetyNote = safetyNote
        self.recommendedAssertions = recommendedAssertions
    }

    // Backward-compatible decoding: authored-quality fields were added post-release.
    private enum CodingKeys: String, CodingKey {
        case id, name, summary, category, symbolName, isBuiltin, isExtreme, bindings
        case purpose, recommendedFor, expectedBehavior, safetyNote, recommendedAssertions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decode(String.self, forKey: .summary)
        category = try c.decode(String.self, forKey: .category)
        symbolName = try c.decode(String.self, forKey: .symbolName)
        isBuiltin = try c.decode(Bool.self, forKey: .isBuiltin)
        isExtreme = try c.decode(Bool.self, forKey: .isExtreme)
        bindings = try c.decode([FaultBinding].self, forKey: .bindings)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        recommendedFor = try c.decodeIfPresent([String].self, forKey: .recommendedFor) ?? []
        expectedBehavior = try c.decodeIfPresent(String.self, forKey: .expectedBehavior) ?? ""
        safetyNote = try c.decodeIfPresent(String.self, forKey: .safetyNote) ?? ""
        recommendedAssertions = try c.decodeIfPresent([Assertion].self, forKey: .recommendedAssertions) ?? []
    }
}

// MARK: - Assertions

/// A user-defined expectation that Chaos can check from observable system state.
public struct Assertion: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable {
        case processAlive          // target stays alive for the whole experiment
        case processNotCrashed     // target did not die during the window
        case processResponds       // (best-effort) target did not hit watchdog-style death
        case fileExists            // a file exists at a path
        case fileCreated           // a file appears (created after experiment start)
        case fileRemoved           // a file is gone (or no longer exists) while observed
        case fileSizeChanged       // size at `subject` differs from baseline when observed
        case endpointReachable     // a TCP host:port accepts a connection
        case processAppeared       // a process with a name/bundle id is running
        case processDisappeared    // a process with a name/bundle id is not running
        case logContains           // (best-effort) unified log has an entry matching text
        case memoryPressureExceeded // system memory pressure crossed a threshold (percent 0-100)
    }

    public enum Outcome: String, Codable {
        case pending, passed, failed, skipped, inconclusive

        public var title: String { rawValue.capitalized }

        public var symbolName: String {
            switch self {
            case .pending: return "circle.dashed"
            case .passed: return "checkmark.circle.fill"
            case .failed: return "xmark.octagon.fill"
            case .skipped: return "minus.circle"
            case .inconclusive: return "questionmark.circle"
            }
        }
    }

    /// Evidence attached to an evaluated assertion: status, values, and explanation.
    public struct Evidence: Codable, Hashable, Sendable {
        public var observed: String
        public var expectedDescription: String
        public var explanation: String
        public var evaluatedAt: Date

        public init(observed: String, expectedDescription: String, explanation: String, evaluatedAt: Date = Date()) {
            self.observed = observed
            self.expectedDescription = expectedDescription
            self.explanation = explanation
            self.evaluatedAt = evaluatedAt
        }
    }

    public var id: UUID
    public var kind: Kind
    public var subject: String        // pid string, path, "host:port", bundle id, log subsystem…
    public var label: String
    public var expected: Bool         // false = assert the negative
    public var timeout: TimeInterval  // how long a failing condition may persist before failing
    public var baselineBytes: UInt64? // for fileSizeChanged: size captured at experiment start

    public init(id: UUID = UUID(), kind: Kind, subject: String, label: String? = nil,
                expected: Bool = true, timeout: TimeInterval = 5, baselineBytes: UInt64? = nil) {
        self.id = id; self.kind = kind; self.subject = subject
        self.label = label ?? "\(kind.rawValue) \(subject)"
        self.expected = expected
        self.timeout = timeout
        self.baselineBytes = baselineBytes
    }

    // Backward-compatible decoding (timeout/baseline added after the first release).
    private enum CodingKeys: String, CodingKey {
        case id, kind, subject, label, expected, timeout, baselineBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        subject = try c.decode(String.self, forKey: .subject)
        label = try c.decode(String.self, forKey: .label)
        expected = try c.decode(Bool.self, forKey: .expected)
        timeout = try c.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 5
        baselineBytes = try c.decodeIfPresent(UInt64.self, forKey: .baselineBytes)
    }

    /// Evaluate once against a snapshot. Liveness across time is the monitor's job.
    public func evaluate(_ state: AssertionContext) -> Outcome {
        let observed: Bool
        switch kind {
        case .processAlive, .processNotCrashed, .processResponds:
            guard let pid = Int32(subject) else { return .skipped }
            observed = state.alivePIDs.contains(pid)
        case .fileExists:
            observed = FileManager.default.fileExists(atPath: subject)
        case .fileCreated:
            observed = FileManager.default.fileExists(atPath: subject)
        case .fileRemoved:
            observed = !FileManager.default.fileExists(atPath: subject)
        case .fileSizeChanged:
            let attrs = try? FileManager.default.attributesOfItem(atPath: subject)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            observed = size != (baselineBytes ?? 0)
        case .endpointReachable:
            observed = state.reachableEndpoints.contains(subject)
        case .processAppeared:
            observed = state.runningNames.contains(subject)
        case .processDisappeared:
            observed = !state.runningNames.contains(subject)
        case .logContains:
            observed = state.logMatches.contains(subject)
        case .memoryPressureExceeded:
            observed = state.memoryPressurePercent >= (Double(subject) ?? 90)
        }
        return observed == expected ? .passed : .failed
    }

    /// Human-readable evidence for the observed outcome.
    public func explain(_ state: AssertionContext, outcome: Outcome) -> Evidence {
        let observed: String
        let explanation: String
        switch kind {
        case .processAlive, .processNotCrashed, .processResponds:
            if let pid = Int32(subject) {
                observed = state.alivePIDs.contains(pid) ? "pid \(pid) is alive" : "pid \(pid) is not running"
                explanation = state.alivePIDs.contains(pid)
                    ? "The process was observed running when this assertion was evaluated."
                    : "Expected process \(subject) to be running, but it was absent from the process table."
            } else {
                observed = "no pid recorded"
                explanation = "No PID was captured for the target, so liveness could not be observed."
            }
        case .fileExists:
            observed = FileManager.default.fileExists(atPath: subject) ? "file exists" : "file missing"
            explanation = observed == "file exists" ? "File found at the expected path." : "No file exists at \(subject)."
        case .fileCreated:
            observed = FileManager.default.fileExists(atPath: subject) ? "file exists" : "file never appeared"
            explanation = "Watches for the file to be created at \(subject)."
        case .fileRemoved:
            observed = FileManager.default.fileExists(atPath: subject) ? "file still present" : "file removed"
            explanation = "Watches for the file at \(subject) to disappear."
        case .fileSizeChanged:
            let attrs = try? FileManager.default.attributesOfItem(atPath: subject)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            observed = "size \(size) bytes"
            explanation = "Baseline at experiment start was \(baselineBytes ?? 0) bytes."
        case .endpointReachable:
            observed = state.reachableEndpoints.contains(subject) ? "endpoint accepted a connection" : "connection refused or timed out"
            explanation = "TCP reachability of \(subject) sampled by the Chaos monitor."
        case .processAppeared:
            observed = state.runningNames.contains(subject) ? "process running" : "process not found"
            explanation = "Matches processes by executable name in the process table."
        case .processDisappeared:
            observed = state.runningNames.contains(subject) ? "process still running" : "process gone"
            explanation = "Expects the named process to no longer be present."
        case .logContains:
            observed = state.logMatches.contains(subject) ? "matching entry found" : "no matching entry"
            explanation = "Searches Chaos-visible event/log evidence for \(subject)."
        case .memoryPressureExceeded:
            observed = String(format: "%.0f%% pressure", state.memoryPressurePercent)
            explanation = "Threshold \(subject)% computed from free+purgeable memory."
        }
        let expectedDescription = expected ? "condition holds" : "condition must not hold"
        return Evidence(observed: observed, expectedDescription: expectedDescription, explanation: explanation)
    }
}

/// Observable state snapshot used to evaluate assertions.
public struct AssertionContext: Sendable {
    public var alivePIDs: Set<Int32>
    public var runningNames: Set<String>
    public var reachableEndpoints: Set<String>
    public var logMatches: Set<String>
    public var memoryPressurePercent: Double
    public init(
        alivePIDs: Set<Int32> = [], runningNames: Set<String> = [],
        reachableEndpoints: Set<String> = [], logMatches: Set<String> = [],
        memoryPressurePercent: Double = 0
    ) {
        self.alivePIDs = alivePIDs; self.runningNames = runningNames
        self.reachableEndpoints = reachableEndpoints; self.logMatches = logMatches
        self.memoryPressurePercent = memoryPressurePercent
    }
}

// MARK: - Experiment Configuration

/// The full, serializable definition of an experiment.
public struct ExperimentConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var seed: UInt64
    public var plannedDuration: TimeInterval
    public var bindings: [FaultBinding]
    public var targets: [TargetDescriptor]
    public var assertions: [Assertion]
    public var createdAt: Date
    public var notes: String
    public var safetyConfirmed: Bool
    public var rules: [ChaosRule]

    public init(
        id: UUID = UUID(), name: String, seed: UInt64? = nil,
        plannedDuration: TimeInterval, bindings: [FaultBinding],
        targets: [TargetDescriptor] = [], assertions: [Assertion] = [],
        createdAt: Date = Date(), notes: String = "", safetyConfirmed: Bool = false,
        rules: [ChaosRule] = []
    ) {
        self.id = id
        self.name = name
        self.seed = seed ?? UInt64.random(in: 0...(UInt64.max / 2))
        self.plannedDuration = plannedDuration
        self.bindings = bindings
        self.targets = targets
        self.assertions = assertions
        self.createdAt = createdAt
        self.notes = notes
        self.safetyConfirmed = safetyConfirmed
        self.rules = rules
    }

    // Backward-compatible decoding: rules were added after the first release.
    private enum CodingKeys: String, CodingKey {
        case id, name, seed, plannedDuration, bindings, targets, assertions
        case createdAt, notes, safetyConfirmed, rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        seed = try c.decode(UInt64.self, forKey: .seed)
        plannedDuration = try c.decode(TimeInterval.self, forKey: .plannedDuration)
        bindings = try c.decode([FaultBinding].self, forKey: .bindings)
        targets = try c.decode([TargetDescriptor].self, forKey: .targets)
        assertions = try c.decode([Assertion].self, forKey: .assertions)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        notes = try c.decode(String.self, forKey: .notes)
        safetyConfirmed = try c.decode(Bool.self, forKey: .safetyConfirmed)
        rules = try c.decodeIfPresent([ChaosRule].self, forKey: .rules) ?? []
    }

    /// Total planned duration including the longest fault window (min 5s tail).
    public var effectiveDuration: TimeInterval {
        let longest = bindings.map { $0.startOffset + $0.duration }.max() ?? 0
        return max(plannedDuration, longest) + 5
    }

    public var requiresPrivileges: Bool {
        bindings.contains { FaultCatalog.descriptor(for: $0.faultID)?.privileges != .none }
    }

    public var maxSeverity: Severity {
        bindings.map(\.severity).max() ?? .low
    }

    /// Derived config with replaced bindings (keeps identity and safety state).
    public func with(bindings newBindings: [FaultBinding]) -> ExperimentConfig {
        var copy = self
        copy.bindings = newBindings
        return copy
    }

    /// Derived config with rules attached.
    public func with(rules newRules: [ChaosRule]) -> ExperimentConfig {
        var copy = self
        copy.rules = newRules
        return copy
    }
}

// MARK: - Events & Records

public enum EventKind: String, Codable, Sendable {
    case experimentStarted, experimentEnded
    case faultScheduled, faultActivated, faultDeactivated
    case faultFailed, faultSkipped
    case restorationStarted, restorationCompleted, restorationFailed
    case targetLaunched, targetTerminated
    case assertionUpdated
    case emergencyStop
    case info, warning, error
    case safetyIntervention
    case targetEvent, systemEvent, recoveryObserved

    public var symbolName: String {
        switch self {
        case .experimentStarted: return "play.circle"
        case .experimentEnded: return "flag.checkered"
        case .faultScheduled: return "calendar.badge.clock"
        case .faultActivated: return "bolt.fill"
        case .faultDeactivated: return "bolt.slash"
        case .faultFailed: return "exclamationmark.triangle"
        case .faultSkipped: return "forward.end"
        case .restorationStarted: return "arrow.uturn.backward.circle"
        case .restorationCompleted: return "checkmark.seal"
        case .restorationFailed: return "exclamationmark.octagon"
        case .targetLaunched: return "app.badge"
        case .targetTerminated: return "app.dashed"
        case .assertionUpdated: return "checklist"
        case .emergencyStop: return "stop.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .safetyIntervention: return "shield.lefthalf.filled"
        case .targetEvent: return "app.gift"
        case .systemEvent: return "server.rack"
        case .recoveryObserved: return "heart.text.square"
        }
    }

    /// Coarse filter buckets for the live timeline.
    public var filterBucket: EventFilter {
        switch self {
        case .experimentStarted, .experimentEnded, .info, .faultScheduled: return .chaos
        case .faultActivated, .faultDeactivated, .faultFailed, .faultSkipped: return .faults
        case .targetEvent, .targetLaunched, .targetTerminated: return .target
        case .systemEvent: return .system
        case .assertionUpdated: return .assertions
        case .recoveryObserved: return .recovery
        case .warning, .error: return .warnings
        case .restorationStarted, .restorationCompleted, .restorationFailed,
             .safetyIntervention, .emergencyStop: return .safety
        }
    }
}

/// Timeline filters for the live view.
public enum EventFilter: String, CaseIterable, Codable, Sendable {
    case all, chaos, faults, target, system, assertions, recovery, warnings, safety

    public var title: String { rawValue.capitalized }
}

/// A single timestamped entry in the unified experiment timeline.
public struct ExperimentEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: EventKind
    public var message: String
    public var faultID: FaultID?
    public var detail: String?

    public init(id: UUID = UUID(), date: Date = Date(), kind: EventKind, message: String, faultID: FaultID? = nil, detail: String? = nil) {
        self.id = id; self.date = date; self.kind = kind
        self.message = message; self.faultID = faultID; self.detail = detail
    }
}

public enum ExperimentOutcome: String, Codable, Sendable {
    case running, passed, failed, warning, inconclusive, stopped, errored

    public var title: String {
        switch self {
        case .running: return "Running"
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .warning: return "Warning"
        case .inconclusive: return "Inconclusive"
        case .stopped: return "Stopped"
        case .errored: return "Errored"
        }
    }

    public var symbolName: String {
        switch self {
        case .running: return "bolt.badge.clock"
        case .passed: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .inconclusive: return "questionmark.diamond"
        case .stopped: return "stop.fill"
        case .errored: return "wifi.exclamationmark"
        }
    }
}

/// The persisted result of one experiment run.
public struct ExperimentRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var config: ExperimentConfig
    public var outcome: ExperimentOutcome
    public var startedAt: Date?
    public var endedAt: Date?
    public var events: [ExperimentEvent]
    public var assertionResults: [UUID: Assertion.Outcome]
    public var restorationStatus: [String: Bool]   // subsystem -> restored?
    public var interruptedByExit: Bool
    public var hostInfo: HostInfo?
    public var state: ExperimentState?             // rich lifecycle state (nil on old records)
    public var evidenceByAssertion: [UUID: Assertion.Evidence]

    public init(id: UUID = UUID(), config: ExperimentConfig, outcome: ExperimentOutcome = .running,
                startedAt: Date? = nil, endedAt: Date? = nil, events: [ExperimentEvent] = [],
                assertionResults: [UUID: Assertion.Outcome] = [:], restorationStatus: [String: Bool] = [:],
                interruptedByExit: Bool = false, hostInfo: HostInfo? = nil,
                state: ExperimentState? = nil, evidenceByAssertion: [UUID: Assertion.Evidence] = [:]) {
        self.id = id; self.config = config; self.outcome = outcome
        self.startedAt = startedAt; self.endedAt = endedAt
        self.events = events; self.assertionResults = assertionResults
        self.restorationStatus = restorationStatus
        self.interruptedByExit = interruptedByExit; self.hostInfo = hostInfo
        self.state = state; self.evidenceByAssertion = evidenceByAssertion
    }

    // Backward-compatible decoding: state + evidence were added post-release.
    private enum CodingKeys: String, CodingKey {
        case id, config, outcome, startedAt, endedAt, events, assertionResults
        case restorationStatus, interruptedByExit, hostInfo, state, evidenceByAssertion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        config = try c.decode(ExperimentConfig.self, forKey: .config)
        outcome = try c.decode(ExperimentOutcome.self, forKey: .outcome)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        events = try c.decode([ExperimentEvent].self, forKey: .events)
        // NOTE: Swift 6.4 toolchain bug — [UUID: Value] encodes as a legacy
        // two-element array and cannot decode at all. We always write string-keyed
        // dictionaries and decode tolerantly (skipping malformed/legacy forms).
        let rawResults = (try? c.decode([String: Assertion.Outcome].self, forKey: .assertionResults)) ?? [:]
        assertionResults = Self.convertUUIDKeyed(rawResults)
        restorationStatus = try c.decode([String: Bool].self, forKey: .restorationStatus)
        interruptedByExit = try c.decode(Bool.self, forKey: .interruptedByExit)
        hostInfo = try c.decodeIfPresent(HostInfo.self, forKey: .hostInfo)
        state = try c.decodeIfPresent(ExperimentState.self, forKey: .state)
        let rawEvidence = (try? c.decode([String: Assertion.Evidence].self, forKey: .evidenceByAssertion)) ?? [:]
        evidenceByAssertion = Self.convertUUIDKeyed(rawEvidence)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(config, forKey: .config)
        try c.encode(outcome, forKey: .outcome)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encode(events, forKey: .events)
        let resultsDict = Dictionary(uniqueKeysWithValues: assertionResults.map { ($0.key.uuidString, $0.value) })
        try c.encode(resultsDict, forKey: .assertionResults)
        try c.encode(restorationStatus, forKey: .restorationStatus)
        try c.encode(interruptedByExit, forKey: .interruptedByExit)
        try c.encodeIfPresent(hostInfo, forKey: .hostInfo)
        try c.encodeIfPresent(state, forKey: .state)
        let evidenceDict = Dictionary(uniqueKeysWithValues: evidenceByAssertion.map { ($0.key.uuidString, $0.value) })
        try c.encode(evidenceDict, forKey: .evidenceByAssertion)
    }

    public var duration: TimeInterval? {
        guard let s = startedAt else { return nil }
        return (endedAt ?? Date()).timeIntervalSince(s)
    }

    /// Workaround for the toolchain's [UUID: Value] JSON decoding bug.
    static func convertUUIDKeyed<V>(_ raw: [String: V]) -> [UUID: V] {
        var out: [UUID: V] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) { out[id] = value }
        }
        return out
    }

    /// Counts by assertion outcome, for scorecards and suite summaries.
    public var assertionSummary: (passed: Int, failed: Int, pending: Int, other: Int) {
        var passed = 0, failed = 0, pending = 0, other = 0
        for a in config.assertions {
            switch assertionResults[a.id] ?? .pending {
            case .passed: passed += 1
            case .failed: failed += 1
            case .pending: pending += 1
            default: other += 1
            }
        }
        return (passed, failed, pending, other)
    }
}

// MARK: - Experiment Lifecycle

/// Rich experiment lifecycle. `outcome` (on the record) is the assertion-derived result;
/// `ExperimentState` is the execution state machine.
public enum ExperimentState: String, Codable, Sendable {
    case draft, preparing, running, stopping, restoring
    case completed, failed, interrupted, restorationRequired, restored, inconclusive

    public var title: String {
        switch self {
        case .draft: return "Draft"
        case .preparing: return "Preparing"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .restoring: return "Restoring"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        case .restorationRequired: return "Restoration Required"
        case .restored: return "Restored"
        case .inconclusive: return "Inconclusive"
        }
    }

    public var isActive: Bool {
        switch self { case .preparing, .running, .stopping, .restoring: return true; default: return false }
    }

    /// Map execution state + assertion-derived outcome to a persisted state value.
    public static func derive(outcome: ExperimentOutcome, restorationOK: Bool, restorationEntries: [String: Bool]) -> ExperimentState {
        switch outcome {
        case .running: return .running
        case .passed: return restorationOK ? .completed : .restorationRequired
        case .failed: return restorationOK ? .failed : .restorationRequired
        case .warning: return restorationOK ? .completed : .restorationRequired
        case .inconclusive: return restorationOK ? .inconclusive : .restorationRequired
        case .stopped: return restorationOK ? .completed : .restorationRequired
        case .errored: return .interrupted
        }
    }
}

/// Compact per-experiment summary for suite scorecards and dashboards.
public struct ExperimentSummary: Codable, Hashable, Sendable {
    public var experimentID: UUID
    public var title: String
    public var outcome: ExperimentOutcome
    public var passedAssertions: Int
    public var failedAssertions: Int
    public var pendingAssertions: Int
    public var inconclusiveAssertions: Int
    public var duration: TimeInterval?
    public var seed: UInt64
    public var scenarioName: String?

    public init(record: ExperimentRecord, scenarioName: String? = nil) {
        self.experimentID = record.id
        self.title = record.config.name
        self.outcome = record.outcome
        let s = record.assertionSummary
        self.passedAssertions = s.passed
        self.failedAssertions = s.failed
        self.pendingAssertions = s.pending
        self.inconclusiveAssertions = s.other
        self.duration = record.duration
        self.seed = record.config.seed
        self.scenarioName = scenarioName ?? record.config.name
    }
}

// MARK: - Chaos Suites (Release Testing)

/// A named collection of scenario IDs run sequentially with per-run records.
public struct ChaosSuite: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var scenarioIDs: [String]
    public var createdAt: Date
    public var notes: String

    public init(id: UUID = UUID(), name: String, scenarioIDs: [String], createdAt: Date = Date(), notes: String = "") {
        self.id = id; self.name = name; self.scenarioIDs = scenarioIDs
        self.createdAt = createdAt; self.notes = notes
    }
}

public enum SuiteState: String, Codable, Sendable {
    case pending, running, passed, failed, inconclusive, skipped, stopped

    public var symbolName: String {
        switch self {
        case .pending: return "circle.dashed"
        case .running: return "bolt.badge.clock"
        case .passed: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .inconclusive: return "questionmark.diamond"
        case .skipped: return "forward.end"
        case .stopped: return "stop.fill"
        }
    }
}

/// One slot in a suite run.
public struct SuiteEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var scenarioID: String
    public var scenarioName: String
    public var state: SuiteState
    public var recordID: UUID?

    public init(id: UUID = UUID(), scenarioID: String, scenarioName: String,
                state: SuiteState = .pending, recordID: UUID? = nil) {
        self.id = id; self.scenarioID = scenarioID; self.scenarioName = scenarioName
        self.state = state; self.recordID = recordID
    }
}

/// A suite execution: sequence of experiments with live progress.
public struct SuiteRun: Codable, Identifiable, Sendable {
    public var id: UUID
    public var suiteID: UUID
    public var suiteName: String
    public var entries: [SuiteEntry]
    public var startedAt: Date?
    public var endedAt: Date?

    public init(id: UUID = UUID(), suiteID: UUID, suiteName: String, entries: [SuiteEntry],
                startedAt: Date? = nil, endedAt: Date? = nil) {
        self.id = id; self.suiteID = suiteID; self.suiteName = suiteName
        self.entries = entries; self.startedAt = startedAt; self.endedAt = endedAt
    }

    public var completedCount: Int { entries.filter { ![SuiteState.pending, .running].contains($0.state) }.count }
    public var passedCount: Int { entries.filter { $0.state == .passed }.count }
    public var failedCount: Int { entries.filter { $0.state == .failed }.count }
    public var pendingCount: Int { entries.filter { $0.state == .pending }.count }
}

// MARK: - Scenario → ExperimentConfig

extension Scenario {
    /// Build an experiment configuration from this scenario.
    public func makeConfig(
        seed: UInt64? = nil,
        targets: [TargetDescriptor] = [],
        assertions: [Assertion] = [],
        rules: [ChaosRule] = [],
        safetyConfirmed: Bool = true
    ) -> ExperimentConfig {
        ExperimentConfig(
            name: name,
            seed: seed,
            plannedDuration: bindings.map { $0.startOffset + $0.duration }.max() ?? 60,
            bindings: bindings,
            targets: targets,
            assertions: assertions.isEmpty ? recommendedAssertions : assertions,
            notes: summary,
            safetyConfirmed: safetyConfirmed,
            rules: rules
        )
    }
}

// MARK: - Host Info

public struct HostInfo: Codable, Hashable, Sendable {
    public var hostname: String
    public var macosVersion: String
    public var chipName: String
    public var physicalMemoryGB: Double
    public var chaosVersion: String

    public static func capture() -> HostInfo {
        let processInfo = Foundation.ProcessInfo.processInfo
        let version = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { buf -> String in
            let data = Data(buf.prefix(while: { $0 != 0 }))
            return String(data: data, encoding: .utf8) ?? "unknown"
        }
        return HostInfo(
            hostname: processInfo.hostName,
            macosVersion: version,
            chipName: machine,
            physicalMemoryGB: Double(processInfo.physicalMemory) / 1_000_000_000,
            chaosVersion: chaosKitVersion
        )
    }
}

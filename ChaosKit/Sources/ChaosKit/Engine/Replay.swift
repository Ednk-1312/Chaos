import Foundation

/// Reproducibility identity: everything needed to re-run an experiment exactly
/// (same scenario content, seed, timing, durations, parameters).
///
/// Note on determinism: replay re-executes the same plan and seed. System
/// scheduling is not deterministic, so timings can differ by fractions of a
/// second; we never claim bit-exact reproduction of system behavior.
public struct ReplayPlan: Codable, Hashable, Sendable {
    public var seed: UInt64
    public var name: String
    public var plannedDuration: TimeInterval
    public var bindings: [FaultBinding]
    public var targets: [TargetDescriptor]
    public var assertions: [Assertion]
    public var notes: String

    public init(config: ExperimentConfig) {
        self.seed = config.seed
        self.name = config.name
        self.plannedDuration = config.plannedDuration
        self.bindings = config.bindings
        self.targets = config.targets
        self.assertions = config.assertions
        self.notes = config.notes
    }

    public func makeConfig(safetyConfirmed: Bool = true) -> ExperimentConfig {
        ExperimentConfig(
            name: name,
            seed: seed,
            plannedDuration: plannedDuration,
            bindings: bindings,
            targets: targets,
            assertions: assertions,
            notes: notes,
            safetyConfirmed: safetyConfirmed
        )
    }

    public static let replayNotice =
        "Replay uses the same experiment plan and seed; system scheduling may introduce timing differences."
}

/// A saved, reusable experiment ("bug recipe"): target, faults, assertions.
/// Recipes are user scenarios in the PersistenceStore with recipe metadata.
public struct Recipe: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var purpose: String
    public var targetName: String?
    public var scenario: Scenario

    // Captured from the experiment the recipe reproduces (optional for
    // backward compatibility with recipes saved before these existed).
    public var seed: UInt64?
    public var targets: [TargetDescriptor]
    public var assertions: [Assertion]
    public var sourceExperimentID: UUID?

    public init(id: String = UUID().uuidString, name: String, purpose: String,
                targetName: String? = nil, scenario: Scenario) {
        self.id = id; self.name = name; self.purpose = purpose
        self.targetName = targetName; self.scenario = scenario
        self.seed = nil; self.targets = []; self.assertions = []
        self.sourceExperimentID = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, purpose, targetName, scenario
        case seed, targets, assertions, sourceExperimentID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        purpose = try c.decode(String.self, forKey: .purpose)
        targetName = try c.decodeIfPresent(String.self, forKey: .targetName)
        scenario = try c.decode(Scenario.self, forKey: .scenario)
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed)
        targets = try c.decodeIfPresent([TargetDescriptor].self, forKey: .targets) ?? []
        assertions = try c.decodeIfPresent([Assertion].self, forKey: .assertions) ?? []
        sourceExperimentID = try c.decodeIfPresent(UUID.self, forKey: .sourceExperimentID)
    }

    /// Build a runnable config that reproduces the recorded failure condition:
    /// same faults, same seed, same targets, same assertions.
    public func makeConfig(seed: UInt64? = nil, safetyConfirmed: Bool = true) -> ExperimentConfig {
        ExperimentConfig(
            name: name,
            seed: seed ?? self.seed,
            plannedDuration: scenario.bindings.map { $0.startOffset + $0.duration }.max() ?? 60,
            bindings: scenario.bindings,
            targets: targets,
            assertions: assertions,
            notes: purpose,
            safetyConfirmed: safetyConfirmed
        )
    }
}

extension Recipe {
    /// Capture a recorded experiment as a reusable recipe. This is the single
    /// construction used by the app's "Save as Bug Recipe" flow: the fault
    /// plan becomes the recipe's scenario, and the record's seed, targets,
    /// assertions, and identity are captured so replay reproduces the same
    /// failure condition.
    public init(reproducing record: ExperimentRecord, purpose: String) {
        let scenario = Scenario(
            name: record.config.name,
            category: "Recipes",
            summary: purpose.isEmpty ? "Saved from an experiment" : purpose,
            symbolName: "checklist",
            bindings: record.config.bindings
        )
        self.init(
            name: record.config.name,
            purpose: purpose,
            targetName: record.config.targets.first?.name,
            scenario: scenario
        )
        self.seed = record.config.seed
        self.targets = record.config.targets
        self.assertions = record.config.assertions
        self.sourceExperimentID = record.id
    }
}

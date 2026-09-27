import Foundation

/// Evaluates experiment assertions against live observations.
///
/// Semantics (deliberately simple and explainable):
/// - A raw **pass** is recorded immediately (the condition currently holds).
/// - A raw **fail** becomes a confirmed failure only after the condition has
///   held-bad for at least `max(grace, assertion.timeout)` seconds — a single
///   missed observation (e.g. one unlucky process-table sample) is not a verdict.
/// - A skip (unobservable, e.g. no PID known) is recorded immediately.
///
/// Observable honesty: only conditions Chaos can actually observe feed the
/// evaluator. If no target PID is known, liveness assertions are skipped with
/// an explanation rather than guessed.
public final class ExperimentMonitor: @unchecked Sendable {
    public let interval: TimeInterval
    public let grace: TimeInterval
    let onEvent: (ExperimentEvent) -> Void

    // Failure latches: when a condition first observed failing.
    var failingSince: [UUID: Date] = [:]
    let lock = NSLock()

    public init(interval: TimeInterval = 1.0, grace: TimeInterval = 3.0,
                onEvent: @escaping (ExperimentEvent) -> Void = { _ in }) {
        self.interval = max(0.2, interval)
        self.grace = max(0.5, grace)
        self.onEvent = onEvent
    }

    /// Clear all latches (between experiments / between evaluations in tests).
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        failingSince.removeAll()
    }

    /// One monitor tick: sample the system, evaluate every assertion,
    /// return the assertions whose recorded outcome changed.
    @discardableResult
    public func tick(
        record: ExperimentRecord,
        startedAt: Date,
        targets: [TargetDescriptor],
        priorResults: [UUID: Assertion.Outcome],
        evidenceOut: inout [UUID: Assertion.Evidence]
    ) -> [UUID: Assertion.Outcome] {
        lock.lock(); defer { lock.unlock() }
        let now = Date()

        // --- Observe ---
        let endpointSubjects = record.config.assertions
            .filter { $0.kind == .endpointReachable }
            .map(\.subject)
        let context = Self.observe(targets: targets, endpointSubjects: endpointSubjects)

        // Resolve the target PID once: explicit target pid wins; name-based
        // targets were already resolved inside observe().
        let targetPID: Int32? = targets.compactMap(\.pid).first

        var updates: [UUID: Assertion.Outcome] = [:]
        for assertion in record.config.assertions {
            let previous = priorResults[assertion.id] ?? .pending
            guard previous == .pending || previous == .skipped else { continue } // latched once decided

            let raw = rawOutcome(assertion, context: context, targetPID: targetPID)

            let decided: Assertion.Outcome
            switch raw {
            case .pending:
                decided = .pending
            case .skipped:
                decided = .skipped
            case .passed:
                decided = .passed
                failingSince[assertion.id] = nil
            case .failed:
                let since = failingSince[assertion.id] ?? now
                if failingSince[assertion.id] == nil { failingSince[assertion.id] = now }
                let bad = now.timeIntervalSince(since)
                decided = bad >= max(grace, assertion.timeout) ? .failed : .pending
            case .inconclusive:
                decided = .inconclusive
            }

            if decided != previous {
                updates[assertion.id] = decided
                evidenceOut[assertion.id] = assertion.explain(context, outcome: decided)
                if decided == .failed {
                    onEvent(ExperimentEvent(
                        kind: .assertionUpdated,
                        message: "Assertion failed: \(assertion.explain(context, outcome: .failed).explanation)",
                        faultID: nil,
                        detail: assertion.label
                    ))
                }
            }
        }
        return updates
    }

    // MARK: - Raw single-shot evaluation

    private func rawOutcome(_ assertion: Assertion, context: AssertionContext, targetPID: Int32?) -> Assertion.Outcome {
        switch assertion.kind {
        case .processAlive, .processNotCrashed, .processResponds:
            let pid = targetPID ?? Int32(assertion.subject)
            guard let pid else { return .skipped }
            let alive = context.alivePIDs.contains(pid)
            return alive == assertion.expected ? .passed : .failed
        case .fileExists, .fileCreated, .fileRemoved, .fileSizeChanged:
            return assertion.evaluate(context)
        case .endpointReachable:
            let reachable = context.reachableEndpoints.contains(assertion.subject)
            return reachable == assertion.expected ? .passed : .failed
        case .processAppeared, .processDisappeared, .logContains, .memoryPressureExceeded:
            return assertion.evaluate(context)
        }
    }

    // MARK: - Observation

    /// Build an assertion context from real, currently observable system state.
    public static func observe(targets: [TargetDescriptor] = [], endpointSubjects: [String] = []) -> AssertionContext {
        var context = AssertionContext()
        let procs = ProcessScanner.snapshot()
        context.alivePIDs = Set(procs.map(\.pid))
        context.runningNames = Set(procs.map(\.shortName))
        context.memoryPressurePercent = memoryPressurePercent()

        // Resolve a name-based target to its PID for liveness assertions.
        if let namedTarget = targets.first(where: { $0.pid == nil }) {
            if let match = procs.first(where: { $0.shortName == namedTarget.name }) {
                context.alivePIDs.insert(match.pid)
            }
        }

        for subject in endpointSubjects {
            if probe(host: subject) == true {
                context.reachableEndpoints.insert(subject)
            }
        }
        return context
    }

    /// Real memory-pressure percentage (0–100) from free+purgeable memory.
    /// Honest approximation, documented in the UI as such.
    public static func memoryPressurePercent() -> Double {
        let r = (try? Shell.sh("vm_stat")) ?? ShellResult(exitCode: 1, stdout: "", stderr: "")
        var pages: UInt64 = 0
        for line in r.stdout.split(separator: "\n") {
            let digits = line.filter { $0.isNumber }
            guard let n = UInt64(digits), !digits.isEmpty else { continue }
            if line.contains("Pages free") || line.contains("Pages speculative") || line.contains("Pages purgeable") {
                pages += n
            }
        }
        let freeBytes = Double(pages * 4096)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        let fraction = max(0, min(1, freeBytes / (total * 0.35)))
        return (1 - fraction) * 100
    }

    /// TCP reachability probe (`nc -z`, 1s connect timeout). Returns nil when the
    /// subject is not a parseable host:port.
    public static func probe(host: String) -> Bool? {
        let parts = host.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        let r = try? Shell.run("/usr/bin/nc", ["-z", "-G", "1", String(parts[0]), String(port)], timeout: 3)
        return r?.succeeded
    }
}

// MARK: - Batch evaluation (tests, final evaluation, CLI)

extension ExperimentMonitor {
    /// Evaluate a set of assertions once against an explicit context.
    /// No latching — this is a single-shot view (used by tests and offline tools).
    public static func evaluateAll(
        assertions: [Assertion],
        context: AssertionContext
    ) -> [UUID: Assertion.Outcome] {
        var out: [UUID: Assertion.Outcome] = [:]
        for a in assertions {
            out[a.id] = a.evaluate(context)
        }
        return out
    }
}

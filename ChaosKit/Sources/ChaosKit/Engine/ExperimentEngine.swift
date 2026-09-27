import Foundation

/// Supervises one experiment from config → live events → record.
/// All mutable engine state is guarded by stateLock; scheduled work uses a serial queue.
public final class ExperimentEngine: @unchecked Sendable {
    public static let shared = ExperimentEngine()

    // MARK: State

    public enum State: Sendable {
        case idle
        case running(config: ExperimentConfig, startedAt: Date)
        case restoring
    }

    private let stateLock = NSLock()
    private var _state: State = .idle
    private var currentRecord: ExperimentRecord?
    private var scheduledTasks: [DispatchWorkItem] = []
    private var activeFaults: [FaultID: (context: FaultContext, runner: FaultRunner)] = [:]
    private var restorationLedger: [String: Bool] = [:]
    private var workers: [pid_t] = []   // Chaos-owned stress worker PIDs
    private var completionWorkItem: DispatchWorkItem?   // tracked so replays don't collide
    private let queue = DispatchQueue(label: "com.chaosengineering.engine", qos: .userInitiated)
    private let registry: FaultRegistry?
    private let persistence: PersistenceStore
    private let monitor: ExperimentMonitor
    private var ruleEngine: RuleEngine?
    private var monitorTimer: DispatchSourceTimer?
    private var ruleTimer: DispatchSourceTimer?
    private var evidence: [UUID: Assertion.Evidence] = [:]

    /// Evidence for the most recent assertion evaluations (explanations for the UI).
    public var currentEvidence: [UUID: Assertion.Evidence] {
        stateLock.lock(); defer { stateLock.unlock() }
        return evidence
    }

    // Observers
    public var onEvent: (@Sendable (ExperimentEvent) -> Void)?
    public var onStateChange: (@Sendable (State) -> Void)?
    public var onRecordUpdate: (@Sendable (ExperimentRecord) -> Void)?

    public var checkpointDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chaos", isDirectory: true)
        .appendingPathComponent("Checkpoints", isDirectory: true)

    // MARK: Init

    /// Create an engine. `shared` uses the default registry and persistence store;
    /// tests inject fakes and temporary storage.
    public init(registry: FaultRegistry? = nil, persistence: PersistenceStore = .shared,
                monitor: ExperimentMonitor = ExperimentMonitor()) {
        self.registry = registry
        self.persistence = persistence
        self.monitor = monitor
        if let leftover = Self.readCheckpoint(in: checkpointDirectory) {
            orphanSweepFromCheckpoint(leftover)
        }
    }

    // MARK: Public API

    public var state: State {
        stateLock.lock(); defer { stateLock.unlock() }
        return _state
    }

    public func currentRecordSnapshot() -> ExperimentRecord? {
        stateLock.lock(); defer { stateLock.unlock() }
        return currentRecord
    }

    public func start(config: ExperimentConfig) throws -> ExperimentRecord {
        stateLock.lock()
        if case .running = _state {
            stateLock.unlock()
            throw ChaosError.experimentAlreadyRunning
        }
        stateLock.unlock()

        guard config.safetyConfirmed else { throw ChaosError.safetyNotConfirmed }

        // Expand Random Chaos bindings into a deterministic, seeded fault plan.
        var bindings = config.bindings
        for binding in config.bindings where binding.faultID == .randomChaos {
            let categories: [FaultCategory]
            if let csv = binding.parameters["categories"], !csv.isEmpty {
                categories = csv.split(separator: ",").compactMap { FaultCategory(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
            } else {
                categories = Array(FaultCategory.allCases.dropLast()) // all real categories
            }
            let plan = RandomChaosPlanner.plan(
                seed: config.seed,
                duration: binding.duration > 0 ? binding.duration : config.effectiveDuration,
                allowedCategories: categories,
                maxSeverity: config.maxSeverity
            )
            bindings.removeAll { $0.id == binding.id }
            bindings.append(contentsOf: plan.bindings)
        }
        guard !bindings.isEmpty else { throw ChaosError.noFaultsSelected }
        let effectiveConfig = config.with(bindings: bindings)

        let startedAt = Date()
        var record = ExperimentRecord(config: effectiveConfig, outcome: .running, startedAt: startedAt)
        record.hostInfo = HostInfo.capture()

        stateLock.lock()
        currentRecord = record
        restorationLedger = [:]
        workers = []
        activeFaults = [:]
        evidence = [:]
        stateLock.unlock()
        monitor.reset()

        try? FileManager.default.createDirectory(at: checkpointDirectory, withIntermediateDirectories: true)
        setState(.running(config: effectiveConfig, startedAt: startedAt))
        emit(ExperimentEvent(
            kind: .experimentStarted,
            message: "Experiment '\(effectiveConfig.name)' started — \(effectiveConfig.bindings.count) fault(s), seed \(effectiveConfig.seed), planned \(effectiveConfig.effectiveDuration.asClockString)."
        ))
        writeCheckpoint()

        for binding in effectiveConfig.bindings.sorted(by: { $0.startOffset < $1.startOffset }) {
            guard binding.enabled else {
                emit(ExperimentEvent(kind: .faultSkipped,
                                     message: "\(binding.name) is disabled and will not run.",
                                     faultID: binding.faultID))
                continue
            }
            let task = DispatchWorkItem { [weak self] in self?.activate(binding: binding) }
            queue.asyncAfter(deadline: .now() + binding.startOffset, execute: task)
            stateLock.lock()
            scheduledTasks.append(task)
            stateLock.unlock()
            emit(ExperimentEvent(
                kind: .faultScheduled,
                message: "\(binding.name) → at \(Int(binding.startOffset))s, for \(Int(binding.duration))s.",
                faultID: binding.faultID
            ))
        }

        // Cancel any previous completion timer, then schedule this experiment's end.
        stateLock.lock()
        completionWorkItem?.cancel()
        let completion = DispatchWorkItem { [weak self] in
            self?.finish(reason: .completed)
        }
        completionWorkItem = completion
        stateLock.unlock()
        queue.asyncAfter(deadline: .now() + effectiveConfig.effectiveDuration, execute: completion)

        // Conditional Chaos rule engine.
        if !effectiveConfig.rules.isEmpty {
            let ruleEngine = RuleEngine(rules: effectiveConfig.rules) { [weak self] event in
                self?.emit(event)
            }
            self.ruleEngine = ruleEngine
            startRulePolling(config: effectiveConfig, startedAt: startedAt)
        }

        // Start the assertion monitor loop.
        startMonitorLoop(config: effectiveConfig, startedAt: startedAt)

        return record
    }

    // MARK: Monitor + rule loops

    private func startMonitorLoop(config: ExperimentConfig, startedAt: Date) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + monitor.interval, repeating: monitor.interval)
        timer.setEventHandler { [weak self] in
            guard let self, case .running = self.state else { return }
            self.runMonitorTick(config: config, startedAt: startedAt)
        }
        timer.resume()
        stateLock.lock()
        monitorTimer?.cancel()
        monitorTimer = timer
        stateLock.unlock()
    }

    private func runMonitorTick(config: ExperimentConfig, startedAt: Date) {
        guard let record = liveSnapshot else { return }
        let prior = record.assertionResults
        var ev = currentEvidence
        let updates = monitor.tick(
            record: record,
            startedAt: startedAt,
            targets: config.targets,
            priorResults: prior,
            evidenceOut: &ev
        )
        guard !updates.isEmpty else { return }

        stateLock.lock()
        evidence.merge(ev) { _, new in new }
        stateLock.unlock()

        stateLock.lock()
        currentRecord?.assertionResults.merge(updates) { _, new in new }
        let snapshot = currentRecord
        stateLock.unlock()
        for (id, outcome) in updates where outcome != .pending {
            emit(ExperimentEvent(kind: .assertionUpdated,
                                 message: "Assertion \(outcome.title): \(config.assertions.first { $0.id == id }?.label ?? id.uuidString)",
                                 detail: outcome.rawValue))
        }
        if let snapshot { onRecordUpdate?(snapshot) }
    }

    private func startRulePolling(config: ExperimentConfig, startedAt: Date) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self, case .running = self.state else { return }
            let bindings = self.ruleEngine?.evaluate(
                now: Date(),
                experimentStartedAt: startedAt,
                targetPIDs: config.targets.compactMap(\.pid),
                activeFaults: Array(self.activeFaultIDs)
            ) ?? []
            for binding in bindings {
                self.activate(binding: binding)
            }
        }
        timer.resume()
        stateLock.lock()
        ruleTimer?.cancel()
        ruleTimer = timer
        stateLock.unlock()
    }

    public var activeFaultIDs: [FaultID] {
        stateLock.lock(); defer { stateLock.unlock() }
        return Array(activeFaults.keys)
    }

    public enum StopReason: Sendable { case completed, userStop, emergencyStop }

    public func stop(reason: StopReason = .userStop) {
        finish(reason: reason)
    }

    // MARK: Activation

    private func activate(binding: FaultBinding) {
        guard case .running(let config, _) = state else { return }
        guard let runner = registry?.runner(for: binding.faultID)
                ?? DefaultFaultRegistry.runner(for: binding.faultID) else {
            emit(ExperimentEvent(
                kind: .faultSkipped,
                message: "\(binding.name): no runnable implementation — macOS restriction; see the fault's guided alternative.",
                faultID: binding.faultID
            ))
            return
        }

        let context = FaultContext(
            config: config, binding: binding, seed: config.seed,
            workingDirectory: checkpointDirectory.deletingLastPathComponent(),
            emit: { [weak self] event in self?.emit(event) }
        )

        emit(ExperimentEvent(kind: .faultActivated, message: "\(binding.name) activating…", faultID: binding.faultID))
        stateLock.lock()
        restorationLedger[binding.faultID.rawValue] = false
        stateLock.unlock()

        Task.detached { [weak self] in
            guard let self else { return }
            let result = await runner.activate(context)
            self.stateLock.lock()
            if result.ok {
                self.activeFaults[binding.faultID] = (context, runner)
            } else {
                self.restorationLedger[binding.faultID.rawValue] = nil
            }
            let workers = self.workers
            self.stateLock.unlock()

            self.emit(ExperimentEvent(
                kind: result.ok ? .info : .faultFailed,
                message: "\(binding.name): \(result.message)",
                faultID: binding.faultID
            ))
            if result.ok {
                self.writeCheckpoint(activeFaultIDs: [binding.faultID.rawValue], workerPIDs: workers)
            }

            // Schedule restoration at binding end.
            let end = context.binding.duration
            self.queue.asyncAfter(deadline: .now() + end) { [weak self] in
                self?.deactivate(faultID: binding.faultID)
            }
        }
    }

    private func deactivate(faultID: FaultID) {
        stateLock.lock()
        let entry = activeFaults[faultID]
        activeFaults[faultID] = nil
        stateLock.unlock()
        guard let (context, runner) = entry else { return }

        Task.detached { [weak self] in
            let ok = await runner.restore(context)
            self?.recordRestoration(faultID: faultID, ok: ok)
            self?.writeCheckpoint()
        }
    }

    // MARK: Finish & Restore

    private func finish(reason: StopReason) {
        guard case .running = state else { return }
        if reason == .emergencyStop {
            emit(ExperimentEvent(kind: .emergencyStop, message: "EMERGENCY STOP engaged — restoring all state."))
        }

        stateLock.lock()
        let entries = activeFaults
        let scheduled = scheduledTasks
        activeFaults = [:]
        scheduledTasks = []
        stateLock.unlock()
        let workerPIDs = StressWorkerSupervisor.shared.workerPIDs

        completionWorkItem?.cancel()
        completionWorkItem = nil
        stateLock.lock()
        monitorTimer?.cancel(); monitorTimer = nil
        ruleTimer?.cancel(); ruleTimer = nil
        ruleEngine = nil
        stateLock.unlock()

        setState(.restoring)
        emit(ExperimentEvent(kind: .restorationStarted, message: "Restoring system state…"))

        for task in scheduled { task.cancel() }

        // Kill Chaos-owned stress workers immediately, then verify.
        for pid in workerPIDs { kill(pid, SIGKILL) }
        _ = StressWorkerSupervisor.shared.stopAll()
        let deadWorkers = workerPIDs.allSatisfy { !ProcessScanner.isAlive($0) }
        stateLock.lock()
        restorationLedger["stress.workers"] = deadWorkers
        stateLock.unlock()
        if !workerPIDs.isEmpty {
            emit(ExperimentEvent(
                kind: deadWorkers ? .restorationCompleted : .restorationFailed,
                message: deadWorkers ? "Stress workers terminated and verified." : "Some stress workers refused to die — check Activity Monitor.",
                faultID: .cpuLoad
            ))
        }

        // Restore every still-active fault.
        let group = DispatchGroup()
        for (faultID, entry) in entries {
            group.enter()
            Task.detached { [weak self] in
                let ok = await entry.runner.restore(entry.context)
                self?.recordRestoration(faultID: faultID, ok: ok)
                group.leave()
            }
        }
        group.notify(queue: queue) { [weak self] in
            guard let self else { return }
            self.completeRecord(reason: reason)
        }
    }

    private func completeRecord(reason: StopReason) {
        stateLock.lock()
        let record = currentRecord
        let ledger = restorationLedger
        let ev = evidence
        stateLock.unlock()

        guard var rec = record else { return }
        rec.endedAt = Date()
        rec.restorationStatus = ledger
        rec.evidenceByAssertion = ev
        rec.outcome = Self.outcomeFor(record: rec, reason: reason)
        let restorationOK = !ledger.values.isEmpty && ledger.values.allSatisfy { $0 }
        rec.state = ExperimentState.derive(
            outcome: rec.outcome,
            restorationOK: restorationOK || ledger.isEmpty,
            restorationEntries: ledger
        )

        stateLock.lock()
        currentRecord = rec
        let snapshot = rec
        _state = .idle
        stateLock.unlock()

        persistence.save(record: snapshot)
        Self.deleteCheckpoint(in: checkpointDirectory)
        onRecordUpdate?(snapshot)
        emit(ExperimentEvent(kind: .experimentEnded,
                             message: "Experiment \(rec.outcome.title.lowercased()) after \(rec.duration?.asClockString ?? "?")."))
        setState(.idle)
    }

    static func outcomeFor(record: ExperimentRecord, reason: StopReason) -> ExperimentOutcome {
        if record.config.assertions.isEmpty {
            return reason == .completed ? .inconclusive : .stopped
        }
        let outcomes = record.config.assertions.compactMap { record.assertionResults[$0.id] }
        if outcomes.contains(.failed) { return .failed }
        if outcomes.allSatisfy({ $0 == .passed }) && !outcomes.isEmpty { return .passed }
        return .warning
    }

    private func recordRestoration(faultID: FaultID, ok: Bool) {
        stateLock.lock()
        restorationLedger[faultID.rawValue] = ok
        stateLock.unlock()
        emit(ExperimentEvent(
            kind: ok ? .restorationCompleted : .restorationFailed,
            message: "\(FaultCatalog.descriptor(for: faultID)?.name ?? faultID.rawValue) restoration \(ok ? "verified" : "FAILED").",
            faultID: faultID
        ))
    }

    // MARK: Checkpoint (crash safety)

    struct Checkpoint: Codable {
        var experimentID: UUID
        var startedAt: Date
        var activeFaultIDs: [String]
        var workerPIDs: [pid_t]
    }

    func writeCheckpoint(activeFaultIDs: [String]? = nil, workerPIDs: [pid_t]? = nil) {
        stateLock.lock()
        let record = currentRecord
        let faults = activeFaultIDs ?? Array(activeFaults.keys.map(\.rawValue))
        let pids = workerPIDs ?? workers
        stateLock.unlock()

        guard let record else { return }
        let cp = Checkpoint(experimentID: record.id, startedAt: record.startedAt ?? Date(),
                            activeFaultIDs: faults, workerPIDs: pids)
        if let data = try? JSONEncoder().encode(cp) {
            try? data.write(to: checkpointDirectory.appendingPathComponent("checkpoint.json"), options: .atomic)
        }
    }

    static func readCheckpoint(in dir: URL) -> Checkpoint? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("checkpoint.json")) else { return nil }
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }

    static func deleteCheckpoint(in dir: URL) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("checkpoint.json"))
    }

    /// On launch: kill orphaned stress workers, reset network state from a dead run.
    func orphanSweepFromCheckpoint(_ cp: Checkpoint) {
        for pid in cp.workerPIDs where ProcessScanner.isAlive(pid) {
            kill(pid, SIGKILL)
        }
        if !cp.activeFaultIDs.isEmpty {
            FaultCleanup.performBootSweep()
        }
        Self.deleteCheckpoint(in: checkpointDirectory)
        emit(ExperimentEvent(
            kind: .safetyIntervention,
            message: "Recovered from an interrupted session: \(cp.activeFaultIDs.count) fault(s) cleaned up, \(cp.workerPIDs.count) worker(s) killed."
        ))
    }

    // MARK: Plumbing

    private func setState(_ s: State) {
        stateLock.lock()
        _state = s
        stateLock.unlock()
        onStateChange?(s)
    }

    func emit(_ event: ExperimentEvent) {
        stateLock.lock()
        currentRecord?.events.append(event)
        let snapshot = currentRecord
        stateLock.unlock()
        onEvent?(event)
        if let snapshot { onRecordUpdate?(snapshot) }
    }

    /// Snapshot used by live UI and the CLI status command.
    public var liveSnapshot: ExperimentRecord? {
        stateLock.lock(); defer { stateLock.unlock() }
        return currentRecord
    }
}

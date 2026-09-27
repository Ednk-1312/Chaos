import Foundation

/// Runs a ChaosSuite: each scenario is executed sequentially through the shared
/// engine (never concurrently), each experiment fully restored before the next.
/// Tracks live SuiteRun progress and persists it after every state change.
public final class SuiteRunner: @unchecked Sendable {
    public static let shared = SuiteRunner()

    private let lock = NSLock()
    private var currentRun: SuiteRun?
    private var currentIndex = 0
    private weak var engine: ExperimentEngine?
    private let persistence: PersistenceStore

    public var onRunUpdate: (@Sendable (SuiteRun) -> Void)?

    public init(engine: ExperimentEngine = .shared, persistence: PersistenceStore = .shared) {
        self.engine = engine
        self.persistence = persistence
    }

    public var activeRun: SuiteRun? {
        lock.lock(); defer { lock.unlock() }
        return currentRun
    }

    public var isRunning: Bool { activeRun != nil }

    // MARK: Control

    /// Begin running a suite. Returns nil when another suite is already running.
    @discardableResult
    public func start(suite: ChaosSuite) -> SuiteRun? {
        lock.lock(); defer { lock.unlock() }
        guard currentRun == nil else { return nil }

        let entries = suite.scenarioIDs.map { id in
            SuiteEntry(
                scenarioID: id,
                scenarioName: ScenarioLibrary.scenario(id: id)?.name
                    ?? PersistenceStore.shared.loadUserScenarios().first { $0.id == id }?.name
                    ?? id
            )
        }
        let run = SuiteRun(suiteID: suite.id, suiteName: suite.name, entries: entries,
                           startedAt: Date())
        currentRun = run
        currentIndex = 0
        persistLocked(run)
        Task { await self.runNext() }
        return run
    }

    public func stop() {
        let run = activeRun
        engine?.stop(reason: .userStop)
        if let run {
            // Mark remaining entries as stopped.
            lock.lock()
            var updated = run
            for i in currentIndex..<updated.entries.count where updated.entries[i].state == .pending {
                updated.entries[i].state = .stopped
            }
            updated.endedAt = Date()
            currentRun = updated
            persistLocked(updated)
            currentRun = nil
            lock.unlock()
            onRunUpdate?(updated)
        }
    }

    /// Rerun only the failed/inconclusive entries of the last run.
    public func rerunFailed() {
        guard let last = loadLastRun(), currentRun == nil else { return }
        let failedScenarios = last.entries
            .filter { $0.state == .failed || $0.state == .inconclusive }
            .map(\.scenarioID)
        guard !failedScenarios.isEmpty,
              let suite = persistence.loadSuites().first(where: { $0.id == last.suiteID }) else { return }
        var rerunSuite = suite
        rerunSuite.scenarioIDs = failedScenarios
        start(suite: rerunSuite)
    }

    // MARK: Sequential execution

    private func runNext() async {
        guard let run = activeRun else { return }
        let idx = currentIndex
        guard idx < run.entries.count else {
            finishRun()
            return
        }

        let entry = run.entries[idx]
        guard let scenario = ScenarioLibrary.scenario(id: entry.scenarioID)
                ?? persistence.loadUserScenarios().first(where: { $0.id == entry.scenarioID }) else {
            markEntry(idx: idx, state: .skipped, recordID: nil)
            await runNext()
            return
        }

        markEntry(idx: idx, state: .running, recordID: nil)

        guard let engine else {
            markEntry(idx: idx, state: .inconclusive, recordID: nil)
            await runNext()
            return
        }

        // Observe this experiment's completion via onStateChange; the AppModel-level
        // engine observer remains separate (SuiteRunner installs its own here).
        let sema = DispatchSemaphore(value: 0)
        let box = RecordBox()
        let observer = { (record: ExperimentRecord) in
            if record.outcome != .running { box.record = record }
        }
        let prevHandler = engine.onRecordUpdate
        engine.onRecordUpdate = { record in
            prevHandler?(record)
            observer(record)
        }

        var config = scenario.makeConfig()
        config.safetyConfirmed = true // suites are explicit user actions
        do {
            _ = try engine.start(config: config)
        } catch {
            markEntry(idx: idx, state: .skipped, recordID: nil)
            await runNext()
            return
        }

        DispatchQueue.global().async {
            _ = sema.wait(timeout: .now() + config.effectiveDuration + 120)
            Task { await self.entryFinished(idx: idx, record: box.record) }
        }
        _ = sema
    }

    private func entryFinished(idx: Int, record: ExperimentRecord?) {
        let state: SuiteState
        switch record?.outcome {
        case .passed: state = .passed
        case .failed: state = .failed
        case .warning: state = .inconclusive
        case .inconclusive: state = .inconclusive
        case .stopped: state = .stopped
        default: state = .inconclusive
        }
        markEntry(idx: idx, state: state, recordID: record?.id)
        Task { await self.runNext() }
    }

    private func finishRun() {
        lock.lock()
        var run = currentRun
        run?.endedAt = Date()
        if let run { persistLocked(run) }
        currentRun = nil
        lock.unlock()
        if let run { onRunUpdate?(run) }
    }

    private func markEntry(idx: Int, state: SuiteState, recordID: UUID?) {
        lock.lock()
        guard var run = currentRun, idx < run.entries.count else {
            lock.unlock(); return
        }
        run.entries[idx].state = state
        run.entries[idx].recordID = recordID
        currentRun = run
        persistLocked(run)
        lock.unlock()
        onRunUpdate?(run)
    }

    private func persistLocked(_ run: SuiteRun) {
        persistence.save(suiteRun: run)
    }

    private func loadLastRun() -> SuiteRun? {
        persistence.loadSuiteRuns().first
    }
}

/// Thread-safe record box for completion observers (suite runner, CLI, tests).
public final class RecordBox: @unchecked Sendable {
    public var record: ExperimentRecord?
    public init() {}
}

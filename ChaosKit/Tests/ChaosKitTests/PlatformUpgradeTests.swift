import XCTest
@testable import ChaosKit

final class PlatformUpgradeTests: XCTestCase {
    var store: PersistenceStore!

    override func setUp() {
        super.setUp()
        store = PersistenceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("chaos-upgrade-\(UUID().uuidString)", isDirectory: true)
        )
    }

    // MARK: Monitor

    func testMonitorFailingLatchRespectsGrace() {
        let monitor = ExperimentMonitor(grace: 10)
        let assertion = Assertion(kind: .processAlive, subject: "999999", timeout: 5)
        let record = ExperimentRecord(config: ExperimentConfig(
            name: "t", plannedDuration: 60,
            bindings: [FaultBinding(faultID: .cpuLoad)], assertions: [assertion]
        ))

        var evidence: [UUID: Assertion.Evidence] = [:]
        let updates1 = monitor.tick(record: record, startedAt: Date(), targets: [],
                                    priorResults: [:], evidenceOut: &evidence)
        XCTAssertNotEqual(updates1[assertion.id], .failed, "a fresh failure within grace must not latch as failed")

        // Simulate the latch having been set long ago.
        monitor.lock.lock()
        monitor.failingSince[assertion.id] = Date().addingTimeInterval(-30)
        monitor.lock.unlock()
        let updates2 = monitor.tick(record: record, startedAt: Date(), targets: [],
                                    priorResults: [:], evidenceOut: &evidence)
        XCTAssertEqual(updates2[assertion.id], .failed, "failure held beyond grace must latch as failed")
        XCTAssertNotNil(evidence[assertion.id], "failure must produce explainable evidence")
    }

    func testMonitorSkipsLivenessWithoutPID() {
        let monitor = ExperimentMonitor(grace: 1)
        let assertion = Assertion(kind: .processAlive, subject: "not-a-pid")
        let record = ExperimentRecord(config: ExperimentConfig(
            name: "t", plannedDuration: 10,
            bindings: [FaultBinding(faultID: .cpuLoad)], assertions: [assertion]
        ))
        var evidence: [UUID: Assertion.Evidence] = [:]
        let updates = monitor.tick(record: record, startedAt: Date(), targets: [],
                                   priorResults: [:], evidenceOut: &evidence)
        XCTAssertEqual(updates[assertion.id], .skipped)
        XCTAssertTrue(evidence[assertion.id]?.explanation.contains("PID") ?? false)
    }

    func testMonitorDecidedAssertionsAreNotReevaluated() {
        let monitor = ExperimentMonitor(grace: 1)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let assertion = Assertion(kind: .processAlive, subject: "\(ownPID)")
        let record = ExperimentRecord(config: ExperimentConfig(
            name: "t", plannedDuration: 10,
            bindings: [FaultBinding(faultID: .cpuLoad)], assertions: [assertion]
        ))
        var evidence: [UUID: Assertion.Evidence] = [:]
        let first = monitor.tick(record: record, startedAt: Date(), targets: [],
                                 priorResults: [:], evidenceOut: &evidence)
        XCTAssertEqual(first[assertion.id], Assertion.Outcome.passed)
        let second = monitor.tick(record: record, startedAt: Date(), targets: [],
                                  priorResults: first, evidenceOut: &evidence)
        XCTAssertNil(second[assertion.id], "a decided assertion must stay latched")
    }

    func testMemoryPressurePercentIsBounded() {
        let p = ExperimentMonitor.memoryPressurePercent()
        XCTAssertTrue((0...100).contains(p), "pressure must be a percentage, got \(p)")
    }

    func testProbeRejectsNonEndpointSubjects() {
        XCTAssertNil(ExperimentMonitor.probe(host: "not-a-host-port"))
        XCTAssertNil(ExperimentMonitor.probe(host: "localhost"))
    }

    // MARK: Rules

    func testRuleEngineFiresFaultActivatedTriggerOnce() {
        var events: [ExperimentEvent] = []
        let engine = RuleEngine(rules: [
            ChaosRule(trigger: .faultActivated, subject: "cpu.load",
                      actionFaultID: .networkLatency, actionParameters: ["latencyMs": "100"],
                      actionDuration: 5)
        ], emit: { events.append($0) })

        let startedAt = Date()
        let none = engine.evaluate(now: Date(), experimentStartedAt: startedAt,
                                   targetPIDs: [], activeFaults: [])
        XCTAssertTrue(none.isEmpty)

        let fired = engine.evaluate(now: Date(), experimentStartedAt: startedAt,
                                    targetPIDs: [], activeFaults: [.cpuLoad])
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.faultID, .networkLatency)

        let again = engine.evaluate(now: Date(), experimentStartedAt: startedAt,
                                    targetPIDs: [], activeFaults: [.cpuLoad])
        XCTAssertTrue(again.isEmpty, "a rule must fire at most once")
        XCTAssertFalse(events.isEmpty)
    }

    func testRuleEngineRespectsStartOffsetAndDisabled() {
        let engine = RuleEngine(rules: [
            ChaosRule(trigger: .processAppears, subject: "anything",
                      actionFaultID: .cpuLoad, startOffset: 3600, enabled: false)
        ], emit: { _ in })
        let fired = engine.evaluate(now: Date(), experimentStartedAt: Date(),
                                    targetPIDs: [], activeFaults: [])
        XCTAssertTrue(fired.isEmpty)
    }

    // MARK: Replay & recipes

    func testReplayPlanPreservesIdentity() {
        let config = ScenarioLibrary.scenario(id: "terrible-wifi")!.makeConfig(seed: 842913)
        let plan = ReplayPlan(config: config)
        XCTAssertEqual(plan.seed, 842913)
        XCTAssertEqual(plan.bindings.count, config.bindings.count)
        let rebuilt = plan.makeConfig()
        XCTAssertEqual(rebuilt.seed, config.seed)
        XCTAssertEqual(rebuilt.bindings, config.bindings)
        XCTAssertEqual(ReplayPlan.replayNotice.contains("scheduling"), true)
    }

    func testRecipeRoundTrip() {
        let recipe = Recipe(name: "Sync Crash", purpose: "Reproduce sync crash on bad network",
                            scenario: ScenarioLibrary.scenario(id: "terrible-wifi")!)
        store.save(recipe: recipe)
        let loaded = store.loadRecipes()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Sync Crash")
        store.deleteRecipe(id: recipe.id)
        XCTAssertTrue(store.loadRecipes().isEmpty)
    }

    // MARK: Suites

    func testSuitePersistenceRoundTrip() {
        let suite = ChaosSuite(name: "MyApp 4.2 Release", scenarioIDs: ["airplane-mode", "memory-moderate"])
        store.save(suite: suite)
        let loaded = store.loadSuites()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.scenarioIDs.count, 2)

        var run = SuiteRun(suiteID: suite.id, suiteName: suite.name,
                           entries: suite.scenarioIDs.map { SuiteEntry(scenarioID: $0, scenarioName: $0) })
        run.entries[0].state = .passed
        run.entries[1].state = .failed
        store.save(suiteRun: run)
        let runs = store.loadSuiteRuns()
        XCTAssertEqual(runs.first?.passedCount, 1)
        XCTAssertEqual(runs.first?.failedCount, 1)
        XCTAssertEqual(runs.first?.completedCount, 2)
    }

    // MARK: State derivation & summaries

    func testExperimentStateDerivation() {
        XCTAssertEqual(ExperimentState.derive(outcome: .passed, restorationOK: true, restorationEntries: ["x": true]), .completed)
        XCTAssertEqual(ExperimentState.derive(outcome: .passed, restorationOK: false, restorationEntries: ["x": false]), .restorationRequired)
        XCTAssertEqual(ExperimentState.derive(outcome: .failed, restorationOK: true, restorationEntries: ["x": true]), .failed)
        XCTAssertEqual(ExperimentState.derive(outcome: .inconclusive, restorationOK: true, restorationEntries: [:]), .inconclusive)
        XCTAssertEqual(ExperimentState.derive(outcome: .errored, restorationOK: true, restorationEntries: [:]), .interrupted)
    }

    func testAssertionSummaryCounts() {
        let a1 = Assertion(kind: .processAlive, subject: "1")
        let a2 = Assertion(kind: .fileExists, subject: "/tmp")
        let a3 = Assertion(kind: .fileExists, subject: "/tmp")
        var record = ExperimentRecord(config: ExperimentConfig(
            name: "s", plannedDuration: 10, bindings: [FaultBinding(faultID: .cpuLoad)],
            assertions: [a1, a2, a3]
        ))
        record.assertionResults[a1.id] = .passed
        record.assertionResults[a2.id] = .failed
        let s = record.assertionSummary
        XCTAssertEqual(s.passed, 1)
        XCTAssertEqual(s.failed, 1)
        XCTAssertEqual(s.pending, 1)
    }

    // MARK: Backward compatibility

    private var legacyDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testOldConfigJSONWithoutRulesDecodes() throws {
        let old = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"legacy","seed":42,
         "plannedDuration":60,"bindings":[],"targets":[],"assertions":[],
         "createdAt":"2026-01-01T00:00:00Z","notes":"","safetyConfirmed":true}
        """
        let config = try legacyDecoder.decode(ExperimentConfig.self, from: Data(old.utf8))
        XCTAssertEqual(config.name, "legacy")
        XCTAssertTrue(config.rules.isEmpty)
    }

    func testOldRecordJSONWithoutStateDecodes() throws {
        let old = """
        {"id":"22222222-2222-2222-2222-222222222222",
         "config":{"id":"33333333-3333-3333-3333-333333333333","name":"legacy","seed":1,
                   "plannedDuration":10,"bindings":[],"targets":[],"assertions":[],
                   "createdAt":"2026-01-01T00:00:00Z","notes":"","safetyConfirmed":true},
         "outcome":"stopped","events":[],"assertionResults":{},
         "restorationStatus":{},"interruptedByExit":false}
        """
        let record = try legacyDecoder.decode(ExperimentRecord.self, from: Data(old.utf8))
        XCTAssertNil(record.state)
        XCTAssertTrue(record.evidenceByAssertion.isEmpty)
    }

    func testOldScenarioJSONWithoutMetadataDecodes() throws {
        let old = """
        {"id":"legacy-scenario","name":"Legacy","summary":"old","category":"Network",
         "symbolName":"wifi","isBuiltin":false,"isExtreme":false,"bindings":[]}
        """
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data(old.utf8))
        XCTAssertEqual(scenario.purpose, "")
        XCTAssertEqual(scenario.recommendedFor, [])
    }
}

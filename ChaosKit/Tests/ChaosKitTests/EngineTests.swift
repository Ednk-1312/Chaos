import XCTest
@testable import ChaosKit

/// Records calls so tests can assert engine↔runner behavior.
final class FakeFaultRunner: FaultRunner, @unchecked Sendable {
    let id: FaultID
    let activationDelay: TimeInterval
    let shouldSucceed: Bool
    private(set) var activateCount = 0
    private(set) var restoreCount = 0
    private let lock = NSLock()

    init(id: FaultID, shouldSucceed: Bool = true, activationDelay: TimeInterval = 0.05) {
        self.id = id
        self.shouldSucceed = shouldSucceed
        self.activationDelay = activationDelay
    }

    func activate(_ context: FaultContext) async -> ActivationResult {
        lock.lock(); activateCount += 1; lock.unlock()
        try? await Task.sleep(nanoseconds: UInt64(activationDelay * 1_000_000_000))
        return shouldSucceed ? .success("fake activated") : .failure("fake failed")
    }

    func restore(_ context: FaultContext) async -> Bool {
        lock.lock(); restoreCount += 1; lock.unlock()
        return true
    }
}

final class EngineTests: XCTestCase {
    var store: PersistenceStore!
    var engine: ExperimentEngine!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("chaos-tests-\(UUID().uuidString)", isDirectory: true)
        store = PersistenceStore(rootURL: tmp)
        engine = ExperimentEngine(registry: FaultRegistry(), persistence: store)
    }

    override func tearDown() {
        engine.stop(reason: .emergencyStop)
        super.tearDown()
    }

    private func makeConfig(
        bindings: [FaultBinding],
        assertions: [Assertion] = [],
        safetyConfirmed: Bool = true
    ) -> ExperimentConfig {
        ExperimentConfig(
            name: "Test Experiment",
            plannedDuration: 1,
            bindings: bindings,
            assertions: assertions,
            safetyConfirmed: safetyConfirmed
        )
    }

    func testStartRefusesUnconfirmedConfig() {
        let config = makeConfig(
            bindings: [FaultBinding(faultID: .networkLatency)],
            safetyConfirmed: false
        )
        XCTAssertThrowsError(try engine.start(config: config)) { error in
            XCTAssertTrue(error is ChaosError)
        }
    }

    func testStartRefusesEmptyBindings() {
        let config = makeConfig(bindings: [])
        XCTAssertThrowsError(try engine.start(config: config))
    }

    func testStartRefusesWhileAlreadyRunning() throws {
        let runner = FakeFaultRunner(id: .networkLatency)
        let registry = FaultRegistry()
        registry.register(runner)
        engine = ExperimentEngine(registry: registry, persistence: store)

        _ = try engine.start(config: makeConfig(
            bindings: [FaultBinding(faultID: .networkLatency, duration: 0.2)]
        ))

        // The start call schedules async activation; wait a beat then confirm
        // a second start is rejected while the first is still in flight.
        let expectation = expectation(description: "second start rejected")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            do {
                _ = try self.engine.start(config: self.makeConfig(
                    bindings: [FaultBinding(faultID: .cpuLoad, duration: 0.2)]
                ))
            } catch ChaosError.experimentAlreadyRunning {
                expectation.fulfill()
            } catch {
                // experiment may have finished already — also acceptable
                if case ChaosError.experimentAlreadyRunning = error {
                    expectation.fulfill()
                }
            }
        }
        wait(for: [expectation], timeout: 3)
    }

    func testFaultActivatesAndRestores() async throws {
        let runner = FakeFaultRunner(id: .cpuLoad)
        let registry = FaultRegistry()
        registry.register(runner)
        engine = ExperimentEngine(registry: registry, persistence: store)

        _ = try engine.start(config: makeConfig(
            bindings: [FaultBinding(faultID: .cpuLoad, duration: 0.2)]
        ))

        // Wait for activation + scheduled restoration.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertGreaterThanOrEqual(runner.activateCount, 1)
        XCTAssertGreaterThanOrEqual(runner.restoreCount, 1)
    }

    func testEmergencyStopRestoresActiveFaults() async throws {
        let runner = FakeFaultRunner(id: .memoryPressure, activationDelay: 0.01)
        let registry = FaultRegistry()
        registry.register(runner)
        engine = ExperimentEngine(registry: registry, persistence: store)

        _ = try engine.start(config: makeConfig(
            bindings: [FaultBinding(faultID: .memoryPressure, duration: 30)]
        ))
        try await Task.sleep(nanoseconds: 400_000_000)

        engine.stop(reason: .emergencyStop)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(runner.restoreCount, 1, "emergency stop must restore active faults")
    }

    func testOutcomeDerivation() {
        var record = ExperimentRecord(config: makeConfig(bindings: [
            FaultBinding(faultID: .cpuLoad)
        ], assertions: [
            Assertion(kind: .processAlive, subject: "123")
        ]))
        record.assertionResults[record.config.assertions[0].id] = .failed
        XCTAssertEqual(
            ExperimentEngine.outcomeFor(record: record, reason: .completed),
            .failed
        )

        record.assertionResults[record.config.assertions[0].id] = .passed
        XCTAssertEqual(
            ExperimentEngine.outcomeFor(record: record, reason: .completed),
            .passed
        )
    }

    func testInconclusiveWithoutAssertions() {
        let record = ExperimentRecord(config: makeConfig(bindings: [
            FaultBinding(faultID: .cpuLoad)
        ]))
        XCTAssertEqual(
            ExperimentEngine.outcomeFor(record: record, reason: .completed),
            .inconclusive
        )
    }

    func testCheckpointRoundTrip() throws {
        let cp = ExperimentEngine.Checkpoint(
            experimentID: UUID(), startedAt: Date(),
            activeFaultIDs: ["cpu.load"], workerPIDs: [123, 456]
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chaos-cp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        engine.checkpointDirectory = dir
        if let data = try? JSONEncoder().encode(cp) {
            try data.write(to: dir.appendingPathComponent("checkpoint.json"))
        }
        let read = ExperimentEngine.readCheckpoint(in: dir)
        XCTAssertNotNil(read)
        XCTAssertEqual(read?.activeFaultIDs, ["cpu.load"])
        XCTAssertEqual(read?.workerPIDs, [123, 456])
    }
}

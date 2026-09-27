import XCTest
@testable import ChaosKit

final class PersistenceAndSafetyTests: XCTestCase {
    var store: PersistenceStore!

    override func setUp() {
        super.setUp()
        store = PersistenceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("chaos-persist-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func makeRecord() -> ExperimentRecord {
        var config = ExperimentConfig(
            name: "Persist Me",
            plannedDuration: 30,
            bindings: [
                FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 20,
                             parameters: ["latencyMs": "250"])
            ],
            assertions: [Assertion(kind: .processAlive, subject: "100")]
        )
        config.safetyConfirmed = true
        var record = ExperimentRecord(config: config, outcome: .passed, startedAt: Date(), endedAt: Date())
        record.events = [
            ExperimentEvent(kind: .experimentStarted, message: "started"),
            ExperimentEvent(kind: .faultActivated, message: "latency on", faultID: .networkLatency),
        ]
        record.assertionResults[config.assertions[0].id] = .passed
        record.restorationStatus = ["network.latency": true]
        record.hostInfo = HostInfo.capture()
        return record
    }

    func testRecordRoundTrip() {
        let record = makeRecord()
        store.save(record: record)
        let loaded = store.loadRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.config.name, "Persist Me")
        XCTAssertEqual(loaded.first?.outcome, .passed)
        XCTAssertEqual(loaded.first?.events.count, 2)
        XCTAssertEqual(loaded.first?.restorationStatus["network.latency"], true)
        XCTAssertEqual(loaded.first?.config.bindings.first?.faultID, .networkLatency)
    }

    func testScenarioRoundTrip() {
        let scenario = Scenario(
            id: "my-scenario", name: "Mine", category: "Custom",
            summary: "user scenario", symbolName: "bolt",
            bindings: [FaultBinding(faultID: .cpuLoad, startOffset: 0, duration: 30)]
        )
        store.save(scenario: scenario)
        let loaded = store.loadUserScenarios()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "my-scenario")
        XCTAssertEqual(loaded.first?.bindings.first?.faultID, .cpuLoad)
    }

    func testDeleteRecord() {
        store.save(record: makeRecord())
        XCTAssertFalse(store.loadRecords().isEmpty)
        store.deleteRecord(id: store.loadRecords()[0].id)
        XCTAssertTrue(store.loadRecords().isEmpty)
    }

    func testCorruptedRecordIsSkippedNotFatal() throws {
        store.save(record: makeRecord())
        let url = store.recordsURL.appendingPathComponent("garbage.json")
        try Data("not json at all {{".utf8).write(to: url)
        XCTAssertEqual(store.loadRecords().count, 1, "corrupted files must be skipped")
    }

    // MARK: Safety

    func testMemoryCeilingAlwaysLeavesHeadroom() {
        let ceiling = ResourceSafety.memoryCeilingBytes()
        let total = ProcessInfo.processInfo.physicalMemory
        XCTAssertGreaterThanOrEqual(ceiling, total / 4)
        XCTAssertGreaterThanOrEqual(ceiling, 2_000_000_000)
    }

    func testSafeAllocationNeverExceedsFreeMemory() {
        let desired: UInt64 = 100_000_000_000 // 100 GB — absurd
        let safe = ResourceSafety.safeAllocationBytes(desired: desired)
        XCTAssertLessThan(safe, desired)
    }

    func testSandboxIsScopedToApplicationSupport() {
        XCTAssertTrue(ChaosSandbox.rootURL.path.contains("Application Support"))
        XCTAssertTrue(ChaosSandbox.rootURL.path.hasSuffix("Chaos/Sandbox"))
    }

    func testSandboxDirectoryCreationIsUnique() {
        let a = ChaosSandbox.makeExperimentDirectory()
        let b = ChaosSandbox.makeExperimentDirectory()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        ChaosSandbox.purgeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChaosSandbox.rootURL.path))
    }

    func testReportsGenerateAllFormats() {
        let record = makeRecord()
        let md = ReportGenerator.markdown(for: record)
        XCTAssertTrue(md.contains("# Chaos Report"))
        XCTAssertTrue(md.contains("Persist Me"))
        XCTAssertTrue(md.contains("## Restoration"))

        let json = try? ReportGenerator.jsonData(for: record)
        XCTAssertNotNil(json)
        XCTAssertGreaterThan(json?.count ?? 0, 50)

        let csv = ReportGenerator.csv(for: record)
        XCTAssertTrue(csv.hasPrefix("timestamp,kind,message"))
        XCTAssertTrue(csv.contains("started"))

        let html = ReportGenerator.htmlDocument(for: record)
        XCTAssertTrue(html.contains("<html"))
        XCTAssertFalse(html.contains("<script"), "report HTML must not contain scripts")
    }

    func testHTMLEscaping() {
        XCTAssertEqual(ReportGenerator.escapeHTML("<b>&\""), "&lt;b&gt;&amp;\"")
    }
}

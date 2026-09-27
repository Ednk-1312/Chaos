import XCTest
@testable import ChaosKit

final class ResilienceScorecardTests: XCTestCase {

    private func makeRecord(
        name: String,
        bindings: [FaultBinding],
        assertions: [Assertion],
        results: [UUID: Assertion.Outcome]
    ) -> ExperimentRecord {
        var config = ExperimentConfig(name: name, plannedDuration: 60, bindings: bindings, targets: [], assertions: assertions)
        config.safetyConfirmed = true
        return ExperimentRecord(
            config: config,
            outcome: .passed,
            startedAt: Date(timeIntervalSince1970: 1_760_000_000),
            endedAt: Date(timeIntervalSince1970: 1_760_000_060),
            events: [],
            assertionResults: results
        )
    }

    func testEmptyHistoryYieldsEmptyScorecard() {
        let card = ResilienceScorecard(records: [])
        XCTAssertTrue(card.entries.isEmpty)
        XCTAssertEqual(card.distinctRecordCount, 0)
    }

    func testSingleCategoryAggregation() {
        let net = FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 10)
        let a1 = Assertion(kind: .endpointReachable, subject: "1.1.1.1:443")
        let a2 = Assertion(kind: .processAlive, subject: "123")
        let record = makeRecord(
            name: "Net Test",
            bindings: [net],
            assertions: [a1, a2],
            results: [a1.id: .passed, a2.id: .failed]
        )

        let card = ResilienceScorecard(records: [record])
        XCTAssertEqual(card.entries.count, 1)
        let entry = try! XCTUnwrap(card.entry(for: .network))
        XCTAssertEqual(entry.runCount, 1)
        XCTAssertEqual(entry.totalPassed, 1)
        XCTAssertEqual(entry.totalFailed, 1)
        XCTAssertEqual(entry.distinctFaultCount, 1)
        XCTAssertEqual(entry.faultsByRuns.first?.0, .networkLatency)
    }

    func testRecordSpansMultipleCategories() {
        let net = FaultBinding(faultID: .packetLoss, startOffset: 0, duration: 10)
        let mem = FaultBinding(faultID: .memoryPressure, startOffset: 10, duration: 10)
        let a1 = Assertion(kind: .processAlive, subject: "123")
        let record = makeRecord(
            name: "Combo",
            bindings: [net, mem],
            assertions: [a1],
            results: [a1.id: .passed]
        )

        let card = ResilienceScorecard(records: [record])
        XCTAssertEqual(card.entries.count, 2)
        XCTAssertEqual(card.distinctRecordCount, 1)
        for entry in card.entries {
            XCTAssertEqual(entry.runCount, 1, "record should count in both \(entry.category) rows")
            XCTAssertEqual(entry.totalPassed, 1)
        }
    }

    func testDisabledBindingsDoNotAttribute() {
        var net = FaultBinding(faultID: .dnsFailure, startOffset: 0, duration: 10)
        net.enabled = false
        let card = ResilienceScorecard(records: [
            makeRecord(name: "X", bindings: [net], assertions: [], results: [:])
        ])
        XCTAssertTrue(card.entries.isEmpty, "a record whose only faults are disabled must not appear")
    }

    func testUnresolvedOutcomesAreCountedSeparately() {
        let mem = FaultBinding(faultID: .memoryPressure, startOffset: 0, duration: 10)
        let a1 = Assertion(kind: .processAlive, subject: "1")
        let a2 = Assertion(kind: .fileExists, subject: "/tmp/x")
        let a3 = Assertion(kind: .logContains, subject: "kernel")
        let record = makeRecord(
            name: "Y",
            bindings: [mem],
            assertions: [a1, a2, a3],
            results: [a1.id: .pending, a2.id: .skipped, a3.id: .inconclusive]
        )

        let entry = try! XCTUnwrap(ResilienceScorecard(records: [record]).entry(for: .memory))
        XCTAssertEqual(entry.totalPending, 1)
        XCTAssertEqual(entry.totalSkipped, 1)
        XCTAssertEqual(entry.totalInconclusive, 1)
        XCTAssertEqual(entry.totalPassed, 0)
        XCTAssertEqual(entry.totalFailed, 0)
    }

    func testUnresolvedAssertionsDefaultToPending() {
        let cpu = FaultBinding(faultID: .cpuLoad, startOffset: 0, duration: 10)
        let a1 = Assertion(kind: .processAlive, subject: "9")
        let record = makeRecord(name: "Z", bindings: [cpu], assertions: [a1], results: [:])

        let entry = try! XCTUnwrap(ResilienceScorecard(records: [record]).entry(for: .cpu))
        XCTAssertEqual(entry.totalPending, 1, "missing result must surface as pending, never as pass")
    }

    func testSortingPutsFailureEvidenceFirst() {
        func record(_ name: String, _ fault: FaultID, _ outcomes: [Assertion.Outcome]) -> ExperimentRecord {
            let binding = FaultBinding(faultID: fault, startOffset: 0, duration: 10)
            let assertions = outcomes.enumerated().map { i, o in
                Assertion(kind: .processAlive, subject: "\(i)")
            }
            var results: [UUID: Assertion.Outcome] = [:]
            for (a, o) in zip(assertions, outcomes) { results[a.id] = o }
            return makeRecord(name: name, bindings: [binding], assertions: assertions, results: results)
        }

        let failing = record("F", .fsPermissionDenied, [.failed, .failed])
        let passing = record("P", .networkOffline, [.passed, .passed])
        let card = ResilienceScorecard(records: [passing, failing])

        XCTAssertEqual(card.entries.first?.category, .filesystem, "category with failures sorts first")
        XCTAssertEqual(card.entries.last?.category, .network)
    }

    func testFaultsByRunsOrdersAndTiesBreakAlphabetically() {
        let a = FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 5)
        let b = FaultBinding(faultID: .packetLoss, startOffset: 5, duration: 5)
        let c = FaultBinding(faultID: .jitter, startOffset: 10, duration: 5)
        let record1 = makeRecord(name: "r1", bindings: [a, b], assertions: [], results: [:])
        let record2 = makeRecord(name: "r2", bindings: [a, c], assertions: [], results: [:])

        let entry = try! XCTUnwrap(ResilienceScorecard(records: [record1, record2]).entry(for: .network))
        let faults = entry.faultsByRuns.map { $0.0 }
        XCTAssertEqual(faults.first, .networkLatency, "latency ran in 2 records, others in 1")
        XCTAssertEqual(entry.distinctFaultCount, 3)
    }

    func testEquivalentHistoriesProduceEqualAggregates() {
        // Two runs with identical assertions/outcomes must aggregate identically
        // (record IDs and seeds differ; the evidence does not).
        let net = FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 10)
        let a = Assertion(kind: .endpointReachable, subject: "h:1")
        let r1 = makeRecord(name: "A", bindings: [net], assertions: [a], results: [a.id: .passed])
        let r2 = makeRecord(name: "A", bindings: [net], assertions: [a], results: [a.id: .passed])
        let c1 = ResilienceScorecard(records: [r1]).entry(for: .network)
        let c2 = ResilienceScorecard(records: [r2]).entry(for: .network)
        XCTAssertEqual(c1?.runCount, c2?.runCount)
        XCTAssertEqual(c1?.totalPassed, c2?.totalPassed)
        XCTAssertEqual(c1?.faultsByRuns.map { "\($0.0.rawValue):\($0.1)" },
                       c2?.faultsByRuns.map { "\($0.0.rawValue):\($0.1)" })
        XCTAssertNotEqual(r1.id, r2.id, "records are distinct runs; aggregates must still match")
    }
}

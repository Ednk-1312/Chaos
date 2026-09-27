import XCTest
@testable import ChaosKit

final class ModelTests: XCTestCase {
    func testFaultCatalogIsComplete() {
        XCTAssertFalse(FaultCatalog.all.isEmpty)
        // Every category must have at least one fault.
        for category in FaultCategory.allCases {
            XCTAssertFalse(
                FaultCatalog.all.filter { $0.category == category }.isEmpty,
                "category \(category.rawValue) has no faults"
            )
        }
        // Fault IDs must be unique.
        let ids = FaultCatalog.all.map { $0.id.rawValue }
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate fault ids in catalog")
    }

    func testEveryFaultHasDocumentation() {
        for fault in FaultCatalog.all {
            XCTAssertFalse(fault.whatItTests.isEmpty, "\(fault.id) missing whatItTests")
            XCTAssertFalse(fault.restoration.isEmpty, "\(fault.id) missing restoration")
            XCTAssertFalse(fault.capabilityNote.isEmpty, "\(fault.id) missing capabilityNote")
        }
    }

    func testEveryRunnableFaultHasRunner() {
        for fault in FaultCatalog.all where fault.id.category == .network {
            XCTAssertNotNil(
                DefaultFaultRegistry.runner(for: fault.id),
                "network fault \(fault.id) should be runnable"
            )
        }
    }

    func testGuidedFaultsAreLabeledSimulated() {
        // Composition faults are planned/supervised by the engine, not guided drills.
        let composition: [FaultID] = [.randomChaos, .releaseCandidate, .everythingBroken, .customScript]
        for id in DefaultFaultRegistry.guidedOnlyFaultIDs where !composition.contains(id) {
            let descriptor = FaultCatalog.descriptor(for: id)
            XCTAssertNotNil(descriptor)
            XCTAssertTrue(
                descriptor?.simulated ?? false,
                "guided-only fault \(id.rawValue) must be marked simulated"
            )
        }
    }

    func testScenarioLibraryIntegrity() {
        XCTAssertFalse(ScenarioLibrary.all.isEmpty)
        for scenario in ScenarioLibrary.all {
            XCTAssertFalse(scenario.bindings.isEmpty, "\(scenario.id) has no bindings")
            XCTAssertFalse(scenario.summary.isEmpty, "\(scenario.id) missing summary")
            for binding in scenario.bindings {
                XCTAssertNotNil(
                    FaultCatalog.descriptor(for: binding.faultID),
                    "\(scenario.id) references unknown fault \(binding.faultID)"
                )
            }
        }
        let ids = ScenarioLibrary.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate scenario ids")
    }

    func testAssertionEvaluation() {
        let alive = Assertion(kind: .processAlive, subject: "\(ProcessInfo.processInfo.processIdentifier)")
        let dead = Assertion(kind: .processAlive, subject: "999999")
        let context = AssertionContext(
            alivePIDs: [ProcessInfo.processInfo.processIdentifier],
            runningNames: [],
            reachableEndpoints: ["127.0.0.1:8080"],
            logMatches: []
        )
        XCTAssertEqual(alive.evaluate(context), .passed)
        XCTAssertEqual(dead.evaluate(context), .failed)

        // processDisappeared with default expectation: a vanished process is the expected outcome.
        let negative = Assertion(kind: .processDisappeared, subject: "never-running-process")
        XCTAssertEqual(negative.evaluate(context), .passed)
        // With expected=false it asserts the process is still present.
        let stillThere = Assertion(kind: .processDisappeared, subject: "never-running-process", expected: false)
        XCTAssertEqual(stillThere.evaluate(context), .failed)
    }

    func testFaultIDCategoryParsing() {
        XCTAssertEqual(FaultID.networkOffline.category, .network)
        XCTAssertEqual(FaultID.cpuLoad.category, .cpu)
        XCTAssertEqual(FaultID("weird.unknown"), FaultID("weird.unknown"))
        XCTAssertEqual(FaultID("weird.unknown").category, .misc)
    }

    func testSeverityOrdering() {
        XCTAssertTrue(Severity.low < Severity.moderate)
        XCTAssertTrue(Severity.moderate < Severity.high)
        XCTAssertTrue(Severity.high < Severity.extreme)
        XCTAssertEqual([Severity.moderate, .extreme, .low].max(), .extreme)
    }
}

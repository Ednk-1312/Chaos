import XCTest
@testable import ChaosKit

final class RandomChaosTests: XCTestCase {
    func testSameSeedProducesIdenticalPlan() {
        let categories: [FaultCategory] = [.network, .cpu, .memory]
        let a = RandomChaosPlanner.plan(seed: 842913, duration: 600, allowedCategories: categories, maxSeverity: .high)
        let b = RandomChaosPlanner.plan(seed: 842913, duration: 600, allowedCategories: categories, maxSeverity: .high)
        XCTAssertEqual(a.bindings.map(\.faultID), b.bindings.map(\.faultID))
        XCTAssertEqual(a.bindings.map(\.startOffset), b.bindings.map(\.startOffset))
        XCTAssertEqual(a.bindings.map(\.duration), b.bindings.map(\.duration))
        XCTAssertEqual(a.bindings.map(\.parameters), b.bindings.map(\.parameters))
    }

    func testDifferentSeedsDiverge() {
        let categories: [FaultCategory] = [.network, .cpu, .memory, .storage]
        let a = RandomChaosPlanner.plan(seed: 1, duration: 600, allowedCategories: categories, maxSeverity: .extreme)
        let b = RandomChaosPlanner.plan(seed: 2, duration: 600, allowedCategories: categories, maxSeverity: .extreme)
        // Not statistically guaranteed, but with 13+ windows the chance both seeds
        // produce identical sequences is negligible.
        XCTAssertNotEqual(a.bindings.map(\.faultID), b.bindings.map(\.faultID))
    }

    func testPlanRespectsSeverityCeiling() {
        let categories: [FaultCategory] = [.network, .cpu, .memory]
        let plan = RandomChaosPlanner.plan(seed: 7, duration: 600, allowedCategories: categories, maxSeverity: .moderate)
        for binding in plan.bindings {
            XCTAssertLessThanOrEqual(binding.severity, .moderate)
        }
    }

    func testPlanRespectsDurationBounds() {
        let plan = RandomChaosPlanner.plan(seed: 99, duration: 120, allowedCategories: [.network, .cpu, .memory], maxSeverity: .extreme)
        for binding in plan.bindings {
            XCTAssertLessThanOrEqual(binding.startOffset, 120)
            XCTAssertLessThanOrEqual(binding.startOffset + binding.duration, 125)
        }
    }

    func testEmptyCategoriesYieldEmptyPlan() {
        let plan = RandomChaosPlanner.plan(seed: 5, duration: 600, allowedCategories: [], maxSeverity: .extreme)
        XCTAssertTrue(plan.bindings.isEmpty)
    }

    func testSplitMix64IsDeterministic() {
        var rngA = SplitMix64(seed: 42)
        var rngB = SplitMix64(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(rngA.next(), rngB.next())
        }
        var rngC = SplitMix64(seed: 42)
        _ = rngC.next()
        _ = rngC.next()
        var rngD = SplitMix64(seed: 42)
        _ = rngD.next()
        // rngC is one step ahead of rngD, so their next values must differ.
        XCTAssertNotEqual(rngC.next(), rngD.next())
    }
}

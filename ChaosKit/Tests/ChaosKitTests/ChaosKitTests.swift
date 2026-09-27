import XCTest
@testable import ChaosKit

final class ChaosKitTests: XCTestCase {
    func testEngineVersionIsReported() {
        XCTAssertFalse(chaosKitVersion.isEmpty)
    }

    func testRegistryLookup() {
        let registry = FaultRegistry()
        XCTAssertNil(registry.runner(for: .cpuLoad))
        registry.register(FakeFaultRunner(id: .cpuLoad))
        XCTAssertNotNil(registry.runner(for: .cpuLoad))
        XCTAssertTrue(registry.canExecute(.cpuLoad))
        XCTAssertFalse(registry.canExecute(.randomChaos))
    }

    func testDefaultRegistryCoversNetworkAndResources() {
        let ids: [FaultID] = [.networkOffline, .networkLatency, .packetLoss, .cpuLoad, .memoryPressure]
        for id in ids {
            XCTAssertNotNil(DefaultFaultRegistry.runner(for: id), "missing runner for \(id)")
        }
    }
}

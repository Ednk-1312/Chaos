import Foundation

/// A developer's application under test. Profiles personalize Chaos: recent
/// experiments, saved recipes, and recommended tests based ONLY on what the
/// user actually configured — never invented dependencies or guessed metadata.
public struct AppProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bundleID: String?
    public var version: String?
    public var executablePath: String?
    public var iconData: Data?
    public var configuredDependencies: [String]   // user-declared only, never inferred
    public var recommendedScenarioIDs: [String]
    public var createdAt: Date
    public var notes: String

    public init(
        id: UUID = UUID(), name: String, bundleID: String? = nil,
        version: String? = nil, executablePath: String? = nil,
        iconData: Data? = nil, configuredDependencies: [String] = [],
        recommendedScenarioIDs: [String] = [], createdAt: Date = Date(), notes: String = ""
    ) {
        self.id = id; self.name = name; self.bundleID = bundleID
        self.version = version; self.executablePath = executablePath
        self.iconData = iconData; self.configuredDependencies = configuredDependencies
        self.recommendedScenarioIDs = recommendedScenarioIDs
        self.createdAt = createdAt; self.notes = notes
    }

    /// Recommended tests derived strictly from configured characteristics.
    /// No dependency declared → no dependency scenario recommended. Honest.
    public var recommendedScenarios: [Scenario] {
        var ids = recommendedScenarioIDs
        if ids.isEmpty {
            ids = ["terrible-wifi", "memory-moderate"]
            if !configuredDependencies.isEmpty { ids.append("server-outage") }
        }
        return ids.compactMap { ScenarioLibrary.scenario(id: $0) }
    }

    /// Resilience history: records whose target matches this profile.
    public func matchingRecords(in records: [ExperimentRecord]) -> [ExperimentRecord] {
        records.filter { record in
            record.config.targets.contains { target in
                (bundleID != nil && target.bundleID == bundleID)
                    || target.name == name
            } || record.config.name == name
        }
    }
}

/// Sensible default parameters per fault, so dropping a fault on the timeline
/// yields a runnable configuration immediately (no forced dialogs).
public enum FaultDefaults {
    public static func parameters(for id: FaultID) -> [String: String] {
        switch id {
        case .networkLatency: return ["latencyMs": "500"]
        case .packetLoss: return ["lossPercent": "10"]
        case .bandwidthCap: return ["bandwidthKbps": "1500"]
        case .burstLoss: return ["periodSeconds": "12"]
        case .jitter: return ["latencyMs": "150"]
        case .cpuLoad: return ["utilization": "75", "threads": "4"]
        case .memoryPressure: return ["gigabytes": "2"]
        case .storageFill: return ["capacityGB": "2", "freeGB": "1"]
        case .deviceVolumeDisappear: return ["detachAfterSeconds": "8"]
        case .processRestartLoop: return ["intervalSeconds": "20"]
        case .dependencySlow: return ["latencyMs": "800"]
        case .clockSkew: return ["offsetMinutes": "90"]
        default: return [:]
        }
    }

    public static func duration(for id: FaultID) -> TimeInterval {
        FaultCatalog.descriptor(for: id)?.defaultDuration ?? 60
    }
}

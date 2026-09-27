import Foundation

/// Concrete registry wiring FaultIDs to the real fault implementations.
public enum DefaultFaultRegistry {
    private static let networkRunner = NetworkFaultRunner(id: .networkOffline) // id unused; per-call switch
    private static let resourceRunner = ResourceFaultRunner(id: .cpuLoad)
    private static let storageRunner = StorageFilesystemFaultRunner(id: .storageFill)
    private static let processRunner = ProcessFaultRunner(id: .processKill)
    private static let environmentRunner = EnvironmentFaultRunner(id: .lifecycleSleep)

    public static func runner(for id: FaultID) -> FaultRunner? {
        switch id {
        case .networkOffline, .networkLatency, .packetLoss, .bandwidthCap,
             .dnsFailure, .connectionReset, .jitter, .burstLoss:
            return networkRunner
        case .cpuLoad, .memoryPressure, .powerThermal, .thermalSustainedLoad:
            return resourceRunner
        case .storageFill, .fsMissingFile, .fsReadOnly, .fsPermissionDenied,
             .fsLocked, .fsDelayedAvailability, .permissionDenied:
            return storageRunner
        case .processKill, .processPause, .processRestartLoop, .processRelaunch,
             .dependencyDown, .dependencySlow, .dependencyFlap, .dependencyRestart:
            return processRunner
        case .lifecycleSleep, .lifecycleWake, .deviceDisconnect, .deviceVolumeDisappear,
             .deviceDisplaySleep, .deviceAudioSwitch,
             .clockSkew, .clockDST, .clockRollover, .clockCertExpiry,
             .powerLowBattery, .powerChargeState, .powerSourceSwitch:
            return environmentRunner
        default:
            return nil // guided/manual faults intentionally have no runner
        }
    }

    /// Faults with real executable implementations.
    public static var supportedFaultIDs: [FaultID] {
        FaultCatalog.all.map(\.id).filter { runner(for: $0) != nil }
    }

    /// Faults that require the guided/manual path (honestly labeled in the UI).
    public static var guidedOnlyFaultIDs: [FaultID] {
        FaultCatalog.all.map(\.id).filter { runner(for: $0) == nil }
    }
}

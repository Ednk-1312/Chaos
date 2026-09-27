import Foundation

/// The shipped scenario library. Every preset is a real, executable composition.
public enum ScenarioLibrary {
    public static let all: [Scenario] = network + storage + memory + permissions + lifecycle + extreme

    public static func byCategory() -> [(String, [Scenario])] {
        let groups = Dictionary(grouping: all, by: \.category)
        return ["Network", "Storage", "Memory", "Permissions", "Lifecycle", "Extreme"]
            .compactMap { cat in groups[cat].map { (cat, $0) } }
    }

    public static func scenario(id: String) -> Scenario? {
        all.first { $0.id == id }
    }

    /// Make an experiment config from a scenario (seed, assertions, safety).

    // MARK: Network

    public static let network: [Scenario] = [
        Scenario(
            id: "airplane-mode", name: "Airplane Mode", category: "Network",
            summary: "Full offline: every outbound connection fails immediately.",
            symbolName: "airplane", isBuiltin: true,
            purpose: "Test application behavior under a full offline window — detection, retry, and queueing behavior.",
            recommendedFor: ["sync apps", "cloud apps", "API clients"],
            expectedBehavior: "The application detects the offline state, queues or retries work, and resumes when connectivity returns.",
            safetyNote: "Blocks all outbound traffic during the experiment window. Fully restored on stop.",
            bindings: [FaultBinding(faultID: .networkOffline, startOffset: 0, duration: 300)]
        ),
        Scenario(
            id: "hotel-wifi", name: "Hotel Wi-Fi", category: "Network",
            summary: "Heavy latency, 15% loss, and capped bandwidth — the classic conference network.",
            symbolName: "wifi.exclamationmark", isBuiltin: true,
            bindings: [
                FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 600,
                             parameters: ["latencyMs": "400"]),
                FaultBinding(faultID: .packetLoss, startOffset: 0, duration: 600,
                             parameters: ["lossPercent": "15"]),
                FaultBinding(faultID: .bandwidthCap, startOffset: 0, duration: 600,
                             parameters: ["bandwidthKbps": "1500"]),
            ]
        ),
        Scenario(
            id: "terrible-wifi", name: "Terrible Wi-Fi", category: "Network",
            summary: "Burst loss with high latency — connections stall and recover unpredictably.",
            symbolName: "wifi.slash", isBuiltin: true,
            purpose: "Test application behavior under unstable connectivity — stalls, blackouts, and partial recovery.",
            recommendedFor: ["sync apps", "cloud apps", "API clients", "messaging apps"],
            expectedBehavior: "The application remains responsive, shows honest connectivity state, and eventually recovers without user data loss.",
            safetyNote: "Affects all processes' outbound traffic for the duration (pf/dummynet). Fully restored on stop.",
            bindings: [
                FaultBinding(faultID: .burstLoss, startOffset: 0, duration: 600,
                             parameters: ["periodSeconds": "12"]),
                FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 600,
                             parameters: ["latencyMs": "800"]),
            ],
            recommendedAssertions: [
                Assertion(kind: .processAppeared, subject: "MyApp", label: "App remains present"),
                Assertion(kind: .endpointReachable, subject: "1.1.1.1:443",
                          label: "Network recovers after blackouts", timeout: 30),
            ]
        ),
        Scenario(
            id: "slow-internet", name: "Slow Internet", category: "Network",
            summary: "2-second latency on everything. Timeouts everywhere.",
            symbolName: "tortoise", isBuiltin: true,
            bindings: [FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 600,
                                    parameters: ["latencyMs": "2000"])]
        ),
        Scenario(
            id: "intermittent-internet", name: "Intermittent Internet", category: "Network",
            summary: "Connection drops for 20s every 2 minutes.",
            symbolName: "arrow.triangle.2.circlepath", isBuiltin: true,
            bindings: [FaultBinding(faultID: .burstLoss, startOffset: 0, duration: 900,
                                    parameters: ["periodSeconds": "120"])]
        ),
        Scenario(
            id: "dns-disaster", name: "DNS Disaster", category: "Network",
            summary: "All hostname resolution fails. IP connections still work.",
            symbolName: "globe.badge.chevron.backward", isBuiltin: true,
            bindings: [FaultBinding(faultID: .dnsFailure, startOffset: 0, duration: 300)]
        ),
        Scenario(
            id: "server-outage", name: "Server Outage", category: "Network",
            summary: "One dependency (by port) goes dark mid-run.",
            symbolName: "antenna.radiowaves.left.and.right.slash", isBuiltin: true,
            bindings: [FaultBinding(faultID: .dependencyDown, startOffset: 30, duration: 300,
                                    parameters: ["port": "443"])]
        ),
    ]

    // MARK: Storage

    public static let storage: [Scenario] = [
        Scenario(
            id: "nearly-full-disk", name: "Nearly Full Disk", category: "Storage",
            summary: "A test volume with ~1 GB free. Point your app at it; fill paths get exercised.",
            symbolName: "internaldrive.badge.exclamationmark", isBuiltin: true,
            bindings: [FaultBinding(faultID: .storageFill, startOffset: 0, duration: 600,
                                    parameters: ["capacityGB": "2", "freeGB": "1"])]
        ),
        Scenario(
            id: "critical-disk", name: "Critical Disk", category: "Storage",
            summary: "A test volume with ~100 MB free — near-zero headroom.",
            symbolName: "internaldrive.fill", isBuiltin: true,
            bindings: [FaultBinding(faultID: .storageFill, startOffset: 0, duration: 600,
                                    parameters: ["capacityGB": "1", "freeGB": "0"])]
        ),
        Scenario(
            id: "volume-vanish", name: "Volume Vanishes", category: "Storage",
            summary: "A mounted scratch volume disappears mid-operation.",
            symbolName: "externaldrive.badge.minus", isBuiltin: true,
            bindings: [FaultBinding(faultID: .deviceVolumeDisappear, startOffset: 10, duration: 120,
                                    parameters: ["detachAfterSeconds": "8"])]
        ),
    ]

    // MARK: Memory

    public static let memory: [Scenario] = [
        Scenario(
            id: "cpu-pressure", name: "CPU Pressure", category: "Memory",
            summary: "Chaos-owned workers at ~75% CPU — timer and watchdog stress.",
            symbolName: "cpu", isBuiltin: true,
            bindings: [FaultBinding(faultID: .cpuLoad, startOffset: 0, duration: 120,
                                    parameters: ["utilization": "75"], severity: .high)]
        ),
        Scenario(
            id: "memory-moderate", name: "Moderate Memory Pressure", category: "Memory",
            summary: "Hold 2 GB of real allocation — caches get purged, warnings fire.",
            symbolName: "memorychip", isBuiltin: true,
            bindings: [FaultBinding(faultID: .memoryPressure, startOffset: 0, duration: 300,
                                    parameters: ["gigabytes": "2"], severity: .moderate)]
        ),
        Scenario(
            id: "memory-severe", name: "Severe Memory Pressure", category: "Memory",
            summary: "Hold 6 GB — jetsam starts reclaiming; expect memory warnings.",
            symbolName: "memorychip.badge.exclamationmark", isBuiltin: true,
            bindings: [FaultBinding(faultID: .memoryPressure, startOffset: 0, duration: 300,
                                    parameters: ["gigabytes": "6"], severity: .high)]
        ),
        Scenario(
            id: "memory-spike", name: "Memory Spike", category: "Memory",
            summary: "Sudden 8 GB allocation for 45 seconds, then clean release.",
            symbolName: "chart.line.uptrend.xyaxis", isBuiltin: true,
            bindings: [FaultBinding(faultID: .memoryPressure, startOffset: 5, duration: 45,
                                    parameters: ["gigabytes": "8"], severity: .high)]
        ),
    ]

    // MARK: Permissions

    public static let permissions: [Scenario] = [
        Scenario(
            id: "dir-access-denied", name: "Directory Access Denied", category: "Permissions",
            summary: "POSIX permissions revoked in a Chaos sandbox directory.",
            symbolName: "lock", isBuiltin: true,
            bindings: [FaultBinding(faultID: .permissionDenied, startOffset: 0, duration: 300)]
        ),
        Scenario(
            id: "read-only-location", name: "Read-Only Location", category: "Permissions",
            summary: "Everything read-only in the sandbox — save flows must degrade gracefully.",
            symbolName: "lock.open", isBuiltin: true,
            bindings: [FaultBinding(faultID: .fsReadOnly, startOffset: 0, duration: 300)]
        ),
        Scenario(
            id: "privacy-guided", name: "Privacy Prompts (Guided)", category: "Permissions",
            summary: "A guided drill covering TCC prompts — macOS never lets apps toggle these.",
            symbolName: "hand.raised", isBuiltin: true,
            bindings: [FaultBinding(faultID: .privacyPrompt, startOffset: 0, duration: 600)]
        ),
    ]

    // MARK: Lifecycle

    public static let lifecycle: [Scenario] = [
        Scenario(
            id: "sleep-during-operation", name: "Sleep During Operation", category: "Lifecycle",
            summary: "Requests system sleep 30s in — what happens to in-flight work?",
            symbolName: "moon.zzz.fill", isBuiltin: true,
            bindings: [
                FaultBinding(faultID: .lifecycleSleep, startOffset: 30, duration: 60),
                FaultBinding(faultID: .lifecycleWake, startOffset: 60, duration: 120),
            ]
        ),
        Scenario(
            id: "wake-after-network-loss", name: "Wake After Network Loss", category: "Lifecycle",
            summary: "Network stays blocked after wake — reconnect handling under fire.",
            symbolName: "moon.zzz", isBuiltin: true,
            bindings: [FaultBinding(faultID: .lifecycleWake, startOffset: 0, duration: 180)]
        ),
        Scenario(
            id: "dependency-restart", name: "Dependency Restart", category: "Lifecycle",
            summary: "Your local service gets restarted mid-run.",
            symbolName: "arrow.clockwise.circle", isBuiltin: true,
            bindings: [FaultBinding(faultID: .dependencyRestart, startOffset: 15, duration: 60)]
        ),
    ]

    // MARK: Extreme

    public static let extreme: [Scenario] = [
        Scenario(
            id: "everything-broken", name: "Everything Is Broken", category: "Extreme",
            summary: "Offline + loss + latency + memory + CPU simultaneously. Extreme — confirm before running.",
            symbolName: "exclamationmark.triangle.fill", isBuiltin: true, isExtreme: true,
            purpose: "Observe the application's behavior on the worst possible day: every subsystem failing at once.",
            recommendedFor: ["release candidates", "resilience hardening"],
            expectedBehavior: "The application degrades gracefully, never corrupts data, and recovers after conditions clear.",
            safetyNote: "Simultaneous system-wide pressure within hard safety ceilings. Explicit confirmation required.",
            bindings: [
                FaultBinding(faultID: .networkOffline, startOffset: 0, duration: 180),
                FaultBinding(faultID: .packetLoss, startOffset: 0, duration: 180, parameters: ["lossPercent": "30"]),
                FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 180, parameters: ["latencyMs": "1000"]),
                FaultBinding(faultID: .memoryPressure, startOffset: 10, duration: 150, parameters: ["gigabytes": "4"]),
                FaultBinding(faultID: .cpuLoad, startOffset: 20, duration: 140, parameters: ["utilization": "90"]),
            ]
        ),
        Scenario(
            id: "worst-day", name: "Worst Day Ever", category: "Extreme",
            summary: "Everything Is Broken, plus disk pressure and a dependency outage.",
            symbolName: "cloud.bolt.rain.fill", isBuiltin: true, isExtreme: true,
            purpose: "Everything Is Broken, plus disk pressure and a dependency outage — for hardening, not for the faint of heart.",
            recommendedFor: ["release candidates", "backup apps"],
            expectedBehavior: "Graceful degradation across every failure class; no data corruption; full recovery.",
            safetyNote: "Strict safety ceilings; explicit confirmation required before running.",
            bindings: [
                FaultBinding(faultID: .networkOffline, startOffset: 0, duration: 240),
                FaultBinding(faultID: .memoryPressure, startOffset: 0, duration: 220, parameters: ["gigabytes": "5"]),
                FaultBinding(faultID: .cpuLoad, startOffset: 0, duration: 220, parameters: ["utilization": "85"]),
                FaultBinding(faultID: .storageFill, startOffset: 30, duration: 200,
                             parameters: ["capacityGB": "1", "freeGB": "0"]),
                FaultBinding(faultID: .dependencyDown, startOffset: 60, duration: 180, parameters: ["port": "443"]),
            ]
        ),
        Scenario(
            id: "random-chaos", name: "Random Chaos", category: "Extreme",
            summary: "Seeded random faults from every category. Reproducible by seed.",
            symbolName: "dice", isBuiltin: true,
            bindings: [FaultBinding(faultID: .randomChaos, startOffset: 0, duration: 600)]
        ),
        Scenario(
            id: "release-candidate", name: "Release Candidate", category: "Extreme",
            summary: "The full pre-release gauntlet: network, memory, storage, permissions, lifecycle.",
            symbolName: "flag.2.crossed", isBuiltin: true,
            bindings: [
                FaultBinding(faultID: .networkLatency, startOffset: 0, duration: 120, parameters: ["latencyMs": "500"]),
                FaultBinding(faultID: .memoryPressure, startOffset: 130, duration: 120, parameters: ["gigabytes": "4"]),
                FaultBinding(faultID: .storageFill, startOffset: 260, duration: 120, parameters: ["capacityGB": "1", "freeGB": "0"]),
                FaultBinding(faultID: .permissionDenied, startOffset: 390, duration: 120),
                FaultBinding(faultID: .lifecycleSleep, startOffset: 520, duration: 60),
            ]
        ),
    ]
}

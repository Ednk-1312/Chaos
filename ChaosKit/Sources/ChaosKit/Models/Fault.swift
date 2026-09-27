import Foundation

// MARK: - Fault Categories

/// Top-level fault categories, mirroring the Chaos product model.
public enum FaultCategory: String, CaseIterable, Codable, Hashable {
    case network, cpu, memory, storage, filesystem, permissions, process, dependency
    case timing, lifecycle, device, clock, power, misc

    public var title: String {
        switch self {
        case .network: return "Network"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .filesystem: return "Filesystem"
        case .permissions: return "Permissions"
        case .process: return "Process"
        case .dependency: return "Dependency"
        case .timing: return "Timing"
        case .lifecycle: return "Lifecycle"
        case .device: return "Device"
        case .clock: return "Clock"
        case .power: return "Power"
        case .misc: return "Miscellaneous"
        }
    }

    public var symbolName: String {
        switch self {
        case .network: return "wifi"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .filesystem: return "doc.badge.gearshape"
        case .permissions: return "lock.shield"
        case .process: return "app.connected.to.app.below.fill"
        case .dependency: return "point.3.connected.trianglepath.dotted"
        case .timing: return "timer"
        case .lifecycle: return "moon.zzz"
        case .device: return "cable.connector"
        case .clock: return "clock"
        case .power: return "bolt.slash"
        case .misc: return "wand.and.stars"
        }
    }
}

// MARK: - Severity & Risk

/// How aggressive a fault is. Drives safety confirmations and default durations.
public enum Severity: String, Codable, CaseIterable, Comparable, Hashable {
    case low, moderate, high, extreme

    public var rank: Int {
        switch self { case .low: return 0; case .moderate: return 1; case .high: return 2; case .extreme: return 3 }
    }
    public static func < (l: Severity, r: Severity) -> Bool { l.rank < r.rank }

    public var title: String {
        switch self { case .low: return "Low"; case .moderate: return "Moderate"; case .high: return "High"; case .extreme: return "Extreme" }
    }
}

// MARK: - Privileges

/// Privilege level a fault needs. Chaos uses least privilege and elevates only at the point of need.
public enum PrivilegeRequirement: String, Codable, CaseIterable, Hashable {
    case none
    case localNetworkSettings   // pf firewall control via authexec + osascript authorization
    case systemConfiguration    // dnctl / networksetup
    case accessibility          // guided sim only; never silently used
    case adminExplanation       // needs explicit user explanation, no silent persistence
}

// MARK: - Fault Descriptor

/// Static, self-describing metadata for one fault type. The "library card".
public struct FaultDescriptor: Identifiable, Hashable, Codable {
    public let id: FaultID
    public var name: String
    public var summary: String
    public var category: FaultCategory
    public var severity: Severity
    public var reversible: Bool
    public var privileges: PrivilegeRequirement
    public var simulated: Bool
    public var capabilityNote: String
    public var whatItTests: String
    public var restoration: String
    public var defaultDuration: TimeInterval

    public init(
        id: FaultID, name: String, summary: String = "", category: FaultCategory,
        severity: Severity, reversible: Bool, simulated: Bool = false,
        privileges: PrivilegeRequirement = .none, capabilityNote: String = "",
        whatItTests: String, restoration: String, defaultDuration: TimeInterval = 60
    ) {
        self.id = id; self.name = name; self.summary = summary; self.category = category
        self.severity = severity; self.reversible = reversible; self.simulated = simulated
        self.privileges = privileges; self.capabilityNote = capabilityNote
        self.whatItTests = whatItTests; self.restoration = restoration
        self.defaultDuration = defaultDuration
    }
}

// MARK: - FaultID

/// Stable identifier for a fault kind, e.g. "network.latency".
public struct FaultID: Hashable, Codable, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.rawValue = try c.decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
    public var description: String { rawValue }
    public var category: FaultCategory {
        FaultCategory.allCases.first { rawValue.hasPrefix($0.rawValue + ".") } ?? .misc
    }

    // Network
    public static let networkOffline = FaultID("network.offline")
    public static let networkLatency = FaultID("network.latency")
    public static let packetLoss = FaultID("network.packet_loss")
    public static let bandwidthCap = FaultID("network.bandwidth")
    public static let dnsFailure = FaultID("network.dns")
    public static let connectionReset = FaultID("network.reset")
    public static let jitter = FaultID("network.jitter")
    public static let burstLoss = FaultID("network.burst_loss")
    // CPU
    public static let cpuLoad = FaultID("cpu.load")
    // Memory
    public static let memoryPressure = FaultID("memory.pressure")
    // Storage
    public static let storageFill = FaultID("storage.fill")
    // Filesystem
    public static let fsMissingFile = FaultID("filesystem.missing_file")
    public static let fsReadOnly = FaultID("filesystem.read_only")
    public static let fsPermissionDenied = FaultID("filesystem.permission_denied")
    public static let fsLocked = FaultID("filesystem.locked")
    public static let fsDelayedAvailability = FaultID("filesystem.delayed_availability")
    // Permissions
    public static let permissionDenied = FaultID("permissions.denied")
    public static let privacyPrompt = FaultID("permissions.privacy")
    // Process
    public static let processKill = FaultID("process.kill")
    public static let processPause = FaultID("process.pause")
    public static let processRestartLoop = FaultID("process.restart_loop")
    public static let processRelaunch = FaultID("process.relaunch")
    // Dependency
    public static let dependencyDown = FaultID("dependency.down")
    public static let dependencySlow = FaultID("dependency.slow")
    public static let dependencyFlap = FaultID("dependency.flap")
    public static let dependencyRestart = FaultID("dependency.restart")
    // Timing
    public static let timingDelay = FaultID("timing.delay")
    public static let timingJitter = FaultID("timing.jitter")
    public static let timingEscalation = FaultID("timing.escalation")
    // Lifecycle
    public static let lifecycleSleep = FaultID("lifecycle.sleep")
    public static let lifecycleWake = FaultID("lifecycle.wake")
    // Device
    public static let deviceDisconnect = FaultID("device.disconnect")
    public static let deviceVolumeDisappear = FaultID("device.volume_disappear")
    public static let deviceDisplaySleep = FaultID("device.display_sleep")
    public static let deviceAudioSwitch = FaultID("device.audio_switch")
    // Clock
    public static let clockSkew = FaultID("clock.skew")
    public static let clockDST = FaultID("clock.dst")
    public static let clockRollover = FaultID("clock.rollover")
    public static let clockCertExpiry = FaultID("clock.cert_expiry")
    // Power
    public static let powerLowBattery = FaultID("power.low_battery")
    public static let powerChargeState = FaultID("power.charge_state")
    public static let powerSourceSwitch = FaultID("power.source_switch")
    public static let powerThermal = FaultID("power.thermal")
    public static let thermalSustainedLoad = FaultID("power.sustained_load")
    // Misc
    public static let randomChaos = FaultID("misc.random_chaos")
    public static let releaseCandidate = FaultID("misc.release_candidate")
    public static let everythingBroken = FaultID("misc.everything_broken")
    public static let customScript = FaultID("misc.custom_script")
    public static let customManual = FaultID("misc.custom_manual")
}

// MARK: - Fault Catalog

/// The complete built-in fault library. Every entry is honest about what macOS allows.
public enum FaultCatalog {
    public static let all: [FaultDescriptor] = network + cpu + memory + storage + filesystem
        + permissions + process + dependency + timing + lifecycle + device + clock + power + misc

    public static func descriptor(for id: FaultID) -> FaultDescriptor? {
        all.first { $0.id == id }
    }

    public static func byCategory() -> [(FaultCategory, [FaultDescriptor])] {
        var map: [FaultCategory: [FaultDescriptor]] = [:]
        for f in all { map[f.category, default: []].append(f) }
        return FaultCategory.allCases.compactMap { cat in map[cat].map { (cat, $0) } }
    }

    // MARK: Network

    public static let network: [FaultDescriptor] = [
        FaultDescriptor(
            id: .networkOffline, name: "Offline Mode", category: .network, severity: .high, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Blocks outbound traffic via a pf anchor (packet filter). All interfaces remain up; apps see hard connection failures. Needs one authorization to install the rule; the anchor is removed on stop and on app exit.",
            whatItTests: "Offline detection, retry logic, queueing of mutations, UI offline states.",
            restoration: "pf anchor is flushed and removed; dnctl default restored.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .networkLatency, name: "Latency", category: .network, severity: .moderate, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Uses dummynet (dnctl pipe) — the same mechanism as Apple's Network Link Conditioner, applied only while the experiment runs. Affects all processes on the machine; per-app network isolation is not possible with documented APIs.",
            whatItTests: "Timeout budgets, loading states, optimistic UI, request coalescing.",
            restoration: "Pipe deleted, dnctl reset to default 0 delay.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .packetLoss, name: "Packet Loss", category: .network, severity: .high, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Random loss via dummynet probability. Covers TCP retransmits, QUIC recovery, and retry storms.",
            whatItTests: "Packet loss tolerance, stream resumption, timeout tuning.",
            restoration: "Pipe probability reset to 0 and pipe removed.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .bandwidthCap, name: "Bandwidth Cap", category: .network, severity: .moderate, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "dummynet bandwidth limit in bits per second. Applies to all processes.",
            whatItTests: "Progressive downloads, pagination, image loading strategies.",
            restoration: "Pipe removed.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .dnsFailure, name: "DNS Failure", category: .network, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Blocked via pf rule to port 53 unless an allowlist entry exists. Requires the network anchor (authorization only once per launch).",
            whatItTests: "DNS fallback behavior, cached results, hostname error UX.",
            restoration: "DNS rule removed with the anchor.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .connectionReset, name: "Connection Reset", category: .network, severity: .moderate, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Modeled as packet loss + short latency spikes; true per-connection RST injection is not exposed by documented macOS APIs.",
            whatItTests: "RST handling, connection pools, TLS session reuse.",
            restoration: "Pipes removed.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .jitter, name: "Jitter", category: .network, severity: .moderate, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "dummynet queue delay with random variation.",
            whatItTests: "Real-time media, ordering assumptions, retry-after headers.",
            restoration: "Pipe removed.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .burstLoss, name: "Burst Loss", category: .network, severity: .high, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Alternates complete loss with full connectivity on a schedule.",
            whatItTests: "Reconnection logic, exponential backoff, partial sync.",
            restoration: "Timer cancelled, pipe removed.",
            defaultDuration: 120),
    ]

    // MARK: CPU

    public static let cpu: [FaultDescriptor] = [
        FaultDescriptor(
            id: .cpuLoad, name: "CPU Pressure", category: .cpu, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Generates real workload with Chaos-owned worker processes. System-wide — macOS provides no documented API to throttle a single other process. Workers are killed on stop and orphan-protected at launch.",
            whatItTests: "Main-thread contention, timer degradation, watchdog timeouts, energy behavior.",
            restoration: "Worker processes terminated and verified.",
            defaultDuration: 60),
    ]

    // MARK: Memory

    public static let memory: [FaultDescriptor] = [
        FaultDescriptor(
            id: .memoryPressure, name: "Memory Pressure", category: .memory, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Chaos-owned workers allocate real memory up to a hard safety ceiling (always leaves ≥2 GB or 25% of RAM free). System-wide; jetsam treats all apps equally. Never intends to trigger a system-wide OOM.",
            whatItTests: "Memory warnings handling, purgeable caches, state restoration after jetsam.",
            restoration: "Workers exit and free memory; verified via pressure readback.",
            defaultDuration: 90),
    ]

    // MARK: Storage

    public static let storage: [FaultDescriptor] = [
        FaultDescriptor(
            id: .storageFill, name: "Disk Near-Full Simulation", category: .storage, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Creates a sparse, temporary staging volume (via `hdiutil`, no admin needed for user-owned images) with a fixed capacity, so apps pointed at it see a nearly-full volume. The real system disk is never filled.",
            whatItTests: "Low-space handling, write failure paths, quota UX, temp file cleanup.",
            restoration: "Volume unmounted and image deleted; verified.",
            defaultDuration: 300),
    ]

    // MARK: Filesystem

    public static let filesystem: [FaultDescriptor] = [
        FaultDescriptor(
            id: .fsMissingFile, name: "Missing File / Directory", category: .filesystem, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Operates only inside Chaos-managed test directories or user-approved folders. Files are moved to a Chaos vault, never deleted.",
            whatItTests: "Missing-resource handling, lazy migration, default file creation.",
            restoration: "Files restored from vault to original paths.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .fsReadOnly, name: "Read-Only Location", category: .filesystem, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Applies user-level read-only flags (uchg) inside approved directories; does not touch system locations.",
            whatItTests: "Save flows, atomic writes, error surfacing for read-only targets.",
            restoration: "Flags cleared.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .fsPermissionDenied, name: "Permission Denied", category: .filesystem, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Rewrites POSIX modes (000) inside approved directories only.",
            whatItTests: "Permission-denied handling, access-recovery flows, sandbox awareness.",
            restoration: "Original modes restored from the vault manifest.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .fsLocked, name: "File Lock Contention", category: .filesystem, severity: .low, reversible: true,
            privileges: .none,
            capabilityNote: "A Chaos-owned helper holds advisory locks (flock) on target files inside approved directories.",
            whatItTests: "Lock-wait behavior, stale lock recovery, cooperative locking bugs.",
            restoration: "Helper exits, releasing all locks.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .fsDelayedAvailability, name: "Delayed File Availability", category: .filesystem, severity: .low, reversible: true,
            privileges: .none,
            capabilityNote: "Within a managed sandbox directory, a file appears only after a configured delay (created hidden until then).",
            whatItTests: "First-launch resource fetching, race conditions, loading UX.",
            restoration: "Sandbox directory removed.",
            defaultDuration: 30),
    ]

    // MARK: Permissions

    public static let permissions: [FaultDescriptor] = [
        FaultDescriptor(
            id: .permissionDenied, name: "Directory Access Denied", category: .permissions, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "POSIX-level denial inside a managed test directory. TCC privacy permissions cannot be programmatically revoked by any app — Chaos instead launches apps with a restricted sandbox-exec profile to exercise denial paths honestly.",
            whatItTests: "Denied-access flows, fallback locations, user messaging.",
            restoration: "Modes restored / profile scoped to the experiment only.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .privacyPrompt, name: "Privacy Prompt Simulation", category: .permissions, severity: .low, reversible: true,
            simulated: true,
            capabilityNote: "SIMULATED — a guided walkthrough with an expected-behavior checklist. macOS does not allow any app (including Chaos) to toggle TCC privacy grants programmatically.",
            whatItTests: "User mental model for each privacy prompt and denial path.",
            restoration: "Nothing changed on the system.",
            defaultDuration: 300),
    ]

    // MARK: Process

    public static let process: [FaultDescriptor] = [
        FaultDescriptor(
            id: .processKill, name: "Kill Process", category: .process, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "SIGKILL to selected processes. Only processes owned by the same user; privileged system processes are refused. Repeat/periodic modes supported.",
            whatItTests: "Crash handling, state persistence, relaunch resilience, watchdogs.",
            restoration: "Not applicable — targets are restored by relaunching if they were started by Chaos; externally-launched apps are the developer's to relaunch (a report records what was killed).",
            defaultDuration: 30),
        FaultDescriptor(
            id: .processPause, name: "Pause (SIGSTOP)", category: .process, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "SIGSTOP freezes the target; SIGCONT resumes. Same-user processes only.",
            whatItTests: "Watchdog behavior, UI freezes, heartbeats, dead-man switches.",
            restoration: "SIGCONT sent and verified.",
            defaultDuration: 20),
        FaultDescriptor(
            id: .processRestartLoop, name: "Dependency Restart Loop", category: .process, severity: .extreme, reversible: true,
            privileges: .none,
            capabilityNote: "Kills the target on a schedule. Chaos never auto-relaunches third-party processes — that could mask real bugs — it only relaunches Chaos-owned helper processes.",
            whatItTests: "Reconnection with dependency, startup racing, supervisor logic.",
            restoration: "Timer cancelled; process left running.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .processRelaunch, name: "Relaunch Cycle", category: .process, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Quits (SIGTERM, then SIGKILL after grace) and relaunches a Chaos-started target app.",
            whatItTests: "Full cold-start path, state restoration, first-run work after upgrade.",
            restoration: "Final launch left running.",
            defaultDuration: 60),
    ]

    // MARK: Dependency

    public static let dependency: [FaultDescriptor] = [
        FaultDescriptor(
            id: .dependencyDown, name: "Dependency Unavailable", category: .dependency, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Blocks a host/port pair via pf rules (authorization required once). If you define a dependency as a Chaos-managed local process, it is stopped instead.",
            whatItTests: "Circuit breakers, failover, error states for backend outages.",
            restoration: "Rules removed with the anchor.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .dependencySlow, name: "Dependency Latency", category: .dependency, severity: .moderate, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "dummynet delay applied to traffic for the dependency's port.",
            whatItTests: "Per-dependency timeouts, speculative work, batching.",
            restoration: "Pipe removed.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .dependencyFlap, name: "Dependency Flapping", category: .dependency, severity: .high, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Alternates dependency availability on a schedule.",
            whatItTests: "Reconnect loops, health checks, jittered backoff correctness.",
            restoration: "Timer cancelled, rules removed.",
            defaultDuration: 180),
        FaultDescriptor(
            id: .dependencyRestart, name: "Restart Dependency", category: .dependency, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Stops and starts Chaos-managed dependency processes only.",
            whatItTests: "Cold reconnect, connection pool invalidation, auth re-handshake.",
            restoration: "Dependency restarted and left running.",
            defaultDuration: 60),
    ]

    // MARK: Timing

    public static let timing: [FaultDescriptor] = [
        FaultDescriptor(
            id: .timingDelay, name: "Artificial Delay", category: .timing, severity: .low, reversible: true,
            simulated: true,
            capabilityNote: "Chaos cannot slow your code's internal timers. This fault is a Chaos-owned proxy/gate used in tests, or a scheduled injection point in the Experiment Builder (e.g. delay before a process fault).",
            whatItTests: "Timeout budgets around controlled delay points.",
            restoration: "Nothing persistent.",
            defaultDuration: 30),
        FaultDescriptor(
            id: .timingJitter, name: "Random Jitter Injection", category: .timing, severity: .low, reversible: true,
            simulated: true,
            capabilityNote: "Randomized trigger times for paired faults inside an experiment; deterministic under a seed.",
            whatItTests: "Race conditions, non-deterministic ordering bugs.",
            restoration: "Nothing persistent.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .timingEscalation, name: "Escalating Conditions", category: .timing, severity: .moderate, reversible: true,
            simulated: true,
            capabilityNote: "Schedules ramping parameters for paired faults (e.g. latency 100ms → 2s over 5 minutes).",
            whatItTests: "Degradation handling over time, adaptive strategies.",
            restoration: "Nothing persistent.",
            defaultDuration: 300),
    ]

    // MARK: Lifecycle

    public static let lifecycle: [FaultDescriptor] = [
        FaultDescriptor(
            id: .lifecycleSleep, name: "Sleep During Operation", category: .lifecycle, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Requests system sleep via IOPMSleepEnable/IOPMSleepSystem (public API, user approval as with Apple menu sleep). Display sleep and idle-sleep paths are also exercisable.",
            whatItTests: "Work persistence across sleep, reconnect after wake, clock assumptions.",
            restoration: "System wakes by user action; experiment timeline continues.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .lifecycleWake, name: "Wake With Network Loss", category: .lifecycle, severity: .high, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Composes wake with a pf block so the first minute after wake has no network — the classic 'hotel Wi-Fi' wake.",
            whatItTests: "Wake → reconnect handling, optimistic resume, stale sockets.",
            restoration: "Rules removed.",
            defaultDuration: 90),
    ]

    // MARK: Device

    public static let device: [FaultDescriptor] = [
        FaultDescriptor(
            id: .deviceDisconnect, name: "Device Disconnect", category: .device, severity: .high, reversible: false, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — macOS does not expose documented APIs to unplug hardware. Chaos provides a guided drill (unplug checklist) plus Chaos-owned 'virtual device' files (e.g. a removable-like volume) that are genuinely unmounted mid-operation.",
            whatItTests: "Device-unplugged flows, partial writes to removable storage.",
            restoration: "Guided; virtual devices remounted.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .deviceVolumeDisappear, name: "Volume Disappears", category: .device, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Creates a small scratch volume (hdiutil) and unmounts it mid-experiment — a real, observable volume disappearance, fully scripted.",
            whatItTests: "Handling of vanished volumes, stale file handles, save-to-missing-disk UX.",
            restoration: "Volume remounted or deleted.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .deviceDisplaySleep, name: "Display Sleep", category: .device, severity: .low, reversible: true,
            privileges: .none,
            capabilityNote: "Uses IOPMSleep with display-only context or pmset displaysleepnow (user session).",
            whatItTests: "Rendering after display sleep, screen-recording interruptions.",
            restoration: "User wakes display.",
            defaultDuration: 10),
        FaultDescriptor(
            id: .deviceAudioSwitch, name: "Audio Output Switch", category: .device, severity: .low, reversible: true,
            simulated: true,
            capabilityNote: "SIMULATED — switches output between real devices if present, else guided drill. CoreAudio device routing is available only for devices the user has.",
            whatItTests: "Audio route changes, AVAudioSession-equivalent interruptions.",
            restoration: "Output restored to the original device when it exists.",
            defaultDuration: 30),
    ]

    // MARK: Clock

    public static let clock: [FaultDescriptor] = [
        FaultDescriptor(
            id: .clockSkew, name: "Clock Skew (Simulated)", category: .clock, severity: .moderate, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — Chaos never changes the host clock. It publishes a simulated-time feed (file + Unix socket) plus helper libraries to inject into your test builds; a guided drill covers manual TZ override.",
            whatItTests: "Token expiry math, scheduling, TTL/cache decisions under skew.",
            restoration: "Feed removed; helpers no-op.",
            defaultDuration: 120),
        FaultDescriptor(
            id: .clockDST, name: "DST Transition", category: .clock, severity: .moderate, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — launches the target with TZ set to a DST-boundary timezone via the safe process environment (per-process, system clock untouched).",
            whatItTests: "DST-boundary bugs, recurring-event math.",
            restoration: "Environment scoped to the launched process only.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .clockRollover, name: "Midnight / Rollover", category: .clock, severity: .low, reversible: true, simulated: true,
            capabilityNote: "SIMULATED — per-process timezone/offset feed; never touches the system clock.",
            whatItTests: "Date rollovers, daily jobs, log rotation boundaries.",
            restoration: "Feed removed.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .clockCertExpiry, name: "Expired Certificate Window", category: .clock, severity: .moderate, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — pairs the clock-skew feed with a local TLS endpoint using a deliberately expired certificate to exercise real trust-evaluation code.",
            whatItTests: "Cert-pinning fallbacks, expiry error UX.",
            restoration: "Endpoint and feed removed.",
            defaultDuration: 60),
    ]

    // MARK: Power

    public static let power: [FaultDescriptor] = [
        FaultDescriptor(
            id: .powerLowBattery, name: "Low Battery", category: .power, severity: .low, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — publishes a low-battery state via the Chaos status feed; apps that read IOPSCopyPowerSourcesInfo will still see real hardware. Guided drill documents expected UI.",
            whatItTests: "Low-power UI branches, reduced-quality modes.",
            restoration: "Feed removed.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .powerChargeState, name: "Charging State Change", category: .power, severity: .low, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — status feed; no hardware state is altered.",
            whatItTests: "Charge-state observers, deferrable work.",
            restoration: "Feed removed.",
            defaultDuration: 30),
        FaultDescriptor(
            id: .powerSourceSwitch, name: "AC ↔ Battery Switch", category: .power, severity: .low, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "SIMULATED — guided drill; unplug the charger when Chaos prompts you (a genuinely observable transition).",
            whatItTests: "Power-source transitions, pause/resume heuristics.",
            restoration: "Feed removed.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .powerThermal, name: "Thermal Pressure (Workload)", category: .power, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Real sustained CPU/GPU-ish workload raises thermals organically. Chaos never writes thermal state — macOS does not permit it.",
            whatItTests: "Thermal-state observers (ProcessInfo.thermalState), quality downgrades.",
            restoration: "Workers stopped; thermals recover naturally.",
            defaultDuration: 180),
        FaultDescriptor(
            id: .thermalSustainedLoad, name: "Sustained Background Load", category: .power, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Chaos-owned workers at low priority (nice +10, background QoS) to emulate background agents.",
            whatItTests: "App performance under realistic background load.",
            restoration: "Workers stopped.",
            defaultDuration: 180),
    ]

    // MARK: Misc

    public static let misc: [FaultDescriptor] = [
        FaultDescriptor(
            id: .randomChaos, name: "Random Chaos", category: .misc, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Seeded random selection from allowed categories, with hard bounds. The seed makes every run exactly reproducible.",
            whatItTests: "Unknown-unknowns across a bounded blast radius.",
            restoration: "Each injected fault restores itself; the supervisor verifies.",
            defaultDuration: 600),
        FaultDescriptor(
            id: .releaseCandidate, name: "Release Candidate Suite", category: .misc, severity: .high, reversible: true,
            privileges: .none,
            capabilityNote: "Runs the curated pre-release scenario list sequentially, each restored before the next.",
            whatItTests: "Ship-blocker discovery across all categories.",
            restoration: "Per-fault restoration with a final verified sweep.",
            defaultDuration: 1800),
        FaultDescriptor(
            id: .everythingBroken, name: "Everything Is Broken", category: .misc, severity: .extreme, reversible: true,
            privileges: .localNetworkSettings,
            capabilityNote: "Concurrent worst-case composition (offline + loss + latency + memory + disk). Explicit confirmation required; strict safety ceilings still apply.",
            whatItTests: "Complete outage behavior — the day everything fails at once.",
            restoration: "Supervisor restores all faults and verifies each.",
            defaultDuration: 180),
        FaultDescriptor(
            id: .customScript, name: "Custom Script Fault", category: .misc, severity: .moderate, reversible: true,
            privileges: .none,
            capabilityNote: "Runs a user-provided script with CHAOS_* env vars. Restore script paired with it. Reviewed at edit time for dangerous constructs (sudo, rm -rf /, etc.).",
            whatItTests: "Anything you need that's not built in.",
            restoration: "Restore script runs on stop.",
            defaultDuration: 60),
        FaultDescriptor(
            id: .customManual, name: "Guided Manual Step", category: .misc, severity: .low, reversible: true, simulated: true,
            privileges: .none,
            capabilityNote: "A checklist step the human performs (e.g. 'toggle Wi-Fi off now'). The experiment waits for your confirmation before proceeding.",
            whatItTests: "Conditions no API can create.",
            restoration: "Nothing automated.",
            defaultDuration: 60),
    ]
}

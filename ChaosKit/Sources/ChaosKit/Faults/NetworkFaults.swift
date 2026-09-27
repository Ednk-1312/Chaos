import Foundation

// MARK: - Elevation

/// Runs privileged commands via documented elevation paths:
/// direct if already root; otherwise osascript administrator prompt (GUI) or a clear failure (CLI).
public enum Elevation {
    public static var isRoot: Bool { geteuid() == 0 }

    /// Headless mode (CLI): never trigger GUI authorization dialogs. Privileged
    /// operations fail fast with an honest message instead of hanging.
    public static var isHeadless: Bool {
        ProcessInfo.processInfo.environment["CHAOS_HEADLESS"] == "1"
    }

    /// Run a script with root privileges. `allowPrompt` permits the GUI authorization dialog.
    public static func runPrivileged(_ script: String, allowPrompt: Bool = true) -> ShellResult {
        if isRoot {
            return (try? Shell.sh(script)) ?? ShellResult(exitCode: 1, stdout: "", stderr: "shell failed")
        }
        if isHeadless {
            return ShellResult(exitCode: 1, stdout: "",
                               stderr: "requires administrator authorization — run inside the Chaos app once to authorize, or run the CLI as root")
        }
        guard allowPrompt else {
            return ShellResult(exitCode: 1, stdout: "", stderr: "requires root: \(script)")
        }
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"
        return (try? Shell.run("/usr/bin/osascript", ["-e", osa], timeout: 120))
            ?? ShellResult(exitCode: 1, stdout: "", stderr: "authorization failed or was cancelled")
    }
}

// MARK: - Network State

/// Tracks dummynet pipes + anchor state so concurrent faults don't clobber each other.
final class NetworkState: @unchecked Sendable {
    static let shared = NetworkState()
    private var nextPipe = 1
    private let lock = NSLock()

    func allocatePipe() -> Int {
        lock.lock(); defer { lock.unlock() }
        defer { nextPipe += 1 }
        return nextPipe
    }
}

// MARK: - NetworkFaultRunner

/// One runner serves every network fault; behavior is driven by the FaultID.
final class NetworkFaultRunner: FaultRunner {
    let id: FaultID
    private let anchor = "com.chaos"

    init(id: FaultID) { self.id = id }

    func activate(_ context: FaultContext) async -> ActivationResult {
        let params = context.binding.parameters
        let pipe = NetworkState.shared.allocatePipe()

        switch id {
        case .networkOffline:
            return activateBlock(rule: "block drop out all", message: "All outbound traffic is now blocked (pf anchor \(anchor)).")

        case .dnsFailure:
            return activateBlock(
                rule: "block drop out proto udp from any to any port 53\nblock drop out proto tcp from any to any port 53",
                message: "DNS (port 53) is now blocked; hostname resolution will fail."
            )

        case .networkLatency:
            let ms = Int(context.doubleParam("latencyMs", default: 500))
            let ok = configurePipe(pipe, "delay \(ms)")
            guard ok else { return .failure("Could not configure dummynet pipe (authorization declined?).") }
            return activatePipeRule(pipe: pipe, message: "Latency +\(ms)ms active on all outbound traffic.")

        case .packetLoss:
            let pct = min(100, max(1, context.intParam("lossPercent", default: 20)))
            let ok = configurePipe(pipe, "plr \(String(format: "%.2f", Double(pct) / 100.0))")
            guard ok else { return .failure("Could not configure dummynet pipe.") }
            return activatePipeRule(pipe: pipe, message: "Packet loss \(pct)% active.")

        case .bandwidthCap:
            let kbps = max(8, context.intParam("bandwidthKbps", default: 1024))
            let ok = configurePipe(pipe, "bw \(kbps)Kbit/s")
            guard ok else { return .failure("Could not configure dummynet pipe.") }
            return activatePipeRule(pipe: pipe, message: "Bandwidth capped at \(kbps) Kbit/s.")

        case .jitter:
            let base = context.intParam("latencyMs", default: 150)
            let ok = configurePipe(pipe, "delay \(base) queue 4 plr 0.02")
            guard ok else { return .failure("Could not configure dummynet pipe.") }
            return activatePipeRule(pipe: pipe, message: "Jitter active around \(base)ms with small random loss.")

        case .burstLoss:
            let ok = configurePipe(pipe, "plr 1.00")
            guard ok else { return .failure("Could not configure dummynet pipe.") }
            guard activatePipeRule(pipe: pipe, message: "Burst loss active.").ok else {
                return .failure("Could not install dummynet rule.")
            }
            let period = max(2, context.intParam("periodSeconds", default: 10))
            Self.startBurstCycle(pipe: pipe, period: TimeInterval(period))
            return .success("Burst loss cycle: \(period)s out / \(period)s clean.")

        case .connectionReset:
            // Honest approximation: loss + latency spikes; true RST injection is not public API.
            let ok = configurePipe(pipe, "delay 400 plr 0.08")
            guard ok else { return .failure("Could not configure dummynet pipe.") }
            return activatePipeRule(pipe: pipe, message: "Connection-unstable profile active (loss + spikes).")

        default:
            return .failure("NetworkFaultRunner cannot execute \(id.rawValue).")
        }
    }

    func restore(_ context: FaultContext) async -> Bool {
        cancelTimers()
        // Restoration is a safety operation: use the full privilege path and
        // verify the anchor is actually empty instead of trusting an exit code.
        return FaultCleanup.restoreNetworkState()
    }

    // MARK: Internals

    private func activateBlock(rule: String, message: String) -> ActivationResult {
        let script = """
        /sbin/pfctl -E >/dev/null 2>&1; \
        echo "\(rule)" | /sbin/pfctl -a \(anchor) -f -
        """
        let r = Elevation.runPrivileged(script)
        guard r.succeeded else {
            return .failure("pf rule rejected: \(r.combinedOutput.prefix(200))")
        }
        return .success(message)
    }

    private func configurePipe(_ pipe: Int, _ config: String) -> Bool {
        Elevation.runPrivileged("/sbin/dnctl pipe \(pipe) config \(config)").succeeded
    }

    private func activatePipeRule(pipe: Int, message: String) -> ActivationResult {
        let rule = "dummynet out all pipe \(pipe)"
        let script = """
        /sbin/pfctl -E >/dev/null 2>&1; \
        echo "\(rule)" | /sbin/pfctl -a \(anchor) -f -
        """
        let r = Elevation.runPrivileged(script)
        guard r.succeeded else { return .failure("pf dummynet rule rejected.") }
        return .success(message)
    }

    // Timer registry for cyclic faults (burst loss / flap).
    private static var timers: [Timer] = []
    private static let timerLock = NSLock()
    private static var burstIsOn = false

    private func registerTimer(_ t: Timer) {
        Self.timerLock.lock(); Self.timers.append(t); Self.timerLock.unlock()
    }

    static func startBurstCycle(pipe: Int, period: TimeInterval) {
        DispatchQueue.main.async {
            burstIsOn = true
            let t = Timer(timeInterval: period, repeats: true) { _ in
                burstIsOn.toggle()
                _ = Elevation.runPrivileged(
                    "/sbin/dnctl pipe \(pipe) config plr \(burstIsOn ? "1.00" : "0.00")",
                    allowPrompt: false
                )
            }
            RunLoop.main.add(t, forMode: .common)
            timerLock.lock(); timers.append(t); timerLock.unlock()
        }
    }

    private func cancelTimers() {
        Self.timerLock.lock()
        let all = Self.timers
        Self.timers = []
        Self.timerLock.unlock()
        DispatchQueue.main.async {
            for t in all { t.invalidate() }
        }
    }
}


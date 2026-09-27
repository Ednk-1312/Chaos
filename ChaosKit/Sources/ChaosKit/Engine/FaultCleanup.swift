import Foundation

/// Safety net: removes and VERIFIES network chaos state. Verification is real —
/// a flush whose anchor still contains rules reports failure, never success.
public enum FaultCleanup {
    /// Canonical network reset + verification. Exit 0 only when the anchor is
    /// actually empty afterwards. Runs via the elevation path when needed.
    static let networkResetScript = """
    /sbin/pfctl -a com.chaos -F all >/dev/null 2>&1
    /sbin/dnctl -q flush >/dev/null 2>&1
    if /sbin/pfctl -a com.chaos -s rules 2>/dev/null | grep -q .; then
        exit 1
    fi
    exit 0
    """

    /// Reset network state and verify. Returns true only when verified clean.
    /// When `allowPrompt` is false and privileges are missing, reports failure
    /// honestly (the CLI surfaces this as “unable to verify” with instructions).
    @discardableResult
    public static func restoreNetworkState(allowPrompt: Bool = true) -> Bool {
        Elevation.runPrivileged(networkResetScript, allowPrompt: allowPrompt).succeeded
    }

    /// Boot sweep: non-interactive, best-effort (no prompting at startup).
    public static func performBootSweep() {
        _ = Elevation.runPrivileged(networkResetScript, allowPrompt: false)
    }

    /// Kill any Chaos-owned stress workers still running, by process name.
    @discardableResult
    public static func killOrphanedWorkers() -> Int {
        let procs = ProcessScanner.snapshot()
        let workers = procs.filter { $0.command.contains("chaos-stress") }
        var killed = 0
        for p in workers where kill(p.pid, SIGKILL) == 0 {
            killed += 1
        }
        return killed
    }

    /// True when no chaos-stress processes remain.
    public static func verifyNoWorkers() -> Bool {
        !ProcessScanner.snapshot().contains { $0.command.contains("chaos-stress") }
    }

    /// Full restore sweep across every subsystem Chaos can touch, each verified.
    /// CLI callers pass allowPrompt: false and surface honest “unverified” states.
    public static func restoreEverything(allowPrompt: Bool = true) -> [String: Bool] {
        var status: [String: Bool] = [:]
        status["pf rules"] = restoreNetworkState(allowPrompt: allowPrompt)
        killOrphanedWorkers()
        status["orphan workers"] = verifyNoWorkers()
        return status
    }
}

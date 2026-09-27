import Foundation

final class ProcessFaultRunner: FaultRunner {
    let id: FaultID
    static var pausedPIDs: [Int32] = []
    static var loopTasks: [DispatchWorkItem] = []
    static var launchedProcesses: [Foundation.Process] = []

    init(id: FaultID) { self.id = id }

    func activate(_ context: FaultContext) async -> ActivationResult {
        switch id {
        case .processKill, .processPause, .processRestartLoop:
            return await activateProcessFault(context)
        case .processRelaunch:
            return await activateRelaunch(context)
        case .dependencyDown, .dependencySlow, .dependencyFlap, .dependencyRestart:
            return await activateDependencyFault(context)
        default:
            return .failure("ProcessFaultRunner cannot execute \(id.rawValue).")
        }
    }

    // MARK: Target resolution

    private func targets(_ context: FaultContext) -> (pids: [Int32], names: [String]) {
        var pids: [Int32] = []
        var names: [String] = []
        if let pidStr = context.binding.parameters["pid"], let pid = Int32(pidStr) {
            pids.append(pid); names.append("pid \(pid)")
        } else if let targetID = context.binding.targetID,
                  let t = context.config.targets.first(where: { $0.id == targetID }),
                  let pid = t.pid {
            pids.append(pid); names.append(t.name)
        } else if let name = context.binding.parameters["processName"], !name.isEmpty {
            let procs = ProcessScanner.snapshot().filter { $0.shortName == name && $0.user == NSUserName() }
            pids.append(contentsOf: procs.map(\.pid))
            names.append(name)
        }
        return (pids, names)
    }

    // MARK: Process faults

    private func activateProcessFault(_ context: FaultContext) async -> ActivationResult {
        let (pids, names) = targets(context)
        guard !pids.isEmpty else {
            return .failure("No target process resolved. Pick a running process owned by your user.")
        }
        // Refuse to kill init/launchd or anything privileged.
        for pid in pids where pid <= 1 {
            return .failure("Refusing to signal pid \(pid).")
        }

        switch id {
        case .processPause:
            for pid in pids { kill(pid, SIGSTOP) }
            Self.pausedPIDs.append(contentsOf: pids)
            return .success("SIGSTOP sent to \(names.joined(separator: ", ")).")

        case .processKill:
            var killed = 0
            for pid in pids where kill(pid, SIGKILL) == 0 { killed += 1 }
            return .success("SIGKILL delivered to \(killed) process(es): \(names.joined(separator: ", ")).")

        case .processRestartLoop:
            let interval = max(5, context.intParam("intervalSeconds", default: 20))
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let (current, _) = self.targets(context)
                for pid in current where ProcessScanner.isAlive(pid) {
                    kill(pid, SIGKILL)
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + TimeInterval(interval), repeating: TimeInterval(interval))
            timer.setEventHandler { task.perform() }
            timer.resume()
            Self.loopTasks.append(task)
            Self.timerSources.append(timer)
            return .success("Restart loop: killing \(names.joined(separator: ", ")) every \(interval)s.")
        default:
            return .failure("unreachable")
        }
    }

    private func activateRelaunch(_ context: FaultContext) async -> ActivationResult {
        guard let targetID = context.binding.targetID,
              let t = context.config.targets.first(where: { $0.id == targetID }),
              t.isChaosLaunched, let path = t.path else {
            return .failure("Relaunch cycles require a target that Chaos launched (Launch + Test).")
        }
        if let pid = t.pid, ProcessScanner.isAlive(pid) {
            kill(pid, SIGTERM)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if ProcessScanner.isAlive(pid) { kill(pid, SIGKILL) }
        }
        let open = (try? Shell.run("/usr/bin/open", [path])) ?? ShellResult(exitCode: 1, stdout: "", stderr: "open failed")
        guard open.succeeded else { return .failure("Could not relaunch \(t.name).") }
        return .success("Relaunched \(t.name) — exercise its cold-start path.")
    }

    // MARK: Dependency faults

    private func activateDependencyFault(_ context: FaultContext) async -> ActivationResult {
        let port = context.intParam("port", default: 0)
        let host = context.param("host", default: "")

        switch id {
        case .dependencyDown:
            if port > 0 {
                let script = "/sbin/pfctl -E >/dev/null 2>&1; echo \"block drop out proto tcp from any to any port \(port)\" | /sbin/pfctl -a com.chaos -f -"
                let r = Elevation.runPrivileged(script)
                guard r.succeeded else { return .failure("pf rule rejected (authorization declined?).") }
                return .success("Dependency on port \(port) is now unreachable.")
            }
            let (pids, names) = targets(context)
            guard !pids.isEmpty else { return .failure("Define a port or select a process for this dependency.") }
            for pid in pids { kill(pid, SIGKILL) }
            return .success("Killed dependency process(es): \(names.joined(separator: ", ")).")

        case .dependencySlow:
            guard port > 0 else { return .failure("dependencySlow needs a port number.") }
            let pipe = NetworkState.shared.allocatePipe()
            let ms = context.intParam("latencyMs", default: 800)
            guard Elevation.runPrivileged("/sbin/dnctl pipe \(pipe) config delay \(ms)").succeeded else {
                return .failure("Could not configure pipe.")
            }
            let rule = "dummynet out proto tcp from any to any port \(port) pipe \(pipe)"
            guard Elevation.runPrivileged("echo \"\(rule)\" | /sbin/pfctl -a com.chaos -f -").succeeded else {
                return .failure("Could not install rule.")
            }
            return .success("Traffic to port \(port) delayed by \(ms)ms.")

        case .dependencyFlap:
            guard port > 0 else { return .failure("dependencyFlap needs a port number.") }
            let period = max(3, context.intParam("periodSeconds", default: 15))
            Self.startFlapCycle(port: port, period: TimeInterval(period))
            return .success("Dependency flapping: port \(port) toggles every \(period)s.")

        case .dependencyRestart:
            let (pids, names) = targets(context)
            guard !pids.isEmpty else { return .failure("Select a Chaos-managed dependency process.") }
            for pid in pids { kill(pid, SIGTERM) }
            return .success("Restart signal sent to dependency: \(names.joined(separator: ", ")).")

        default:
            return .failure("unreachable")
        }
    }

    // MARK: Flap cycle

    static var timerSources: [DispatchSourceTimer] = []
    static var flapIsBlocked = false

    static func startFlapCycle(port: Int, period: TimeInterval) {
        let src = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        src.schedule(deadline: .now() + period, repeating: period)
        src.setEventHandler {
            flapIsBlocked.toggle()
            let rule = flapIsBlocked
                ? "block drop out proto tcp from any to any port \(port)"
                : "pass out proto tcp from any to any port \(port)"
            _ = Elevation.runPrivileged("echo \"\(rule)\" | /sbin/pfctl -a com.chaos -f -", allowPrompt: false)
        }
        src.resume()
        timerSources.append(src)
    }

    // MARK: Restore

    func restore(_ context: FaultContext) async -> Bool {
        var ok = true
        for pid in Self.pausedPIDs where ProcessScanner.isAlive(pid) {
            if kill(pid, SIGCONT) != 0 { ok = false }
        }
        Self.pausedPIDs.removeAll()

        for src in Self.timerSources { src.cancel() }
        Self.timerSources.removeAll()

        if [.dependencyDown, .dependencySlow, .dependencyFlap].contains(id) {
            ok = ok && Elevation.runPrivileged(
                "/sbin/pfctl -a com.chaos -F all 2>/dev/null; /sbin/dnctl -q flush 2>/dev/null; exit 0",
                allowPrompt: false
            ).succeeded
        }
        return ok
    }
}

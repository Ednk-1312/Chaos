import Foundation

/// CPU + memory pressure via Chaos-owned worker processes.
/// Workers are small, purpose-built processes so Chaos itself stays responsive and
/// a crashed engine can always kill them by name. Hard safety ceilings are enforced here.
public enum ResourceSafety {
    /// Always leave this much RAM free, or 25% of physical memory — whichever is larger.
    public static func memoryCeilingBytes() -> UInt64 {
        let total = ProcessInfo.processInfo.physicalMemory
        let floorBytes: UInt64 = 2_000_000_000
        return max(floorBytes, total / 4)
    }

    public static func freeMemoryBytes() -> UInt64 {
        let r = (try? Shell.sh("vm_stat")) ?? ShellResult(exitCode: 1, stdout: "", stderr: "")
        // vm_stat reports pages; page size is 4096 on all supported Macs.
        var free: UInt64 = 0
        for line in r.stdout.split(separator: "\n") {
            if line.contains("Pages free"), let n = Int(line.components(separatedBy: ": ")[1].replacingOccurrences(of: ".", with: "")) {
                free += UInt64(n)
            }
            if line.contains("Pages purgeable"), let n = Int(line.components(separatedBy: ": ")[1].replacingOccurrences(of: ".", with: "")) {
                free += UInt64(n) // treat purgeable as reclaimable
            }
        }
        return free * 4096
    }

    public static func safeAllocationBytes(desired: UInt64) -> UInt64 {
        let free = freeMemoryBytes()
        let headroom = memoryCeilingBytes()
        guard free > headroom else { return 0 }
        return min(desired, free - headroom)
    }
}

/// Builds and supervises chaos-stress worker processes.
public final class StressWorkerSupervisor: @unchecked Sendable {
    public static let shared = StressWorkerSupervisor()

    private var workers: [pid_t] = []
    private let lock = NSLock()

    public var workerPIDs: [pid_t] {
        lock.lock(); defer { lock.unlock() }
        return workers
    }

    var workerBinaryPath: String {
        // Candidates in priority order: app bundle (GUI), next to this executable
        // (bundled CLI), SPM product and build directories (development CLI).
        var candidates: [String] = []
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/chaos-stress").path)
        if let first = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: first).deletingLastPathComponent()
                .appendingPathComponent("chaos-stress").path)
        }
        candidates.append("./.build/out/Products/Debug/chaos-stress")
        candidates.append("./.build/release/chaos-stress")
        candidates.append("./.build/debug/chaos-stress")
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return candidates[0]
    }

    /// Spawn CPU workers. utilization: 1–100, threadCount: 1–16.
    @discardableResult
    public func startCPUWorkers(utilization: Int, threadCount: Int, durationSeconds: Int) -> [pid_t] {
        let clampedUtil = min(100, max(1, utilization))
        let clampedThreads = min(16, max(1, threadCount))
        var spawned: [pid_t] = []
        var newPIDs: [pid_t] = []
        for _ in 0..<clampedThreads {
            let task = Foundation.Process()
            task.executableURL = URL(fileURLWithPath: workerBinaryPath)
            task.arguments = ["--mode", "cpu", "--util", "\(clampedUtil)", "--duration", "\(durationSeconds)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                spawned.append(task.processIdentifier)
                newPIDs.append(task.processIdentifier)
            } catch {
                continue
            }
        }
        lock.lock(); workers.append(contentsOf: newPIDs); lock.unlock()
        return spawned
    }

    /// Spawn memory workers allocating up to `bytes` total, respecting the safety ceiling.
    @discardableResult
    public func startMemoryWorkers(bytes: UInt64, durationSeconds: Int) -> (spawned: Int, allocated: UInt64) {
        let safe = ResourceSafety.safeAllocationBytes(desired: bytes)
        guard safe > 0 else { return (0, 0) }
        // Four workers split the allocation.
        let perWorker = safe / 4
        var spawned = 0
        var newPIDs: [pid_t] = []
        for _ in 0..<4 {
            let task = Foundation.Process()
            task.executableURL = URL(fileURLWithPath: workerBinaryPath)
            task.arguments = ["--mode", "mem", "--bytes", "\(perWorker)", "--duration", "\(durationSeconds)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                spawned += 1
                newPIDs.append(task.processIdentifier)
            } catch {
                continue
            }
        }
        lock.lock(); workers.append(contentsOf: newPIDs); lock.unlock()
        return (spawned, safe)
    }

    private func allWorkerPIDs() -> [pid_t] { workers }

    /// Kill and verify all workers. Returns true when none remain alive.
    @discardableResult
    public func stopAll() -> Bool {
        lock.lock()
        let pids = workers
        workers = []
        lock.unlock()
        for pid in pids { kill(pid, SIGKILL) }
        Thread.sleep(forTimeInterval: 0.3)
        return pids.allSatisfy { !ProcessScanner.isAlive($0) }
    }
}

// MARK: - Runner

final class ResourceFaultRunner: FaultRunner {
    let id: FaultID

    init(id: FaultID) { self.id = id }

    func activate(_ context: FaultContext) async -> ActivationResult {
        let duration = max(5, Int(context.binding.duration))
        switch id {
        case .cpuLoad:
            let utilization = min(100, max(1, context.intParam("utilization", default: 80)))
            let threads = min(16, max(1, context.intParam("threads", default: max(2, ProcessInfo.processInfo.activeProcessorCount / 2))))
            let pids = StressWorkerSupervisor.shared.startCPUWorkers(
                utilization: utilization, threadCount: threads, durationSeconds: duration
            )
            guard !pids.isEmpty else {
                return .failure("Could not spawn stress workers (binary missing?).")
            }
            return .success("CPU pressure: \(threads) worker(s) at ~\(utilization)% for \(duration)s.")

        case .memoryPressure:
            let gb = context.doubleParam("gigabytes", default: 2.0)
            let desired = UInt64(gb * 1_000_000_000)
            let (spawned, allocated) = StressWorkerSupervisor.shared.startMemoryWorkers(
                bytes: desired, durationSeconds: duration
            )
            guard spawned > 0, allocated > 0 else {
                return .failure("Safety ceiling hit — refusing to allocate (system too low on memory).")
            }
            let note = allocated < desired
                ? " (capped by safety ceiling; requested \(Int(gb)) GB)"
                : ""
            return .success("Memory pressure: \(spawned) workers holding \(ByteCount.string(allocated)) for \(duration)s\(note).")

        case .powerThermal, .thermalSustainedLoad:
            let utilization = id == .powerThermal ? 90 : 35
            let threads = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
            let pids = StressWorkerSupervisor.shared.startCPUWorkers(
                utilization: utilization, threadCount: threads, durationSeconds: duration
            )
            guard !pids.isEmpty else { return .failure("Could not spawn stress workers.") }
            return .success("Sustained load: \(threads) worker(s) at ~\(utilization)% for \(duration)s.")

        default:
            return .failure("ResourceFaultRunner cannot execute \(id.rawValue).")
        }
    }

    func restore(_ context: FaultContext) async -> Bool {
        StressWorkerSupervisor.shared.stopAll()
        // Verify: no chaos-stress processes remain.
        let procs = ProcessScanner.snapshot()
        return procs.allSatisfy { !$0.command.contains("chaos-stress") }
    }
}

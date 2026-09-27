import Foundation

// MARK: - Shell

/// Thin, dependency-free wrapper for running shell commands with structured results.
public struct ShellResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public var succeeded: Bool { exitCode == 0 }
    public var combinedOutput: String { stdout + "\n" + stderr }
}

public enum ShellError: LocalizedError {
    case launchFailed(String)
    public var errorDescription: String? {
        switch self { case .launchFailed(let why): return "Could not launch helper: \(why)" }
    }
}

public enum Shell {
    /// Run a command with arguments (no shell interpretation — safe by construction).
    @discardableResult
    public static func run(
        _ launchPath: String, _ arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) throws -> ShellResult {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes concurrently while the process runs. Reading only
        // after exit deadlocks once output exceeds the OS pipe buffer: the
        // child blocks writing while we block waiting for it to exit (observed
        // with large `ps -axo` tables on busy machines).
        final class PipeBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
            var value: Data { lock.lock(); defer { lock.unlock() }; return data }
        }
        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { outBuffer.append(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { errBuffer.append(chunk) }
        }

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        // Stop collecting, then pick up anything still buffered (immediate at EOF).
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        let outData = outBuffer.value + outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errBuffer.value + errPipe.fileHandleForReading.readDataToEndOfFile()

        if timedOut {
            return ShellResult(exitCode: -1,
                               stdout: String(data: outData, encoding: .utf8) ?? "",
                               stderr: "timed out after \(Int(timeout))s")
        }
        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Run a command through /bin/sh -c (used only for fixed, Chaos-authored command lines).
    @discardableResult
    public static func sh(_ command: String, timeout: TimeInterval = 30) throws -> ShellResult {
        try run("/bin/sh", ["-c", command], timeout: timeout)
    }

    public static func which(_ tool: String) -> String? {
        (try? run("/usr/bin/which", [tool]))?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Process Table

public struct ProcessInfoSnapshot: Identifiable, Hashable {
    public var pid: Int32
    public var ppid: Int32
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var rssBytes: UInt64
    public var command: String
    public var user: String

    public var id: Int32 { pid }
    public var shortName: String {
        let parts = command.split(separator: "/")
        return parts.last.map(String.init) ?? command
    }
    public var isApp: Bool { command.hasSuffix(".app/Contents/MacOS/") || command.contains(".app/Contents/MacOS/") }
}

public enum ProcessScanner {
    /// Snapshot the running process table via ps (documented tool, no private API).
    public static func snapshot() -> [ProcessInfoSnapshot] {
        guard let result = try? Shell.run(
            "/bin/ps", ["-axo", "pid=,ppid=,%cpu=,%mem=,rss=,user=,comm="], timeout: 10
        ) else { return [] }

        var processes: [ProcessInfoSnapshot] = []
        for line in result.stdout.split(separator: "\n") {
            // ps pads columns with spaces; trim, then split preserving the
            // command (last column) which may itself contain spaces.
            let trimmed = Substring(line).trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard parts.count >= 7,
                  let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]), let mem = Double(parts[3]),
                  let rss = UInt64(parts[4])
            else { continue }
            processes.append(ProcessInfoSnapshot(
                pid: pid, ppid: ppid, cpuPercent: cpu, memoryPercent: mem,
                rssBytes: rss * 1024, command: String(parts[6]), user: String(parts[5])
            ))
        }
        return processes
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// Best-effort app bundle path for a running GUI application.
    public static func appPath(for pid: Int32) -> String? {
        guard let result = try? Shell.run("/bin/ps", ["-p", "\(pid)", "-o", "comm="], timeout: 5) else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All running GUI applications (LSDocumentation: NSRunningApplication on the app side).
    public static func guiApplications() -> [(name: String, bundleID: String, pid: Int32, localizedName: String)] {
        // Implemented on the app side via NSRunningApplication; engine returns ps fallback.
        snapshot()
            .filter { $0.isApp && $0.user == NSUserName() }
            .map { (name: $0.shortName, bundleID: "", pid: $0.pid, localizedName: $0.shortName) }
    }
}

// MARK: - Formatting

public enum ByteCount {
    public static func string(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

public extension Double {
    var asPercentString: String { String(format: "%.0f%%", self) }
}

public extension TimeInterval {
    var asClockString: String {
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

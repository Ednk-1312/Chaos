import Foundation

/// Live system stats. Sampled via documented tools (top -l1 / vm_stat / df) with a
/// low sampling rate — the monitor itself must stay nearly free.
public struct SystemStats: Codable, Hashable, Sendable {
    public var cpuUsagePercent: Double
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var memoryCompressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var diskFreeBytes: UInt64
    public var diskTotalBytes: UInt64
    public var networkInBytesPerSec: Double
    public var networkOutBytesPerSec: Double
    public var processCount: Int
    public var capturedAt: Date
}

public final class SystemMonitor: @unchecked Sendable {
    public static let shared = SystemMonitor()
    private var lastNet: (bytesIn: UInt64, bytesOut: UInt64, at: Date)?
    private let lock = NSLock()

    public func sample() -> SystemStats {
        lock.lock(); defer { lock.unlock() }

        let pi = ProcessInfo.processInfo
        let totalMem = pi.physicalMemory

        // CPU via top (one line, cheap enough at UI sample rates of 1–3s).
        var cpu: Double = 0
        if let r = try? Shell.run("/usr/bin/top", ["-l", "1", "-n", "0"], timeout: 8) {
            for line in r.stdout.split(separator: "\n") where line.contains("CPU usage") {
                // "CPU usage: 12.34% user, 5.67% sys, 81.99% idle"
                let parts = line.split(separator: ",")
                if let user = parts.first(where: { $0.contains("user") })?.split(separator: "%").first,
                   let sys = parts.first(where: { $0.contains("sys") })?.split(separator: "%").first,
                   let u = Double(user.split(separator: " ").last ?? ""), let s = Double(sys.split(separator: " ").last ?? "") {
                    cpu = min(100, u + s)
                }
            }
        }

        // Memory via vm_stat.
        var used: UInt64 = 0, compressed: UInt64 = 0, swap: UInt64 = 0, free: UInt64 = 0
        if let r = try? Shell.sh("vm_stat") {
            func pageValue(_ key: String) -> UInt64? {
                for line in r.stdout.split(separator: "\n") where line.contains(key) {
                    let digits = line.filter { $0.isNumber }
                    return UInt64(digits).map { $0 * 4096 }
                }
                return nil
            }
            free = (pageValue("Pages free") ?? 0) + (pageValue("Pages speculative") ?? 0)
            used = pageValue("Pages active").map { $0 + (pageValue("Pages wired") ?? 0) } ?? 0
            compressed = pageValue("Pages stored in compressor") ?? 0
            swap = pageValue("Swapins") ?? 0
        }

        // Disk via df.
        var diskFree: UInt64 = 0, diskTotal: UInt64 = 0
        if let r = try? Shell.run("/bin/df", ["-k", "/"], timeout: 5) {
            let lines = r.stdout.split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true) }
            if lines.count >= 2, lines[1].count >= 4,
               let totalKB = UInt64(lines[1][1]), let availKB = UInt64(lines[1][3]) {
                diskTotal = totalKB * 1024
                diskFree = availKB * 1024
            }
        }

        // Network via netstat deltas.
        var netIn: Double = 0, netOut: Double = 0
        if let r = try? Shell.run("/usr/sbin/netstat", ["-ibn"], timeout: 5) {
            var inBytes: UInt64 = 0, outBytes: UInt64 = 0
            for line in r.stdout.split(separator: "\n") {
                let cols = line.split(separator: " ", omittingEmptySubsequences: true)
                // en* interfaces only, skip headers and loopback
                if cols.count >= 10, cols[0].hasPrefix("en"), cols[2] != "*" {
                    inBytes += UInt64(cols[6]) ?? 0
                    outBytes += UInt64(cols[9]) ?? 0
                }
            }
            let now = Date()
            if let last = lastNet, now.timeIntervalSince(last.at) > 0.3 {
                let dt = now.timeIntervalSince(last.at)
                netIn = Double(inBytes &- last.bytesIn) / dt
                netOut = Double(outBytes &- last.bytesOut) / dt
            }
            lastNet = (inBytes, outBytes, now)
        }

        let processCount = pi.activeProcessorCount // placeholder replaced below by ps count when cheap

        return SystemStats(
            cpuUsagePercent: cpu,
            memoryUsedBytes: used,
            memoryTotalBytes: totalMem,
            memoryCompressedBytes: compressed,
            swapUsedBytes: swap,
            diskFreeBytes: diskFree,
            diskTotalBytes: diskTotal,
            networkInBytesPerSec: max(0, netIn),
            networkOutBytesPerSec: max(0, netOut),
            processCount: processCount,
            capturedAt: Date()
        )
    }
}

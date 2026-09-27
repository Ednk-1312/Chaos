// chaos-stress — a tiny, purpose-built load generator used by the Chaos engine.
// Modes:
//   --mode cpu --util N --duration S     : busy-wait duty cycle ≈ N%
//   --mode mem --bytes N --duration S    : allocate+touch N bytes, hold for S seconds
// Safety: it never exceeds its orders; the engine kills it on stop/restore.

import Foundation

var mode = "cpu"
var util = 80
var bytes: UInt64 = 0
var duration = 60

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    switch flag {
    case "--mode": mode = args.isEmpty ? mode : args.removeFirst()
    case "--util": util = args.isEmpty ? util : (Int(args.removeFirst()) ?? util)
    case "--bytes": bytes = args.isEmpty ? bytes : (UInt64(args.removeFirst()) ?? bytes)
    case "--duration": duration = args.isEmpty ? duration : (Int(args.removeFirst()) ?? duration)
    default: break
    }
}

let deadline = Date().addingTimeInterval(TimeInterval(duration))

if mode == "mem" {
    // Allocate and touch pages, then hold.
    var buffer: [UInt8] = []
    if bytes > 0 {
        buffer.reserveCapacity(Int(min(bytes, UInt64(Int.max / 2))))
        let chunk = [UInt8](repeating: 0xA5, count: 1 << 20) // 1 MB
        var remaining = Int(min(bytes, UInt64(Int.max / 2)))
        while remaining > 0 && Date() < deadline {
            let n = min(remaining, chunk.count)
            buffer.append(contentsOf: chunk[0..<n])
            remaining -= n
        }
    }
    // Hold until deadline; touch pages periodically so they stay resident.
    while Date() < deadline {
        for i in stride(from: 0, to: buffer.count, by: 4096) {
            buffer[i] = buffer[i] &+ 1
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
} else {
    // CPU duty cycle: busy-wait bursts sized to approximate the requested utilization.
    let utilization = Double(min(100, max(1, util))) / 100.0
    let slice: TimeInterval = 0.1
    while Date() < deadline {
        let start = Date()
        let busyFor = slice * utilization
        while Date().timeIntervalSince(start) < busyFor {
            _ = UInt64.random(in: 0..<UInt64.max)
        }
        let busyActual = Date().timeIntervalSince(start)
        if busyActual < slice {
            Thread.sleep(forTimeInterval: slice - busyActual)
        }
    }
}

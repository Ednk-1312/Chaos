import Foundation

/// Deterministic seeded random fault planning for Random Chaos mode.
/// Same seed + same settings ⇒ the exact same experiment, every time.
public enum RandomChaosPlanner {
    public struct Plan: Sendable {
        public var bindings: [FaultBinding]
        public var seed: UInt64
        public var duration: TimeInterval
    }

    public static func plan(
        seed: UInt64,
        duration: TimeInterval,
        allowedCategories: [FaultCategory],
        maxSeverity: Severity,
        concurrency: Int = 2
    ) -> Plan {
        var rng = SplitMix64(seed: seed)

        let eligible = FaultCatalog.all.filter { descriptor in
            DefaultFaultRegistry.runner(for: descriptor.id) != nil
                && allowedCategories.contains(descriptor.category)
                && descriptor.severity <= maxSeverity
        }

        var bindings: [FaultBinding] = []
        guard !eligible.isEmpty, duration >= 10 else {
            return Plan(bindings: [], seed: seed, duration: duration)
        }

        let windowCount = max(1, Int(duration / 45)) // a fault window every ~45s
        for i in 0..<windowCount {
            let descriptor = eligible[Int(rng.next() % UInt64(eligible.count))]
            let start = TimeInterval((i * 45) + Int(rng.next() % 20))
            let dur = min(duration - start, 30 + TimeInterval(rng.next() % 60))
            guard dur > 5 else { continue }

            var parameters: [String: String] = [:]
            switch descriptor.id {
            case .networkLatency:
                let ms = [100, 250, 500, 1000, 2000][Int(rng.next() % 5)]
                parameters["latencyMs"] = "\(ms)"
            case .packetLoss:
                parameters["lossPercent"] = "\(5 + Int(rng.next() % 30))"
            case .bandwidthCap:
                let kbps = [256, 512, 1500, 4000][Int(rng.next() % 4)]
                parameters["bandwidthKbps"] = "\(kbps)"
            case .cpuLoad:
                parameters["utilization"] = "\(40 + Int(rng.next() % 55))"
            case .memoryPressure:
                parameters["gigabytes"] = "\(1 + Int(rng.next() % 5))"
            case .burstLoss:
                parameters["periodSeconds"] = "\(15 + Int(rng.next() % 45))"
            default:
                break
            }

            bindings.append(FaultBinding(
                faultID: descriptor.id,
                startOffset: start,
                duration: dur,
                parameters: parameters,
                severity: descriptor.severity
            ))
        }

        // Keep only the most severe N concurrent windows — bounded blast radius.
        let sorted = bindings.sorted { $0.startOffset < $1.startOffset }
        var accepted: [FaultBinding] = []
        for binding in sorted {
            let concurrent = accepted.filter {
                $0.startOffset < binding.startOffset + binding.duration
                    && binding.startOffset < $0.startOffset + $0.duration
            }
            if concurrent.count < max(1, concurrency) {
                accepted.append(binding)
            }
        }

        return Plan(bindings: accepted, seed: seed, duration: duration)
    }
}

/// Small, dependency-free deterministic PRNG (public-domain algorithm).
struct SplitMix64: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

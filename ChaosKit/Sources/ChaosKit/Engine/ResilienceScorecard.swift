import Foundation

/// Aggregates assertion outcomes by fault category across experiment history.
///
/// Evidence-only: every number here is derived from recorded assertion
/// outcomes on real experiment records. Nothing is invented — a category
/// without runs simply doesn't appear, and pending/unresolved outcomes are
/// reported as such rather than folded into pass or fail.
public struct ResilienceScorecard: Sendable, Equatable {
    /// One fault category's aggregated outcomes.
    public struct Entry: Sendable, Equatable, Identifiable {
        public var category: FaultCategory
        /// Every record containing at least one enabled binding in this category.
        public var records: [ExperimentRecord]
        /// Per-record assertion outcome tallies, index-aligned with `records`.
        public var passed: [Int]
        public var failed: [Int]
        public var pending: [Int]
        public var skipped: [Int]
        public var inconclusive: [Int]
        /// Distinct fault IDs exercised in this category, with run counts.
        public var faultCounts: [FaultID: Int]

        public var id: String { category.rawValue }

        public init(category: FaultCategory, records: [ExperimentRecord]) {
            self.category = category
            self.records = records
            var passed: [Int] = [], failed: [Int] = [], pending: [Int] = []
            var skipped: [Int] = [], inconclusive: [Int] = []
            var faultCounts: [FaultID: Int] = [:]
            for record in records {
                // Which of the record's assertions belong to faults of this category?
                let categoryFaultIDs = Set(
                    record.config.bindings
                        .filter { $0.enabled && $0.faultID.category == category }
                        .map { $0.faultID }
                )
                for binding in record.config.bindings
                where binding.enabled && binding.faultID.category == category {
                    faultCounts[binding.faultID, default: 0] += 1
                }
                if categoryFaultIDs.isEmpty {
                    // Unreachable via ResilienceScorecard's grouping (records are
                    // only grouped into categories they exercise), but kept for
                    // direct Entry consumers.
                    passed.append(0); failed.append(0); pending.append(0)
                    skipped.append(0); inconclusive.append(0)
                    continue
                }
                // Attribute each assertion to ALL categories the record
                // exercises — a record with network + memory faults counts in
                // both rows. A failed assertion is evidence for every fault
                // category that was active when it was evaluated.
                var p = 0, f = 0, pen = 0, sk = 0, inc = 0
                for assertion in record.config.assertions {
                    switch record.assertionResults[assertion.id] ?? .pending {
                    case .passed: p += 1
                    case .failed: f += 1
                    case .pending: pen += 1
                    case .skipped: sk += 1
                    case .inconclusive: inc += 1
                    }
                }
                passed.append(p); failed.append(f); pending.append(pen)
                skipped.append(sk); inconclusive.append(inc)
            }
            self.passed = passed
            self.failed = failed
            self.pending = pending
            self.skipped = skipped
            self.inconclusive = inconclusive
            self.faultCounts = faultCounts
        }

        public var totalPassed: Int { passed.reduce(0, +) }
        public var totalFailed: Int { failed.reduce(0, +) }
        public var totalPending: Int { pending.reduce(0, +) }
        public var totalSkipped: Int { skipped.reduce(0, +) }
        public var totalInconclusive: Int { inconclusive.reduce(0, +) }
        public var runCount: Int { records.count }
        public var distinctFaultCount: Int { faultCounts.keys.count }

        /// Sorted (fault, runCount) pairs, most-run first — for display.
        public var faultsByRuns: [(FaultID, Int)] {
            faultCounts.map { ($0.key, $0.value) }.sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.rawValue < rhs.0.rawValue
            }
        }

        /// Categories sorted by failure evidence, then alphabetically. Rows
        /// with the most to act on float to the top; untested categories still
        /// appear (with zero counts) so gaps are visible.
        public static func sorted(_ entries: [Entry]) -> [Entry] {
            entries.sorted { lhs, rhs in
                if lhs.totalFailed != rhs.totalFailed { return lhs.totalFailed > rhs.totalFailed }
                if lhs.runCount != rhs.runCount { return lhs.runCount > rhs.runCount }
                return lhs.category.rawValue < rhs.category.rawValue
            }
        }
    }

    /// All categories that have at least one record, sorted by failure
    /// evidence. Categories never exercised do not appear.
    public var entries: [Entry]

    public init(records: [ExperimentRecord]) {
        var byCategory: [FaultCategory: [ExperimentRecord]] = [:]
        for record in records {
            var categories = Set<FaultCategory>()
            for binding in record.config.bindings where binding.enabled {
                categories.insert(binding.faultID.category)
            }
            for category in categories { byCategory[category, default: []].append(record) }
        }
        entries = Entry.sorted(byCategory.map { Entry(category: $0.key, records: $0.value) })
    }

    /// Records are deduplicated within each entry; a record may appear in
    /// several entries. Distinct records across the whole scorecard:
    public var distinctRecordCount: Int { Set(entries.flatMap { $0.records.map(\.id) }).count }

    public func entry(for category: FaultCategory) -> Entry? {
        entries.first { $0.category == category }
    }
}

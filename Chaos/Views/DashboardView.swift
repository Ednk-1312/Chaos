import SwiftUI
import ChaosKit

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel

    private let quickStart: [(String, String, String, Scenario)] = [
        ("Bad Network", "wifi.slash", "Full offline or brutal latency",
         ScenarioLibrary.all.first { $0.id == "terrible-wifi" }!),
        ("Low Disk", "internaldrive", "A volume that's nearly full",
         ScenarioLibrary.all.first { $0.id == "nearly-full-disk" }!),
        ("Memory Pressure", "memorychip", "Real allocation pressure",
         ScenarioLibrary.all.first { $0.id == "memory-moderate" }!),
        ("Dependency Failure", "antenna.radiowaves.left.and.right.slash", "One backend goes dark",
         ScenarioLibrary.all.first { $0.id == "server-outage" }!),
        ("Permission Failure", "lock", "Access denied paths",
         ScenarioLibrary.all.first { $0.id == "dir-access-denied" }!),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if app.isRunning {
                    ActiveChaosCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What do you want to break?")
                        .font(.largeTitle.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(quickStart, id: \.0) { item in
                            QuickStartCard(title: item.0, symbol: item.1, subtitle: item.2) {
                                app.startExperiment(scenario: item.3, targets: app.primaryTarget.map { [$0] } ?? [])
                            }
                        }
                        QuickStartCard(title: "Random Chaos", symbol: "dice", subtitle: "Seeded, reproducible mayhem") {
                            app.selectedSection = .randomChaos
                        }
                        QuickStartCard(title: "Custom Experiment", symbol: "wand.and.stars", subtitle: "Build a fault timeline in the visual builder") {
                            app.showExperimentBuilder = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Failures")
                        .font(.title2.bold())
                    let failures = app.history.filter { $0.outcome == .failed }
                    if failures.isEmpty {
                        Text(app.history.isEmpty
                             ? "Run experiments to build a failure archive — every outcome is recorded with evidence."
                             : "No failed experiments yet.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(failures.prefix(5)) { record in
                            Button {
                                app.selectedSection = .history
                            } label: {
                                RecentExperimentRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Resilience")
                        .font(.title2.bold())
                    ResilienceSummary(records: Array(app.history.prefix(10)))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("System Health")
                        .font(.title2.bold())
                    SystemHealthRow(stats: app.systemStats)
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
    }
}

struct QuickStartCard: View {
    let title: String
    let symbol: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(title)")
    }
}

struct ActiveChaosCard: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Text("CHAOS ACTIVE")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                Spacer()
                if let started = app.liveRecord?.startedAt {
                    Text("elapsed \(Date.now.timeIntervalSince(started).asClockString)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let record = app.liveRecord {
                Text(record.config.bindings.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("View Live") {
                    app.selectedSection = .liveMonitor
                }
                Button("STOP CHAOS", role: .destructive) { app.emergencyStop() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.4)))
    }
}

struct SystemHealthRow: View {
    let stats: SystemStats?

    var body: some View {
        HStack(spacing: 12) {
            if let s = stats {
                HealthCard(title: "CPU", value: s.cpuUsagePercent.asPercentString, symbol: "cpu")
                HealthCard(title: "Memory",
                           value: ByteCount.string(s.memoryUsedBytes),
                           symbol: "memorychip")
                HealthCard(title: "Disk Free",
                           value: ByteCount.string(s.diskFreeBytes),
                           symbol: "internaldrive")
                HealthCard(title: "Network ↓",
                           value: ByteCount.string(UInt64(s.networkInBytesPerSec)) + "/s",
                           symbol: "arrow.down")
            } else {
                ProgressView()
                    .frame(height: 60)
            }
        }
    }
}

struct HealthCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

/// Transparent resilience summary: derived only from recorded assertion outcomes.
struct ResilienceSummary: View {
    let records: [ExperimentRecord]

    var body: some View {
        if records.isEmpty {
            Text("Run experiments to build a resilience picture — every assertion outcome feeds this summary.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        } else {
            let passed = records.reduce(0) { $0 + $1.assertionSummary.passed }
            let failed = records.reduce(0) { $0 + $1.assertionSummary.failed }
            let pending = records.reduce(0) { $0 + $1.assertionSummary.pending }
            let failedExperiments = records.filter { $0.outcome == .failed }
            HStack(spacing: 12) {
                HealthCard(title: "Passed", value: "\(passed)", symbol: "checkmark.seal.fill")
                HealthCard(title: "Failed", value: "\(failed)", symbol: "xmark.octagon.fill")
                HealthCard(title: "Inconclusive", value: "\(pending)", symbol: "questionmark.diamond")
                HealthCard(title: "Runs", value: "\(records.count)", symbol: "flask")
            }
            // Evidence-only breakdown by check type — no invented scores.
            ByCheckTypeBreakdown(records: records)
            if !failedExperiments.isEmpty {
                Text("Failures needing attention: " + failedExperiments.map(\.config.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Per-check-type pass/fail counts, derived strictly from recorded assertion
/// outcomes. No scores are invented.
struct ByCheckTypeBreakdown: View {
    let records: [ExperimentRecord]

    private var breakdown: [(String, Int, Int)] {
        var passed: [String: Int] = [:]
        var total: [String: Int] = [:]
        for record in records {
            for assertion in record.config.assertions {
                total[assertion.kind.rawValue, default: 0] += 1
                if record.assertionResults[assertion.id] == .passed {
                    passed[assertion.kind.rawValue, default: 0] += 1
                }
            }
        }
        return total.keys.sorted().compactMap { kind in
            guard let total = total[kind], total > 0 else { return nil }
            return (kind, passed[kind] ?? 0, total)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(breakdown, id: \.0) { kind, passed, total in
                HStack(spacing: 8) {
                    Text(kind).font(.caption)
                    Spacer()
                    Text("\(passed) / \(total) passed")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(passed == total ? .green : .secondary)
                }
            }
        }
    }
}

struct RecentExperimentRow: View {
    let record: ExperimentRecord

    var body: some View {
        HStack {
            Image(systemName: record.outcome.symbolName)
                .foregroundStyle(record.outcome == .passed ? .green : record.outcome == .failed ? .red : .orange)
            VStack(alignment: .leading) {
                Text(record.config.name).font(.headline)
                Text("\(record.config.bindings.count) faults · seed \(record.config.seed)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.startedAt.map { DashboardView.dateFormatter.string(from: $0) } ?? "")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f
    }()
}

extension DashboardView {
    static var dateFormatter: DateFormatter { RecentExperimentRow.dateFormatter }
}

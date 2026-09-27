import SwiftUI
import ChaosKit

/// Resilience Scorecard — aggregates assertion outcomes by fault category
/// across all recorded history, with click-through to the matching
/// experiments in History. Evidence-only: every number is derived from
/// recorded assertion results; pending and inconclusive outcomes are shown
/// as such, never folded into pass or fail.
struct ResilienceScorecardView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if app.history.isEmpty {
                    EmptyStateView(
                        symbol: "gauge.with.needle",
                        title: "NO EVIDENCE YET",
                        message: "The scorecard aggregates assertion outcomes by fault category once experiments have run and recorded results.",
                        buttonTitle: "Create Experiment"
                    ) { app.showExperimentBuilder = true }
                } else {
                    let card = ResilienceScorecard(records: app.history)
                    ScorecardSummaryLine(card: card)
                    ForEach(card.entries) { entry in
                        CategoryScorecardRow(entry: entry) {
                            // Click-through: scope History to exactly this
                            // category's experiments and preselect the first.
                            app.historyScope = HistoryScope(
                                title: entry.category.title,
                                symbolName: entry.category.symbolName,
                                recordIDs: Set(entry.records.map(\.id))
                            )
                            app.pendingHistorySelection = entry.records.first?.id
                            app.selectedSection = .history
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Scorecard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Resilience Scorecard").font(.largeTitle.bold())
            Text("Assertion outcomes grouped by the fault categories each experiment exercised. Click a category to see its experiments in History.")
                .foregroundStyle(.secondary)
        }
    }
}

/// One-line rollup across every category.
struct ScorecardSummaryLine: View {
    let card: ResilienceScorecard

    var body: some View {
        let passed = card.entries.reduce(0) { $0 + $1.totalPassed }
        let failed = card.entries.reduce(0) { $0 + $1.totalFailed }
        let pending = card.entries.reduce(0) { $0 + $1.totalPending + $1.totalSkipped + $1.totalInconclusive }
        return HStack(spacing: 16) {
            Label("\(card.distinctRecordCount) experiments", systemImage: "flask")
            Label("\(card.entries.count) categories", systemImage: "square.stack.3d.up")
            Label("\(passed) passed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(passed > 0 ? .green : .secondary)
            Label("\(failed) failed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(failed > 0 ? .red : .secondary)
            Label("\(pending) unresolved", systemImage: "questionmark.circle")
                .foregroundStyle(pending > 0 ? .orange : .secondary)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

/// One fault category's aggregated row, clickable through to History.
struct CategoryScorecardRow: View {
    let entry: ResilienceScorecard.Entry
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: entry.category.symbolName)
                        .foregroundStyle(entry.totalFailed > 0 ? Color.red : Color.secondary)
                    Text(entry.category.title).font(.headline)
                    Spacer()
                    Text("\(entry.runCount) run\(entry.runCount == 1 ? "" : "s") · \(entry.distinctFaultCount) fault\(entry.distinctFaultCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                OutcomeBar(
                    passed: entry.totalPassed,
                    failed: entry.totalFailed,
                    other: entry.totalPending + entry.totalSkipped + entry.totalInconclusive
                )

                OutcomeCountsLine(
                    passed: entry.totalPassed,
                    failed: entry.totalFailed,
                    pending: entry.totalPending,
                    skipped: entry.totalSkipped,
                    inconclusive: entry.totalInconclusive
                )

                if !entry.faultsByRuns.isEmpty {
                    FaultChipsLine(faults: entry.faultsByRuns)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Category \(entry.category.title): \(entry.totalPassed) passed, \(entry.totalFailed) failed. Show experiments in History.")
    }
}

/// Proportional outcome strip. Green / red / orange-gray, gray when no data.
struct OutcomeBar: View {
    let passed: Int
    let failed: Int
    let other: Int

    private var total: Int { max(1, passed + failed + other) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 2) {
                if passed + failed + other == 0 {
                    Capsule().fill(Color.secondary.opacity(0.25))
                } else {
                    if passed > 0 {
                        Capsule().fill(Color.green)
                            .frame(width: max(4, w * CGFloat(passed) / CGFloat(total)))
                    }
                    if failed > 0 {
                        Capsule().fill(Color.red)
                            .frame(width: max(4, w * CGFloat(failed) / CGFloat(total)))
                    }
                    if other > 0 {
                        Capsule().fill(Color.orange.opacity(0.7))
                            .frame(width: max(4, w * CGFloat(other) / CGFloat(total)))
                    }
                }
            }
        }
        .frame(height: 6)
    }
}

struct OutcomeCountsLine: View {
    let passed: Int
    let failed: Int
    let pending: Int
    let skipped: Int
    let inconclusive: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(passed) passed").foregroundStyle(passed > 0 ? Color.green : Color.secondary)
            Text("\(failed) failed").foregroundStyle(failed > 0 ? Color.red : Color.secondary)
            if pending > 0 { Text("\(pending) pending").foregroundStyle(.orange) }
            if skipped > 0 { Text("\(skipped) skipped").foregroundStyle(.secondary) }
            if inconclusive > 0 { Text("\(inconclusive) inconclusive").foregroundStyle(.orange) }
            Spacer()
        }
        .font(.caption.monospacedDigit())
    }
}

/// The actual faults exercised in this category, most-run first.
struct FaultChipsLine: View {
    let faults: [(FaultID, Int)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(faults, id: \.0.rawValue) { fault, runs in
                    HStack(spacing: 4) {
                        Text(FaultCatalog.descriptor(for: fault)?.name ?? fault.rawValue)
                            .font(.caption2)
                        Text("×\(runs)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            }
        }
    }
}

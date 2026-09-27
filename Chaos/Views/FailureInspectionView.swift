import SwiftUI
import ChaosKit

// MARK: - Failure Inspector (Section 11)
// Shows exactly the recorded evidence: expected vs observed, plus the event
// timeline around the failure. Chaos never invents causes here.

struct FailureInspectorView: View {
    let record: ExperimentRecord
    let assertion: Assertion
    @Environment(\.dismiss) private var dismiss

    private var outcome: Assertion.Outcome { record.assertionResults[assertion.id] ?? .pending }
    private var evidence: Assertion.Evidence? { record.evidenceByAssertion[assertion.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: outcome.symbolName)
                    .font(.title2)
                    .foregroundStyle(outcome == .failed ? .red : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(assertion.label).font(.title3.bold())
                    Text(outcome.title).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            // Expected / Observed — only what the engine actually recorded.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("EXPECTED", systemImage: "checkmark.circle")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Text(evidence?.expectedDescription ?? expectedFallback)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: 3) {
                        Label("OBSERVED", systemImage: outcome == .failed ? "xmark.circle" : "eye")
                            .font(.caption.bold())
                            .foregroundStyle(outcome == .failed ? .red : .secondary)
                        Text(evidence?.observed ?? "No observation was recorded for this assertion.")
                            .font(.callout)
                            .foregroundStyle(outcome == .failed ? .red : .primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let explanation = evidence?.explanation, !explanation.isEmpty {
                    Divider()
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
                if let at = evidence?.evaluatedAt {
                    Text("Evaluated \(RecentExperimentRow.dateFormatter.string(from: at))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

            // Timeline of events around the assertion window — recorded events only.
            VStack(alignment: .leading, spacing: 6) {
                Text("Timeline").font(.headline)
                if record.events.isEmpty {
                    Text("No events were recorded during this experiment.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    EventTimelineView(events: Array(record.events.suffix(40)))
                        .frame(height: 260)
                }
            }

            Text("Chaos reports only what it observed. It does not infer causes.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 620, height: 560)
    }

    /// Human phrasing of what the assertion checks, when no engine evidence exists.
    private var expectedFallback: String {
        switch assertion.kind {
        case .processAlive, .processNotCrashed:
            return "Process \(assertion.subject) remains alive for the whole experiment."
        case .processResponds:
            return "Process \(assertion.subject) remains responsive."
        case .endpointReachable:
            return "\(assertion.subject) accepts connections."
        case .fileExists:
            return "File exists at \(assertion.subject)."
        case .fileCreated:
            return "A file appears at \(assertion.subject)."
        case .fileRemoved:
            return "File at \(assertion.subject) is gone."
        case .fileSizeChanged:
            return "Size at \(assertion.subject) differs from baseline."
        case .processAppeared:
            return "Process \(assertion.subject) is running."
        case .processDisappeared:
            return "Process \(assertion.subject) is not running."
        case .logContains:
            return "Unified log contains \"\(assertion.subject)\"."
        case .memoryPressureExceeded:
            return "Memory pressure crossed \(assertion.subject)%."
        }
    }
}

// MARK: - Clickable assertion row with evidence (used in record detail)

struct FailureEvidenceCard: View {
    let record: ExperimentRecord
    @State private var inspectedAssertion: Assertion?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assertions").font(.headline)
            ForEach(record.config.assertions) { assertion in
                let outcome = record.assertionResults[assertion.id] ?? .pending
                Button {
                    inspectedAssertion = assertion
                } label: {
                    HStack {
                        Image(systemName: outcome.symbolName)
                            .foregroundStyle(AssertionOutcomeColor.color(outcome))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assertion.label)
                                .foregroundStyle(.primary)
                            if let evidence = record.evidenceByAssertion[assertion.id] {
                                Text(evidence.explanation)
                                    .font(.caption)
                                    .foregroundStyle(outcome == .failed ? .red : .secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(outcome.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if outcome == .failed {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(assertion.label): \(outcome.title). Open evidence.")
            }
        }
        .sheet(item: $inspectedAssertion) { assertion in
            FailureInspectorView(record: record, assertion: assertion)
        }
    }
}

enum AssertionOutcomeColor {
    static func color(_ outcome: Assertion.Outcome) -> Color {
        switch outcome {
        case .passed: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

// MARK: - Replay Comparison (Section 15/29, evidence-only)

struct ReplayCompareView: View {
    let original: ExperimentRecord
    let replay: ExperimentRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {                Text("REPLAY COMPARISON").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("").font(.caption)
                    Text("ORIGINAL").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("REPLAY").font(.caption.bold()).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Result").font(.callout)
                    HStack(spacing: 4) {
                        Image(systemName: original.outcome.symbolName)
                        Text(original.outcome.title)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: replay.outcome.symbolName)
                        Text(replay.outcome.title)
                    }
                }
                GridRow {
                    Text("Duration").font(.callout)
                    Text(original.duration.map { $0.asClockString } ?? "—")
                    Text(replay.duration.map { $0.asClockString } ?? "—")
                }
                GridRow {
                    Text("Assertions").font(.callout)
                    Text(assertionSummary(original))
                    Text(assertionSummary(replay))
                }
                GridRow {
                    Text("Restoration").font(.callout)
                    Text(restorationSummary(original))
                    Text(restorationSummary(replay))
                }
            }
            .font(.callout.monospacedDigit())

            let changed = changedAssertions
            if !changed.isEmpty {
                Divider()
                Text("Changed assertions").font(.subheadline.bold())
                ForEach(changed, id: \.0.id) { assertion, before, after in
                    HStack(spacing: 8) {
                        Image(systemName: assertion.kind == .processAlive ? "heart" : "checklist")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(assertion.label).font(.callout)
                        Spacer()
                        Label(before.title, systemImage: before.symbolName)
                            .foregroundStyle(AssertionOutcomeColor.color(before))
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Label(after.title, systemImage: after.symbolName)
                            .foregroundStyle(AssertionOutcomeColor.color(after))
                    }
                }
            }

            Text("Replay uses the same plan and seed. System scheduling and external system behavior may differ between runs — Chaos does not claim deterministic system behavior.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func assertionSummary(_ record: ExperimentRecord) -> String {
        let s = record.assertionSummary
        return "\(s.passed)/\(record.config.assertions.count) passed"
    }

    private func restorationSummary(_ record: ExperimentRecord) -> String {
        if record.restorationStatus.isEmpty { return "n/a" }
        return record.restorationStatus.values.allSatisfy { $0 } ? "✓ verified" : "✗ problems"
    }

    /// Assertions whose outcome differs between the two runs.
    private var changedAssertions: [(Assertion, Assertion.Outcome, Assertion.Outcome)] {
        var out: [(Assertion, Assertion.Outcome, Assertion.Outcome)] = []
        for assertion in original.config.assertions {
            let before = original.assertionResults[assertion.id] ?? .pending
            let after = replay.assertionResults[assertion.id] ?? .pending
            if before != after { out.append((assertion, before, after)) }
        }
        return out
    }
}

// MARK: - Compare two experiments (Section 29)

struct ComparePickerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectionA: ExperimentRecord?
    @State private var selectionB: ExperimentRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare Experiments").font(.title3.bold())
            Text("Pick two runs of the same plan. Chaos shows only recorded differences — never a verdict about why they differ.")
                .font(.callout).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                pickColumn(title: "Original", selection: $selectionA, other: selectionB)
                pickColumn(title: "Comparison", selection: $selectionB, other: selectionA)
            }

            if let a = selectionA, let b = selectionB {
                ReplayCompareView(original: a, replay: b)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 720, height: 560)
    }

    private func pickColumn(title: String, selection: Binding<ExperimentRecord?>,
                            other: ExperimentRecord?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            List(app.history.prefix(40), selection: selection) { record in
                ExperimentRow(record: record, showTarget: false)
                    .tag(record)
                    .opacity(other?.id == record.id ? 0.4 : 1)
            }
            .frame(height: 240)
        }
        .frame(maxWidth: .infinity)
    }
}

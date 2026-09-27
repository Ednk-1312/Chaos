import SwiftUI
import ChaosKit

struct LiveExperimentView: View {
    @EnvironmentObject private var app: AppModel
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let record = app.liveRecord {
                VStack(spacing: 0) {
                    // Event filter bar
                    Picker("Filter", selection: $app.eventFilter) {
                        ForEach(EventFilter.allCases, id: \.self) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !record.config.assertions.isEmpty {
                                LiveAssertionsCard(record: record, evidence: app.liveRecord?.evidenceByAssertion ?? [:])
                            }
                            FaultStatusBar(record: record, now: now)
                            RestoreStatusBar(record: record)
                            EventTimelineView(events: app.filteredEvents.suffix(120).map { $0 })
                        }
                        .padding(20)
                    }
                }
            } else {
                emptyState
            }
        }
        .onReceive(timer) { now = $0 }
        .navigationTitle("Live Experiment")
    }

    private var header: some View {
        HStack {
            if let record = app.liveRecord, let started = record.startedAt {
                VStack(alignment: .leading) {
                    HStack(spacing: 10) {
                        Text("CHAOS ACTIVE")
                            .font(.title.bold())
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                        Text(Date.now.timeIntervalSince(started).asClockString)
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("\(record.config.name) — seed \(record.config.seed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.restoreEverything()
                } label: {
                    Label("RESTORE EVERYTHING", systemImage: "arrow.uturn.backward.circle.fill")
                }
                Button {
                    app.emergencyStop()
                } label: {
                    Label("STOP CHAOS", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Label("No experiment running", systemImage: "bolt.slash")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start from a Scenario") {
                    app.selectedSection = .scenarios
                }
            }
        }
        .padding(20)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Nothing is broken right now.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a scenario and press CREATE CHAOS.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FaultStatusBar: View {
    let record: ExperimentRecord
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Faults").font(.headline)
            if record.events.contains(where: { $0.kind == .faultActivated }) {
                let faults = Dictionary(grouping: record.events.filter { $0.kind == .faultActivated || $0.kind == .faultDeactivated || $0.kind == .faultFailed }, by: { $0.faultID ?? .customManual })
                ForEach(Array(faults.keys), id: \.self) { faultID in
                    let events = faults[faultID] ?? []
                    let last = events.max { $0.date < $1.date }
                    let isActive = last?.kind == .faultActivated
                    HStack {
                        Circle()
                            .fill(isActive ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                        Text(FaultCatalog.descriptor(for: faultID)?.name ?? faultID.rawValue)
                        Spacer()
                        Text(isActive ? "FAULT ACTIVE" : "restored")
                            .font(.caption)
                            .foregroundStyle(isActive ? .red : .secondary)
                    }
                }
            } else {
                Text("First fault scheduled — waiting…").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct RestoreStatusBar: View {
    let record: ExperimentRecord

    private struct RestoreRow: Identifiable {
        let id: String
        let ok: Bool
    }

    private var rows: [RestoreRow] {
        record.restorationStatus
            .sorted(by: { $0.key < $1.key })
            .map { RestoreRow(id: $0.key, ok: $0.value) }
    }

    var body: some View {
        if !record.restorationStatus.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Restoration").font(.headline)
                ForEach(rows, id: \.id) { (row: RestoreRow) in
                    HStack {
                        Image(systemName: row.ok ? "checkmark.circle.fill" : "exclamationmark.octagon.fill")
                            .foregroundStyle(row.ok ? .green : .red)
                        Text(row.id)
                        Spacer()
                        Text(row.ok ? "Restored" : "Needs attention")
                            .font(.caption)
                            .foregroundStyle(row.ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
}

/// Live assertion status with explained evidence.
struct LiveAssertionsCard: View {
    let record: ExperimentRecord
    let evidence: [UUID: Assertion.Evidence]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assertions").font(.headline)
            ForEach(record.config.assertions) { assertion in
                let outcome = record.assertionResults[assertion.id] ?? .pending
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: outcome.symbolName)
                            .foregroundStyle(outcome == .passed ? .green : outcome == .failed ? .red : .secondary)
                        Text(assertion.label)
                        Spacer()
                        Text(outcome.title).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let ev = evidence[assertion.id], outcome == .failed {
                        Text(ev.explanation)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct EventTimelineView: View {
    let events: [ExperimentEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unified Timeline").font(.headline)
            ForEach(Array(events.suffix(120).enumerated().reversed()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: event.kind.symbolName)
                        .foregroundStyle(color(for: event))
                        .frame(width: 18)
                    Text(event.date.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(event.message)
                        .font(.callout)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(event.kind.rawValue): \(event.message)")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func color(for event: ExperimentEvent) -> Color {
        switch event.kind {
        case .faultActivated, .emergencyStop: return .red
        case .restorationCompleted: return .green
        case .restorationFailed, .faultFailed, .error: return .orange
        case .faultScheduled: return .secondary
        default: return .accentColor
        }
    }
}

import SwiftUI
import ChaosKit
import UniformTypeIdentifiers

struct ReportsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reports").font(.largeTitle.bold())
                Text("Every experiment produces a shareable report: timeline, metrics, assertions, and restoration status.")
                    .foregroundStyle(.secondary)

                if app.history.isEmpty {
                    EmptyStateView(
                        symbol: "doc.richtext",
                        title: "NO REPORTS YET",
                        message: "Every experiment produces a professional report: faults, assertions, evidence, recovery, restoration, and a summary built only from recorded data.",
                        buttonTitle: "Create Experiment"
                    ) { app.showExperimentBuilder = true }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 12) {
                        ForEach(app.history.prefix(12)) { record in
                            ReportCard(record: record)
                        }
                    }
                }

                Text("Summaries in Chaos reports state only what was recorded. They never invent causes — a report says “the application became unresponsive for 8.2 seconds”, not “the network failure caused the crash”, unless the evidence establishes it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .navigationTitle("Reports")
    }
}

struct ReportCard: View {
    let record: ExperimentRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(record.outcome.title, systemImage: record.outcome.symbolName)
                .foregroundStyle(record.outcome == .passed ? .green : record.outcome == .failed ? .red : .orange)
            Text(record.config.name).font(.headline)
            Text(record.startedAt.map { RecentExperimentRow.dateFormatter.string(from: $0) } ?? "")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct ExportView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.largeTitle.bold())
            Text("Export any experiment as Markdown, JSON, CSV, or PDF. Reports never leave your Mac unless you send them.")
                .foregroundStyle(.secondary)
            if app.history.isEmpty {
                EmptyStateView(
                    symbol: "square.and.arrow.up",
                    title: "NOTHING TO EXPORT",
                    message: "Run an experiment and its full report — Markdown, JSON, CSV, or PDF — becomes exportable.",
                    buttonTitle: "Create Experiment"
                ) { app.showExperimentBuilder = true }
            } else {
                List(app.history) { record in
                    HStack {
                        Text(record.config.name)
                        Spacer()
                        Text(record.outcome.title).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(24)
        .navigationTitle("Export")
    }
}

struct LogsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Logs").font(.largeTitle.bold())
            if let record = app.liveRecord ?? app.history.first {
                EventTimelineView(events: record.events.suffix(200).map { $0 })
            } else {
                Text("No events recorded yet.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("Logs")
    }
}

import SwiftUI
import ChaosKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var outcomeFilter: FilterKind = .all
    @State private var showCompare = false
    @State private var selection: ExperimentRecord?

    enum FilterKind: String, CaseIterable {
        case all, passed, failed, warning, inconclusive, restorationRequired

        var title: String {
            switch self {
            case .all: return "All"
            case .restorationRequired: return "Restoration Required"
            default: return ExperimentOutcome(rawValue: rawValue)?.title ?? rawValue
            }
        }
    }

    private var filtered: [ExperimentRecord] {
        app.history.filter { record in
            // Scope filter (scorecard click-through): only the scoped records.
            if let scope = app.historyScope, !scope.recordIDs.contains(record.id) { return false }
            let outcomeMatch: Bool
            switch outcomeFilter {
            case .all: outcomeMatch = true
            case .restorationRequired:
                outcomeMatch = !record.restorationStatus.isEmpty && record.restorationStatus.values.contains(false)
            default:
                outcomeMatch = record.outcome == ExperimentOutcome(rawValue: outcomeFilter.rawValue)
            }
            let searchMatch = searchText.isEmpty
                || record.config.name.localizedCaseInsensitiveContains(searchText)
                || String(record.config.seed).contains(searchText)
                || record.config.targets.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
                || record.config.bindings.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
                || record.config.assertions.contains { $0.label.localizedCaseInsensitiveContains(searchText) }
            return outcomeMatch && searchMatch
        }
    }

    var body: some View {
        // HSplitView (NOT a nested NavigationSplitView — nesting splits inside
        // RootView's split view corrupts the outer sidebar's layout).
        HSplitView {
            Group {
            List(selection: $selection) {
                ForEach(filtered) { record in
                    ExperimentRow(record: record)
                        .tag(record)
                }
                if filtered.isEmpty && !app.history.isEmpty {
                    Text("No experiments match the current filter.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .searchable(text: $searchText, prompt: "Search app, scenario, recipe, fault, assertion")
            .toolbar {
                Button {
                    showCompare = true
                } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
                .disabled(app.history.count < 2)
                .accessibilityLabel("Compare two experiments")
            }
            }
            .frame(minWidth: 320, maxWidth: 460, maxHeight: .infinity)

            Group {
                if let record = selection {
                    RecordDetailView(record: record)
                } else {
                    EmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: "NO EXPERIMENT SELECTED",
                        message: "Every run is archived here with its assertions, evidence, and restoration status — your testing history.",
                        buttonTitle: app.history.isEmpty ? "Create Experiment" : nil,
                        action: app.history.isEmpty ? { app.showExperimentBuilder = true } : nil
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Filter bar spans the FULL page width — inside the narrow list column
        // the six-segment picker gets clipped ("Restoration Req…").
        .safeAreaInset(edge: .bottom) { filterBar }
        .navigationTitle("History")
        .sheet(isPresented: $showCompare) {
            ComparePickerView()
        }
        .onAppear(perform: adoptPendingSelection)
        .onChange(of: app.pendingHistorySelection) { _ in adoptPendingSelection() }
    }

    /// Bottom filter bar: scope banner + outcome segments. Full-width so no
    /// segment is ever cut off.
    private var filterBar: some View {
        VStack(spacing: 0) {
            if let scope = app.historyScope {
                HStack(spacing: 8) {
                    Image(systemName: scope.symbolName)
                        .foregroundStyle(.secondary)
                    Text("Scoped: \(scope.title)").font(.callout)
                    Spacer()
                    Button {
                        app.historyScope = nil
                    } label: {
                        Label("Show All", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear scope and show all experiments")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }
            Picker("Outcome", selection: $outcomeFilter) {
                ForEach(FilterKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
        }
    }

    /// When arriving from the Resilience Scorecard, preselect the first of the
    /// scoped experiments. Consumes the pending selection.
    private func adoptPendingSelection() {
        // Intentionally does NOT consume the pending selection: multiple view
        // instances (e.g. offscreen QA rendering) may need to adopt it.
        // AppModel clears it when navigation leaves History.
        guard let pending = app.pendingHistorySelection,
              let match = app.history.first(where: { $0.id == pending }) else { return }
        selection = match
        outcomeFilter = .all
        searchText = ""
    }
}

struct RecordDetailView: View {
    @EnvironmentObject private var app: AppModel
    let record: ExperimentRecord
    @State private var showRecipeSheet = false
    @State private var recipePurpose = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(record.config.name).font(.largeTitle.bold())
                        Text("Seed \(record.config.seed) · \(record.duration?.asClockString ?? "—")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Label(record.outcome.title, systemImage: record.outcome.symbolName)
                            .font(.headline)
                            .foregroundStyle(color(for: record.outcome))
                        if let state = record.state {
                            Text(state.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // Replay + recipe actions
                HStack {
                    Button {
                        app.replay(record)
                    } label: {
                        Label("Replay Exactly", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(app.isRunning)
                    .accessibilityLabel("Replay exactly: same experiment plan, same seed, same timing configuration")
                    Button {
                        showRecipeSheet = true
                    } label: {
                        Label("Save as Bug Recipe", systemImage: "checklist")
                    }
                    Spacer()
                }

                Text(ReplayPlan.replayNotice)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Replay comparison when this record was launched as a replay.
                if let sourceID = app.lastReplaySourceID,
                   let source = app.history.first(where: { $0.id == sourceID }),
                   source.id != record.id {
                    ReplayCompareView(original: source, replay: record)
                }

                if !record.config.assertions.isEmpty {
                    FailureEvidenceCard(record: record)
                }

                EventTimelineView(events: record.events)
                RestoreStatusBar(record: record)
            }
            .padding(24)
        }
        .sheet(isPresented: $showRecipeSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Save as Bug Recipe").font(.title3.bold())
                Text("A recipe reproduces this failure: same target, fault sequence, and assertions.")
                    .foregroundStyle(.secondary)
                TextField("What failure does this reproduce?", text: $recipePurpose, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Spacer()
                    Button("Cancel") { showRecipeSheet = false }
                    Button("Save Recipe") {
                        app.saveRecipe(from: record, purpose: recipePurpose)
                        recipePurpose = ""
                        showRecipeSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(22)
            .frame(width: 420)
        }
        .toolbar {
            Menu {
                Button("Markdown") { export(.markdown) }
                Button("JSON") { export(.json) }
                Button("CSV") { export(.csv) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func color(for outcome: ExperimentOutcome) -> Color {
        ExperimentRow.color(for: outcome)
    }

    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "\(record.config.name).\(format.extension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data?
        switch format {
        case .markdown: data = ReportGenerator.markdown(for: record).data(using: .utf8)
        case .json: data = try? ReportGenerator.jsonData(for: record)
        case .csv: data = ReportGenerator.csv(for: record).data(using: .utf8)
        case .pdf: data = ReportGenerator.pdfData(for: record)
        }
        try? data?.write(to: url)
    }
}

enum ExportFormat {
    case markdown, json, csv, pdf

    var utType: UTType {
        switch self {
        case .markdown: return .utf8PlainText
        case .json: return .json
        case .csv: return .commaSeparatedText
        case .pdf: return .pdf
        }
    }

    var `extension`: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .csv: return "csv"
        case .pdf: return "pdf"
        }
    }
}

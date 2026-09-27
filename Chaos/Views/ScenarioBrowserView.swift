import SwiftUI
import ChaosKit

struct ScenarioBrowserView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selected: Scenario?
    @State private var searchText = ""

    private var allScenarios: [Scenario] {
        ScenarioLibrary.all + app.userScenarios
    }

    private var filtered: [Scenario] {
        searchText.isEmpty ? allScenarios : allScenarios.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        // HSplitView (NOT a nested NavigationSplitView — nesting splits inside
        // RootView's split view corrupts the outer sidebar's layout).
        HSplitView {
            Group {
            List(selection: $selected) {
                ForEach(ScenarioLibrary.byCategory(), id: \.0) { category, scenarios in
                    Section(category) {
                        ForEach(scenarios) { scenario in
                            HStack {
                                Image(systemName: scenario.symbolName)
                                    .foregroundStyle(scenario.isExtreme ? .red : .accentColor)
                                VStack(alignment: .leading) {
                                    Text(scenario.name)
                                    Text(scenario.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tag(scenario)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            }
            .frame(minWidth: 280, maxWidth: 420, maxHeight: .infinity)

            Group {
                if let scenario = selected {
                    ScenarioDetailView(scenario: scenario)
                } else {
                    EmptyStateView(
                        symbol: "list.bullet.rectangle",
                        title: "SELECT A SCENARIO",
                        message: "Each scenario is a pre-built fault sequence — review exactly what will happen, then press CREATE CHAOS.",
                        buttonTitle: "Build a Custom Experiment"
                    ) { app.showExperimentBuilder = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Scenarios")
    }
}

struct ScenarioDetailView: View {
    @EnvironmentObject private var app: AppModel
    let scenario: Scenario

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(scenario.name).font(.largeTitle.bold())
                        Text(scenario.summary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        app.startExperiment(scenario: scenario, targets: app.primaryTarget.map { [$0] } ?? [])
                    } label: {
                        Text("CREATE CHAOS").font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if scenario.isExtreme {
                    Label("Extreme severity — Chaos will ask for explicit confirmation before running.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Fault Timeline").font(.headline)
                    ForEach(scenario.bindings) { binding in
                        HStack {
                            Text("\(Int(binding.startOffset))s")
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Rectangle().fill(.red.opacity(0.7))
                                .frame(width: max(8, CGFloat(binding.duration) / 4), height: 6)
                                .cornerRadius(3)
                            Text(binding.name).font(.callout)
                            Spacer()
                            Text("\(Int(binding.duration))s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(binding.name) at \(Int(binding.startOffset)) seconds for \(Int(binding.duration)) seconds")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What Each Fault Does").font(.headline)
                    ForEach(scenario.bindings) { binding in
                        if let d = FaultCatalog.descriptor(for: binding.faultID) {
                            DisclosureGroup {
                                Text(d.capabilityNote).font(.callout)
                                Text("Restoration: \(d.restoration)").font(.caption).foregroundStyle(.secondary)
                            } label: {
                                Label(binding.name, systemImage: d.category.symbolName)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

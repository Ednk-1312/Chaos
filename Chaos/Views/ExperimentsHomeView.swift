import SwiftUI
import ChaosKit

/// The Experiments home: launch and re-run experiments. Distinct from
/// Scenarios (browsing pre-built fault plans) and History (the full archive):
/// this page is the working bench for the primary target.
struct ExperimentsHomeView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Experiments").font(.largeTitle.bold())
                    Text("Run chaos against your primary target, build a custom plan, or re-run a recent experiment.")
                        .foregroundStyle(.secondary)
                }

                // Primary target bench
                HStack(spacing: 14) {
                    if let target = app.primaryTarget {
                        AppIconView(iconData: target.iconData, bundleID: target.bundleID, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name).font(.title3.bold())
                            Text("Primary target").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Change Target") {
                            app.selectedSection = .targets
                        }
                        Button("RUN EXPERIMENT") {
                            app.runPrimaryExperiment()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(app.isRunning || app.primaryScenario == nil)
                    } else {
                        Image(systemName: "target")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No primary target set").font(.title3.bold())
                            Text("Pick an application to break first.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Target") {
                            app.selectedSection = .targets
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

                // Actions
                HStack(spacing: 12) {
                    Button {
                        app.showExperimentBuilder = true
                    } label: {
                        Label("New Custom Experiment", systemImage: "wand.and.stars")
                    }
                    .disabled(app.isRunning)
                    Button {
                        app.selectedSection = .scenarios
                    } label: {
                        Label("Browse Scenarios", systemImage: "list.bullet.rectangle")
                    }
                    Spacer()
                }

                // Recent targets
                if !app.recentTargets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Targets").font(.headline)
                        HStack(spacing: 8) {
                            ForEach(app.recentTargets.prefix(5)) { target in
                                Button {
                                    app.setPrimaryTarget(target)
                                } label: {
                                    Label(target.name, systemImage: "arrow.uturn.backward.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                // Last run (quick re-run) — full archive lives in History.
                if let last = app.history.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Run").font(.headline)
                        HStack {
                            Image(systemName: last.outcome.symbolName)
                                .foregroundStyle(ExperimentRow.color(for: last.outcome))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(last.config.name).font(.callout.bold())
                                Text(last.startedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("View in History") {
                                app.pendingHistorySelection = last.id
                                app.selectedSection = .history
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
                }
            }
            .padding(24)
        }
        .navigationTitle("Experiments")
    }
}

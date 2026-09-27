import SwiftUI
import ChaosKit

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detailView
        }
        .sheet(item: $app.showSafetyConfirmation) { request in
            SafetyConfirmationView(request: request)
        }
        .sheet(isPresented: $app.showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $app.showExperimentBuilder) {
            ExperimentBuilderView()
        }
        .overlay(alignment: .top) {
            if app.isRunning { ChaosActiveBanner() }
        }
        .overlay {
            if app.showCommandPalette {
                CommandPaletteView()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch app.selectedSection {
        case .dashboard: DashboardView()
        case .experiments: ExperimentsHomeView()
        case .scenarios: ScenarioBrowserView()
        case .faultLibrary: FaultLibraryView()
        case .targets: TargetsView()
        case .history: HistoryView()
        case .reports: ReportsView()
        case .restoreCenter: RestoreCenterView()
        case .scorecard: ResilienceScorecardView()
        case .apps: AppProfilesView()
        case .suites: SuitesView()
        case .recipes: RecipesView()
        case .randomChaos: RandomChaosView()
        case .conditionalChaos: ConditionalChaosView()
        case .liveMonitor: LiveExperimentView()
        case .system: SystemMonitorView()
        case .network: NetworkMonitorView()
        case .processes: ProcessMonitorView()
        case .storage: StorageMonitorView()
        case .memory: MemoryMonitorView()
        case .cli: CLIGuideView()
        case .automation: AutomationView()
        case .integrations: IntegrationsView()
        case .export: ExportView()
        case .logs: LogsView()
        case .general: GeneralSettingsView()
        case .safety: SafetySettingsView()
        case .privileges: PrivilegesView()
        case .appearance: AppearanceSettingsView()
        case .notifications: NotificationSettingsView()
        case .advanced: AdvancedSettingsView()
        case .yourData: YourDataView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        List(selection: $app.selectedSection) {
            Section("CHAOS") {
                ForEach([SidebarSection.dashboard, .experiments, .scenarios, .faultLibrary, .targets, .history, .reports, .scorecard, .restoreCenter], id: \.self) { section in
                    row(section)
                }
            }
            Section("WORKFLOWS") {
                ForEach([SidebarSection.apps, .suites, .recipes, .randomChaos, .conditionalChaos], id: \.self) { section in
                    row(section)
                }
            }
            Section("MONITORING") {
                ForEach([SidebarSection.liveMonitor, .system, .network, .processes, .storage, .memory], id: \.self) { section in
                    row(section)
                }
            }
            Section("DEVELOPER") {
                ForEach([SidebarSection.cli, .automation, .integrations, .export, .logs], id: \.self) { section in
                    row(section)
                }
            }
            Section("SETTINGS") {
                ForEach([SidebarSection.general, .safety, .privileges, .appearance, .notifications, .advanced, .yourData], id: \.self) { section in
                    row(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ section: SidebarSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbolName)
                .foregroundStyle(section == .liveMonitor && app.isRunning ? .red : .secondary)
        }
        .badge(section == .liveMonitor && app.isRunning ? "LIVE" : "")
    }
}

struct ChaosActiveBanner: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text("CHAOS ACTIVE")
                .font(.headline)
                .foregroundStyle(.red)
            if let record = app.liveRecord, let started = record.startedAt {
                Text(Date.now.timeIntervalSince(started).asClockString)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                app.emergencyStop()
            } label: {
                Label("STOP", systemImage: "stop.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut(".", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityLabel("Chaos active banner with emergency stop")
    }
}

struct SafetyConfirmationView: View {
    let request: SafetyConfirmationRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(request.title, systemImage: "exclamationmark.triangle.fill")
                .font(.title3.bold())
                .foregroundStyle(.orange)
            Text(request.detail)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("I Understand — Proceed") {
                    request.confirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

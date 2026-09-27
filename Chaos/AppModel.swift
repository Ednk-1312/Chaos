import SwiftUI
import Combine
import ChaosKit

/// Optional scope filter for HistoryView, e.g. when arriving from the
/// Resilience Scorecard. Record IDs were computed at click time from real
/// history; unknown IDs (deleted records) simply don't match.
struct HistoryScope: Equatable {
    var title: String
    var symbolName: String
    var recordIDs: Set<UUID>
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard, experiments, scenarios, faultLibrary, targets, history, reports
    case restoreCenter
    case apps, suites, recipes, randomChaos, conditionalChaos
    case scorecard
    case liveMonitor, system, network, processes, storage, memory
    case cli, automation, integrations, export, logs
    case general, safety, privileges, appearance, notifications, advanced, yourData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .experiments: return "Experiments"
        case .scenarios: return "Scenarios"
        case .faultLibrary: return "Fault Library"
        case .targets: return "Targets"
        case .history: return "History"
        case .reports: return "Reports"
        case .restoreCenter: return "Restore Center"
        case .scorecard: return "Scorecard"
        case .apps: return "Applications"
        case .conditionalChaos: return "Conditional"
        case .suites: return "Chaos Suites"
        case .recipes: return "Bug Recipes"
        case .randomChaos: return "Random Chaos"
        case .liveMonitor: return "Live Monitor"
        case .system: return "System"
        case .network: return "Network"
        case .processes: return "Processes"
        case .storage: return "Storage"
        case .memory: return "Memory"
        case .cli: return "CLI"
        case .automation: return "Automation"
        case .integrations: return "Integrations"
        case .export: return "Export"
        case .logs: return "Logs"
        case .general: return "General"
        case .safety: return "Safety"
        case .privileges: return "Privileges"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .advanced: return "Advanced"
        case .yourData: return "Your Data"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .experiments: return "bolt.badge.clock"
        case .scenarios: return "list.bullet.rectangle"
        case .faultLibrary: return "books.vertical"
        case .targets: return "app.dashed"
        case .history: return "clock.arrow.circlepath"
        case .reports: return "doc.richtext"
        case .restoreCenter: return "arrow.uturn.backward.circle"
        case .scorecard: return "gauge.with.needle"
        case .apps: return "app.badge.checkmark"
        case .conditionalChaos: return "arrow.triangle.branch"
        case .suites: return "list.star"
        case .recipes: return "checklist"
        case .randomChaos: return "dice"
        case .liveMonitor: return "waveform.path.ecg"
        case .system: return "desktopcomputer"
        case .network: return "wifi"
        case .processes: return "app.connected.to.app.below.fill"
        case .storage: return "internaldrive"
        case .memory: return "memorychip"
        case .cli: return "terminal"
        case .automation: return "gearshape.2"
        case .integrations: return "puzzlepiece.extension"
        case .export: return "square.and.arrow.up"
        case .logs: return "doc.text.magnifyingglass"
        case .general: return "gearshape"
        case .safety: return "shield.lefthalf.filled"
        case .privileges: return "key"
        case .appearance: return "paintbrush"
        case .notifications: return "bell"
        case .advanced: return "slider.horizontal.3"
        case .yourData: return "lock.shield"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: Navigation
    @Published var selectedSection: SidebarSection = .dashboard
    @Published var showCommandPalette = false
    @Published var showOnboarding = false
    @Published var showExperimentBuilder = false
    @Published var showSafetyConfirmation: SafetyConfirmationRequest?

    // MARK: Experiment state
    @Published var isRunning = false
    @Published var liveRecord: ExperimentRecord?
    @Published var history: [ExperimentRecord] = []
    @Published var userScenarios: [Scenario] = []
    @Published var systemStats: SystemStats?
    @Published var lastRestoreStatus: [String: Bool]?

    // Platform: recipes, suites, replay
    @Published var recipes: [Recipe] = []
    @Published var suites: [ChaosSuite] = []
    @Published var activeSuiteRun: SuiteRun?
    @Published var eventFilter: EventFilter = .all

    // Application profiles
    @Published var profiles: [AppProfile] = []
    @Published var selectedProfile: AppProfile?

    /// Optional filter applied to History's list (e.g. clicking a Resilience
    /// Scorecard category shows only that category's experiments).nil = show all.
    @Published var historyScope: HistoryScope?
    /// Record to preselect when History appears (scorecard click-through).
    @Published var pendingHistorySelection: UUID?

    // MARK: Primary target (the "one click" flow)
    @Published var primaryTarget: TargetDescriptor?
    @Published var primaryScenario: Scenario?
    @Published var recentTargets: [TargetDescriptor] = []

    /// Set the primary target and remember it in recents (persisted).
    func setPrimaryTarget(_ target: TargetDescriptor?) {
        primaryTarget = target
        guard let target else { return }
        recentTargets.removeAll { $0.id == target.id }
        recentTargets.insert(target, at: 0)
        recentTargets = Array(recentTargets.prefix(5))
        if let data = try? JSONEncoder().encode(recentTargets) {
            UserDefaults.standard.set(data, forKey: "chaos.recentTargets")
        }
    }

    private func loadRecentTargets() {
        guard let data = UserDefaults.standard.data(forKey: "chaos.recentTargets"),
              let decoded = try? JSONDecoder().decode([TargetDescriptor].self, from: data) else { return }
        recentTargets = decoded
    }

    private var statsTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func bootstrap() {
        // Engine wiring — engine callbacks hop to main.
        ExperimentEngine.shared.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveRecord = self.liveRecord // touch to trigger publishers
                self.liveRecord = ExperimentEngine.shared.liveSnapshot
                if event.kind == .restorationCompleted || event.kind == .restorationFailed {
                    self.lastRestoreStatus = ExperimentEngine.shared.liveSnapshot?.restorationStatus
                }
            }
        }
        ExperimentEngine.shared.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .running:
                    self.isRunning = true
                case .restoring:
                    self.isRunning = true
                case .idle:
                    self.isRunning = false
                    self.history = PersistenceStore.shared.loadRecords()
                }
            }
        }
        ExperimentEngine.shared.onRecordUpdate = { [weak self] record in
            Task { @MainActor [weak self] in
                self?.liveRecord = record
            }
        }

        history = PersistenceStore.shared.loadRecords()
        userScenarios = PersistenceStore.shared.loadUserScenarios()
        recipes = PersistenceStore.shared.loadRecipes()
        suites = PersistenceStore.shared.loadSuites()
        profiles = PersistenceStore.shared.loadProfiles()
        loadRecentTargets()

        // Hidden launch args for QA/screenshots: -chaos.section <rawValue> [-chaos.openBuilder]
        if let name = UserDefaults.standard.string(forKey: "chaos.section"),
           let section = SidebarSection(rawValue: name) {
            selectedSection = section
        }
        if UserDefaults.standard.bool(forKey: "chaos.openBuilder") {
            showExperimentBuilder = true
        }
        if let profileName = UserDefaults.standard.string(forKey: "chaos.selectProfile"),
           let match = profiles.first(where: { $0.name == profileName }) {
            selectedProfile = match
        }
        // QA: mimic the scorecard category click-through (same code path as
        // CategoryScorecardRow's action) so the receiving end can be verified
        // without synthetic clicks: -chaos.scopeHistory <category title>
        if let categoryTitle = UserDefaults.standard.string(forKey: "chaos.scopeHistory"),
           let entry = ResilienceScorecard(records: history).entries.first(where: { $0.category.title == categoryTitle }) {
            historyScope = HistoryScope(
                title: entry.category.title,
                symbolName: entry.category.symbolName,
                recordIDs: Set(entry.records.map(\.id))
            )
            pendingHistorySelection = entry.records.first?.id
        }

        SuiteRunner.shared.onRunUpdate = { [weak self] run in
            Task { @MainActor [weak self] in
                self?.activeSuiteRun = run
                if run.endedAt != nil {
                    self?.history = PersistenceStore.shared.loadRecords()
                }
            }
        }

        startStatsTimer()

        if !UserDefaults.standard.bool(forKey: "chaos.onboardingComplete") {
            showOnboarding = true
        }
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            let stats = SystemMonitor.shared.sample()
            Task { @MainActor [weak self] in self?.systemStats = stats }
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    // MARK: Actions

    func runPrimaryExperiment() {
        guard let scenario = primaryScenario ?? ScenarioLibrary.all.first(where: { $0.id == "terrible-wifi" }) else { return }
        startExperiment(scenario: scenario, targets: primaryTarget.map { [$0] } ?? [])
    }

    func startExperiment(scenario: Scenario, targets: [TargetDescriptor], assertions: [Assertion] = []) {
        var config = ExperimentConfig(
            name: scenario.name,
            plannedDuration: scenario.bindings.map { $0.startOffset + $0.duration }.max() ?? 60,
            bindings: scenario.bindings,
            targets: targets,
            assertions: assertions
        )
        if scenario.isExtreme {
            showSafetyConfirmation = SafetyConfirmationRequest(
                title: "Extreme experiment: \(scenario.name)",
                detail: "This composition includes Extreme severity faults with simultaneous system-wide pressure. Safety ceilings still apply. Confirm to proceed.",
                confirm: { [weak self] in
                    config.safetyConfirmed = true
                    self?.launch(config)
                }
            )
        } else {
            config.safetyConfirmed = true
            launch(config)
        }
    }

    func launch(_ config: ExperimentConfig) {
        do {
            _ = try ExperimentEngine.shared.start(config: config)
            selectedSection = .liveMonitor
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func stopChaos() {
        ExperimentEngine.shared.stop(reason: .userStop)
    }

    func emergencyStop() {
        ExperimentEngine.shared.stop(reason: .emergencyStop)
    }

    func restoreEverything() {
        lastRestoreStatus = FaultCleanup.restoreEverything()
    }

    func toggleCommandPalette() {
        showCommandPalette.toggle()
    }

    func selectSection(_ section: SidebarSection) {
        // Leaving History invalidates a scorecard click-through scope and any
        // pending preselection.
        if section != .history {
            historyScope = nil
            pendingHistorySelection = nil
        }
        selectedSection = section
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "chaos.onboardingComplete")
        showOnboarding = false
    }

    func saveScenario(_ scenario: Scenario) {
        PersistenceStore.shared.save(scenario: scenario)
        userScenarios = PersistenceStore.shared.loadUserScenarios()
    }

    // MARK: Application profiles

    func saveProfile(_ profile: AppProfile) {
        PersistenceStore.shared.save(profile: profile)
        profiles = PersistenceStore.shared.loadProfiles()
    }

    func deleteProfile(_ profile: AppProfile) {
        PersistenceStore.shared.deleteProfile(id: profile.id)
        profiles = PersistenceStore.shared.loadProfiles()
        if selectedProfile?.id == profile.id { selectedProfile = nil }
    }

    /// Targets for a profile run: prefer a live pid when the app is running,
    /// otherwise fall back to a named/bundle descriptor.
    func targetsForProfile(_ profile: AppProfile) -> [TargetDescriptor] {
        if let bundleID = profile.bundleID {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = running.first, app.processIdentifier > 0 {
                return [TargetDescriptor(kind: .process, name: profile.name,
                                         bundleID: bundleID, pid: app.processIdentifier)]
            }
            return [TargetDescriptor(kind: .process, name: profile.name, bundleID: bundleID, pid: nil)]
        }
        return [TargetDescriptor(kind: .process, name: profile.name)]
    }

    /// Profile "Run Test": first recommended scenario against this app.
    func runProfileTest(_ profile: AppProfile) {
        guard let scenario = profile.recommendedScenarios.first else { return }
        startExperiment(scenario: scenario, targets: targetsForProfile(profile))
    }

    func deleteRecord(_ record: ExperimentRecord) {
        PersistenceStore.shared.deleteRecord(id: record.id)
        history = PersistenceStore.shared.loadRecords()
    }

    // MARK: Recipes (bug recipes)

    /// Save a completed experiment as a reusable recipe: a reproducible
    /// failure condition (fault sequence + seed + targets + assertions).
    func saveRecipe(from record: ExperimentRecord, purpose: String) {
        let recipe = Recipe(reproducing: record, purpose: purpose)
        PersistenceStore.shared.save(recipe: recipe)
        // Also persist the recipe's scenario so suites can include it by id.
        PersistenceStore.shared.save(scenario: recipe.scenario)
        userScenarios = PersistenceStore.shared.loadUserScenarios()
        recipes = PersistenceStore.shared.loadRecipes()
    }

    func runRecipe(_ recipe: Recipe) {
        let config = recipe.makeConfig()
        launch(config)
    }

    func deleteRecipe(_ recipe: Recipe) {
        PersistenceStore.shared.deleteRecipe(id: recipe.id)
        recipes = PersistenceStore.shared.loadRecipes()
    }

    // MARK: Replay

    /// Re-run a past experiment with its exact plan and seed.
    func replay(_ record: ExperimentRecord) {
        let plan = ReplayPlan(config: record.config)
        lastReplaySourceID = record.id
        launch(plan.makeConfig())
    }

    @Published var lastReplaySourceID: UUID?

    // MARK: Random Chaos

    func startRandomChaos(duration: TimeInterval, maxSeverity: Severity,
                          categories: [FaultCategory], seed: UInt64?) {
        let plan = RandomChaosPlanner.plan(
            seed: seed ?? UInt64.random(in: 0...(UInt64.max / 2)),
            duration: duration,
            allowedCategories: categories,
            maxSeverity: maxSeverity
        )
        guard !plan.bindings.isEmpty else { return }
        var config = ExperimentConfig(
            name: "Random Chaos",
            seed: plan.seed,
            plannedDuration: duration,
            bindings: plan.bindings
        )
        config.safetyConfirmed = true
        launch(config)
    }

    // MARK: Suites

    func startSuite(_ suite: ChaosSuite) {
        _ = SuiteRunner.shared.start(suite: suite)
    }

    func stopSuite() {
        SuiteRunner.shared.stop()
    }

    /// Rerun only the failed entries of the last (or current) suite run as a new suite.
    func rerunFailed(from run: SuiteRun) {
        let failedIDs = run.entries.filter { $0.state == .failed }.map(\.scenarioID)
        guard !failedIDs.isEmpty else { return }
        let suite = ChaosSuite(name: "\(run.suiteName) — Rerun Failed", scenarioIDs: failedIDs)
        _ = SuiteRunner.shared.start(suite: suite)
    }

    func saveSuite(name: String, scenarioIDs: [String]) {
        let suite = ChaosSuite(name: name, scenarioIDs: scenarioIDs)
        PersistenceStore.shared.save(suite: suite)
        suites = PersistenceStore.shared.loadSuites()
    }

    func deleteSuite(_ suite: ChaosSuite) {
        PersistenceStore.shared.deleteSuite(id: suite.id)
        suites = PersistenceStore.shared.loadSuites()
    }

    /// Filtered events for the live timeline.
    var filteredEvents: [ExperimentEvent] {
        guard let record = liveRecord else { return [] }
        guard eventFilter != .all else { return record.events }
        return record.events.filter { $0.kind.filterBucket == eventFilter }
    }

    /// Evidence for a given assertion, from the live or historical record.
    func evidence(for assertionID: UUID, in record: ExperimentRecord?) -> Assertion.Evidence? {
        record?.evidenceByAssertion[assertionID]
    }
}

struct SafetyConfirmationRequest: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var confirm: () -> Void
}

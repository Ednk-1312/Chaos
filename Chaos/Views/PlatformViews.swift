import SwiftUI
import ChaosKit

// MARK: - Suites

struct SuitesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var newSuiteName = ""
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Chaos Suites").font(.largeTitle.bold())
                    Text("A suite is a collection of experiments that run sequentially — every fault restored before the next begins.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if app.activeSuiteRun != nil {
                    Button("Stop Suite", role: .destructive) { app.stopSuite() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }

            if let run = app.activeSuiteRun {
                SuiteRunCard(run: run)
                if run.failedCount > 0 {
                    Button {
                        app.rerunFailed(from: run)
                    } label: {
                        Label("Rerun Failed (\(run.failedCount))", systemImage: "arrow.clockwise")
                    }
                    .disabled(app.isRunning)
                }
            }

            HStack {
                TextField("New suite name", text: $newSuiteName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Menu("Add Scenarios (\(selection.count))") {
                    ForEach(ScenarioLibrary.byCategory(), id: \.0) { cat, list in
                        Menu(cat) {
                            ForEach(list) { s in
                                Button(selection.contains(s.id) ? "✓ \(s.name)" : s.name) {
                                    if selection.contains(s.id) { selection.remove(s.id) } else { selection.insert(s.id) }
                                }
                            }
                        }
                    }
                    Divider()
                    Menu("Bug Recipes") {
                        ForEach(app.recipes) { recipe in
                            Button(selection.contains(recipe.scenario.id) ? "✓ \(recipe.name)" : recipe.name) {
                                if selection.contains(recipe.scenario.id) {
                                    selection.remove(recipe.scenario.id)
                                } else {
                                    selection.insert(recipe.scenario.id)
                                }
                            }
                        }
                        if app.recipes.isEmpty {
                            Text("No recipes saved yet")
                        }
                    }
                }
                Button("Create Suite") {
                    guard !newSuiteName.isEmpty, !selection.isEmpty else { return }
                    let allIDs = ScenarioLibrary.all.map(\.id) + app.userScenarios.map(\.id)
                    app.saveSuite(name: newSuiteName, scenarioIDs: allIDs.filter { selection.contains($0) })
                    newSuiteName = ""
                    selection = []
                }
                .disabled(newSuiteName.isEmpty || selection.isEmpty)
            }

            if app.suites.isEmpty {
                Text("No suites yet. Select a release-critical set of scenarios and bundle them into a suite.")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(app.suites) { suite in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(suite.name).font(.headline)
                            Text(suite.scenarioIDs.count + 1 > 1 ? "\(suite.scenarioIDs.count) experiments" : "1 experiment")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Run") { app.startSuite(suite) }
                            .buttonStyle(.borderedProminent)
                            .disabled(app.activeSuiteRun != nil || app.isRunning)
                        Button("Delete", role: .destructive) { app.deleteSuite(suite) }
                            .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
                }
            }
        }
        .padding(24)
        .navigationTitle("Chaos Suites")
    }
}

struct SuiteRunCard: View {
    let run: SuiteRun
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RUNNING: \(run.suiteName)").font(.headline).foregroundStyle(.red)
                Spacer()
                if let started = run.startedAt {
                    Text("elapsed \(now.timeIntervalSince(started).asClockString)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text("\(run.completedCount) / \(run.entries.count) completed — passed \(run.passedCount), failed \(run.failedCount), pending \(run.pendingCount)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            ProgressView(value: Double(run.completedCount), total: Double(max(1, run.entries.count)))
            ForEach(run.entries) { entry in
                HStack {
                    Image(systemName: entry.state.symbolName)
                        .foregroundStyle(color(for: entry.state))
                    Text(entry.scenarioName)
                        .fontWeight(entry.state == .running ? .semibold : .regular)
                    Spacer()
                    Text(entry.state.rawValue).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.scenarioName): \(entry.state.rawValue)")
            }
            Label("Restoration is verified between tests — the next experiment never starts until the previous one has been restored.", systemImage: "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.35)))
        .onReceive(timer) { now = $0 }
    }

    private func color(for state: SuiteState) -> Color {
        switch state {
        case .passed: return .green
        case .failed: return .red
        case .running: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Recipes

struct RecipesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var editingRecipe: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading) {
                Text("Bug Recipes").font(.largeTitle.bold())
                Text("A recipe is not merely a saved experiment — it is a reproducible failure condition: the target, fault sequence, seed, and assertions that produced one specific failure. Fix the bug, then replay the recipe to verify the fix.")
                    .foregroundStyle(.secondary)
            }

            if app.recipes.isEmpty {
                EmptyStateView(
                    symbol: "checklist",
                    title: "NO RECIPES",
                    message: "Save a failed experiment as a reusable bug recipe. Recipes are your regression tests for resilience — run them before every release.",
                    buttonTitle: app.history.isEmpty ? "Run Your First Experiment" : "Open History to Save One"
                ) {
                    app.selectedSection = app.history.isEmpty ? .dashboard : .history
                }
            } else {
                ForEach(app.recipes) { recipe in
                    RecipeCard(recipe: recipe) {
                        editingRecipe = recipe
                    } onDuplicate: {
                        var copy = recipe
                        copy.id = UUID().uuidString
                        copy.name = recipe.name + " copy"
                        PersistenceStore.shared.save(recipe: copy)
                        app.recipes = PersistenceStore.shared.loadRecipes()
                    } onDelete: {
                        app.deleteRecipe(recipe)
                    }
                }
            }
        }
        .padding(24)
        .navigationTitle("Bug Recipes")
        .sheet(item: $editingRecipe) { recipe in
            RecipeEditorSheet(recipe: recipe)
        }
    }
}

struct RecipeCard: View {
    @EnvironmentObject private var app: AppModel
    let recipe: Recipe
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundStyle(.red)
                Text(recipe.name).font(.headline)
                Spacer()
                Button {
                    app.runRecipe(recipe)
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(app.isRunning)
                Menu {
                    Button("Run") { app.runRecipe(recipe) }.disabled(app.isRunning)
                    Button("Replay Exact Plan") {
                        if let sourceID = recipe.sourceExperimentID,
                           let source = app.history.first(where: { $0.id == sourceID }) {
                            app.replay(source)
                        } else {
                            app.runRecipe(recipe)
                        }
                    }
                    .disabled(app.isRunning)
                    Button("Edit…") { onEdit() }
                    Button("Duplicate") { onDuplicate() }
                    Button("Export…") { export() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text(recipe.purpose.isEmpty ? "A reproducible failure condition." : recipe.purpose)
                .font(.callout).foregroundStyle(.secondary)

            if let sourceID = recipe.sourceExperimentID {
                Text("This recipe reproduces the failure observed in experiment \(sourceID.uuidString.prefix(8).uppercased()).")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    Text("Target").font(.caption).foregroundStyle(.secondary)
                    Text(recipe.targetName ?? "Any target").font(.caption)
                }
                GridRow {
                    Text("Seed").font(.caption).foregroundStyle(.secondary)
                    Text(recipe.seed.map(String.init) ?? "not recorded").font(.caption.monospacedDigit())
                }
            }

            RecipeSequenceView(bindings: recipe.scenario.bindings)

            if !recipe.assertions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assertions").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(recipe.assertions) { assertion in
                        Text("• \(assertion.label)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(recipe.name).json"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONEncoder().encode(recipe) else { return }
        try? data.write(to: url)
    }
}

struct RecipeEditorSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Recipe").font(.title3.bold())
            Text("The fault sequence below is the failure condition. Timing and parameters changes apply to future runs of this recipe.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $recipe.name)
                TextField("What failure does this reproduce?", text: $recipe.purpose, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
            RecipeSequenceView(bindings: recipe.scenario.bindings)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    PersistenceStore.shared.save(recipe: recipe)
                    app.recipes = PersistenceStore.shared.loadRecipes()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

// MARK: - Random Chaos setup

struct RandomChaosView: View {
    @EnvironmentObject private var app: AppModel

    @State private var duration: TimeInterval = 300
    @State private var severity: Severity = .high
    @State private var categories: Set<FaultCategory> = [.network, .cpu, .memory]
    @State private var seedText = ""
    @State private var previewPlan: [FaultBinding] = []

    private let durationPresets: [(String, TimeInterval)] = [
        ("30 sec", 30), ("1 min", 60), ("5 min", 300), ("10 min", 600),
    ]

    private var planSeed: UInt64? { UInt64(seedText) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading) {
                    Text("Random Chaos").font(.largeTitle.bold())
                    Text("A seeded, bounded experiment that draws real faults from the categories you allow. Same seed, same plan — the generated sequence is shown before anything runs.")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    // Configuration column
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Severity").font(.headline)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Severity.allCases, id: \.self) { s in
                                    Button {
                                        severity = s
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: severity == s ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(severity == s ? .red : .secondary)
                                            Text(s.title)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Severity \(s.title)")
                                    .accessibilityAddTraits(severity == s ? [.isSelected] : [])
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Categories").font(.headline)
                            ForEach([FaultCategory.network, .cpu, .memory, .storage, .process, .filesystem, .dependency], id: \.self) { cat in
                                Button {
                                    if categories.contains(cat) { categories.remove(cat) } else { categories.insert(cat) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: categories.contains(cat) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(categories.contains(cat) ? .red : .secondary)
                                        Label(cat.title, systemImage: cat.symbolName)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Category \(cat.title)")
                                .accessibilityAddTraits(categories.contains(cat) ? [.isSelected] : [])
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Duration").font(.headline)
                            Picker("Duration", selection: $duration) {
                                ForEach(durationPresets, id: \.1) { label, value in
                                    Text(label).tag(TimeInterval(value))
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seed").font(.headline)
                            TextField("Leave empty for a random seed", text: $seedText)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            generatePlan()
                        } label: {
                            Label("GENERATE PLAN", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(categories.isEmpty)
                    }
                    .frame(width: 300)

                    // Plan preview column
                    VStack(alignment: .leading, spacing: 10) {
                        if previewPlan.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.quaternary)
                                Text("Generate a plan to preview")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Nothing runs until you review the sequence and press RUN GENERATED PLAN.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Text("Generated plan — seed \(seedText)").font(.headline)
                            RecipeSequenceView(bindings: previewPlan)
                            Divider()
                            Button {
                                app.startRandomChaos(duration: duration, maxSeverity: severity,
                                                     categories: Array(categories),
                                                     seed: planSeed)
                            } label: {
                                Label("RUN GENERATED PLAN", systemImage: "bolt.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(app.isRunning)
                            Text("Reproducible: this exact seed regenerates this exact plan.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 380, alignment: .topLeading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                }

                Text(ReplayPlan.replayNotice)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .navigationTitle("Random Chaos")
    }

    private func generatePlan() {
        let seed = planSeed ?? UInt64.random(in: 0...(UInt64.max / 2))
        seedText = String(seed)
        let plan = RandomChaosPlanner.plan(seed: seed, duration: duration,
                                           allowedCategories: Array(categories),
                                           maxSeverity: severity)
        previewPlan = plan.bindings
    }
}

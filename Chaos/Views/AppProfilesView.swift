import SwiftUI
import ChaosKit

// MARK: - Profiles Grid (Settings → Applications)

struct AppProfilesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Applications").font(.largeTitle.bold())
                    Text("A profile is one application under test. Chaos personalizes experiments, recipes, and resilience history around it.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showSetup = true
                } label: {
                    Label("Add Application", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if app.profiles.isEmpty {
                EmptyStateView(
                    symbol: "app.badge.checkmark",
                    title: "NO APPLICATIONS YET",
                    message: "Pick one application and give every failure test a home. Chaos recommends tests based only on what you configure.",
                    buttonTitle: "Add Application"
                ) { showSetup = true }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(app.profiles) { profile in
                        AppProfileCard(profile: profile)
                    }
                }

                if let selected = app.selectedProfile {
                    AppProfileDetailView(profile: selected)
                }
            }
        }
        .padding(24)
        .navigationTitle("Applications")
        .sheet(isPresented: $showSetup) {
            ProfileSetupSheet()
        }
    }
}

struct AppProfileCard: View {
    @EnvironmentObject private var app: AppModel
    let profile: AppProfile

    var body: some View {
        Button {
            app.selectedProfile = profile
        } label: {
            HStack(spacing: 12) {
                AppIconView(iconData: profile.iconData, bundleID: profile.bundleID, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.headline).foregroundStyle(.primary)
                    Text(profile.bundleID ?? "Local process target")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(app.selectedProfile?.id == profile.id ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile \(profile.name)")
    }
}

// MARK: - Profile Detail

struct AppProfileDetailView: View {
    @EnvironmentObject private var app: AppModel
    let profile: AppProfile
    @State private var releaseSuiteName = ""

    private var records: [ExperimentRecord] {
        profile.matchingRecords(in: app.history).sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }
    private var profileRecipes: [Recipe] {
        app.recipes.filter { $0.targetName == profile.name }
    }
    private var failures: [ExperimentRecord] { records.filter { $0.outcome == .failed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Identity + primary actions
            HStack(spacing: 14) {
                AppIconView(iconData: profile.iconData, bundleID: profile.bundleID, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.name).font(.title2.bold())
                        if let v = profile.version, !v.isEmpty {
                            Text("v\(v)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let bundle = profile.bundleID {
                        Text(bundle).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    if let exec = profile.executablePath {
                        Text(exec).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        app.runProfileTest(profile)
                    } label: {
                        Label("RUN TEST", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(app.isRunning)
                    HStack(spacing: 6) {
                        Button("New Experiment") {
                            app.showExperimentBuilder = true
                        }
                        .disabled(app.isRunning)
                        Button("View History") {
                            app.selectedSection = .history
                        }
                    }
                    .controlSize(.small)
                }
            }

            // Recent resilience — only real records, ✓ ✗ ⚠ per spec
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Resilience").font(.headline)
                if records.isEmpty {
                    Text("No experiments have targeted this application yet. RUN TEST starts a recommended scenario and builds history.")
                        .font(.callout).foregroundStyle(.tertiary)
                } else {
                    ForEach(records.prefix(6)) { record in
                        HStack {
                            Image(systemName: outcomeSymbol(record.outcome))
                                .foregroundStyle(outcomeColor(record.outcome))
                            Text(record.config.name).font(.callout)
                            Spacer()
                            Text(record.startedAt.map { RecentExperimentRow.dateFormatter.string(from: $0) } ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(record.config.name): \(record.outcome.title)")
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

            HStack(alignment: .top, spacing: 14) {
                // Recommended tests — evidence-based only
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended Tests").font(.headline)
                    Text("Based only on what you configured. No dependency is assumed unless you declared one.")
                        .font(.caption).foregroundStyle(.tertiary)
                    let recommended = profile.recommendedScenarios
                    if recommended.isEmpty {
                        Text("No recommendations yet.").font(.callout).foregroundStyle(.tertiary)
                    }
                    ForEach(recommended) { scenario in
                        HStack {
                            Image(systemName: scenario.symbolName).foregroundStyle(.red)
                            Text(scenario.name).font(.callout)
                            Spacer()
                            Button("Run") {
                                app.startExperiment(scenario: scenario, targets: app.targetsForProfile(profile))
                            }
                            .controlSize(.small)
                            .disabled(app.isRunning)
                        }
                    }
                    if !profile.configuredDependencies.isEmpty {
                        Divider()
                        Text("Declared dependencies: \(profile.configuredDependencies.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

                // Recipes + release suite + failures
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bug Recipes (\(profileRecipes.count))").font(.headline)
                    if profileRecipes.isEmpty {
                        Text("Save a failed experiment as a recipe and replay it before every release.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(profileRecipes.prefix(4)) { recipe in
                        HStack {
                            Image(systemName: "checklist").foregroundStyle(.red)
                            Text(recipe.name).font(.callout).lineLimit(1)
                            Spacer()
                            Button("Run") { app.runRecipe(recipe) }
                                .controlSize(.small)
                                .disabled(app.isRunning)
                        }
                    }

                    Divider()

                    Text("Release Suite").font(.headline)
                    HStack {
                        TextField("Suite name", text: $releaseSuiteName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 170)
                        Button("Run Release Suite") {
                            let ids = profile.recommendedScenarioIDs.isEmpty
                                ? ["terrible-wifi", "memory-moderate"]
                                : profile.recommendedScenarioIDs
                            app.saveSuite(name: releaseSuiteName.isEmpty ? "\(profile.name) Release" : releaseSuiteName,
                                          scenarioIDs: ids)
                            if let suite = app.suites.first(where: { $0.name == (releaseSuiteName.isEmpty ? "\(profile.name) Release" : releaseSuiteName) }) {
                                app.startSuite(suite)
                            }
                            releaseSuiteName = ""
                        }
                        .disabled(app.activeSuiteRun != nil || app.isRunning)
                    }
                    .font(.callout)

                    if !failures.isEmpty {
                        Divider()
                        Text("Recent Failures").font(.headline).foregroundStyle(.red)
                        ForEach(failures.prefix(3)) { record in
                            Text("• \(record.config.name)").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }

    private func outcomeSymbol(_ outcome: ExperimentOutcome) -> String {
        switch outcome {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        default: return "questionmark.circle"
        }
    }

    private func outcomeColor(_ outcome: ExperimentOutcome) -> Color {
        switch outcome {
        case .passed: return .green
        case .failed: return .red
        case .warning: return .orange
        default: return .secondary
        }
    }
}

// MARK: - App Icon (honest: real icon when available, generic otherwise)

struct AppIconView: View {
    let iconData: Data?
    let bundleID: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = iconData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let bundleID, let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Profile Setup

struct ProfileSetupSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bundleID = ""
    @State private var version = ""
    @State private var dependencyText = ""
    @State private var iconData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Application Profile").font(.title3.bold())
            Text("Chaos uses only what you enter here. Nothing about your app is inferred or uploaded.")
                .font(.callout).foregroundStyle(.secondary)

            Form {
                TextField("Application name", text: $name)
                TextField("Bundle identifier (optional, e.g. com.company.myapp)", text: $bundleID)
                TextField("Version (optional)", text: $version)
                TextField("Dependencies, comma-separated (optional — leave empty if none)", text: $dependencyText)
                HStack {
                    Button("Choose .app…") { chooseApp() }
                    if iconData != nil {
                        Text("App icon captured").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Profile") {
                    var profile = AppProfile(
                        name: name,
                        bundleID: bundleID.isEmpty ? nil : bundleID,
                        version: version.isEmpty ? nil : version,
                        iconData: iconData,
                        configuredDependencies: dependencyText.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    )
                    if !bundleID.isEmpty, let rec = profile.recommendedScenarios.first {
                        profile.recommendedScenarioIDs = [rec.id]
                    }
                    app.saveProfile(profile)
                    app.selectedProfile = profile
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if bundleID.isEmpty {
            bundleID = (Bundle(url: url)?.bundleIdentifier ?? "")
        }
        if version.isEmpty {
            version = (Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        }
        iconData = NSWorkspace.shared.icon(forFile: url.path)
            .tiffRepresentation
    }
}

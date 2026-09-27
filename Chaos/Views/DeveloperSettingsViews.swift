import SwiftUI
import ChaosKit

// MARK: - Targets

struct TargetsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var runningApps: [(name: String, bundleID: String, pid: Int32, localizedName: String)] = []
    @State private var isDropTargeted = false
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Targets").font(.largeTitle.bold())
                Text("Pick the application Chaos will break. Drag an .app here, choose one, or select a running process.")
                    .foregroundStyle(.secondary)
            }

            // Current target — icon prominent (Section 20)
            if let target = app.primaryTarget {
                HStack(spacing: 14) {
                    AppIconView(iconData: target.iconData, bundleID: target.bundleID, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.name).font(.title3.bold())
                        Text(target.bundleID ?? target.path ?? "pid \(target.pid ?? 0)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let pid = target.pid {
                            Text("running as pid \(pid)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { app.setPrimaryTarget(nil) }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(isDropTargeted ? 0.12 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red.opacity(isDropTargeted ? 0.7 : 0.3), lineWidth: isDropTargeted ? 2 : 1)
                )
            } else {
                // Drop zone with large icon frame (the ┌───┐ [APP ICON] ┌───┐ from the spec)
                TargetDropZone(isTargeted: isDropTargeted, onPicker: { showPicker = true }) {
                    refreshRunningApps()
                }
            }

            if !app.recentTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Targets").font(.headline)
                    HStack(spacing: 10) {
                        ForEach(app.recentTargets) { target in
                            Button {
                                app.setPrimaryTarget(target)
                            } label: {
                                VStack(spacing: 5) {
                                    AppIconView(iconData: target.iconData, bundleID: target.bundleID, size: 30)
                                    Text(target.name).font(.caption2).lineLimit(1)
                                }
                                .frame(width: 76)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set \(target.name) as target")
                        }
                    }
                }
            }

            Text("Running Applications").font(.headline)
            List {
                ForEach(runningApps, id: \.pid) { appInfo in
                    HStack(spacing: 10) {
                        AppIconView(iconData: nil, bundleID: appInfo.bundleID.isEmpty ? nil : appInfo.bundleID, size: 22)
                        Text(appInfo.localizedName)
                        Spacer()
                        Text("pid \(appInfo.pid)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button("Set as Target") {
                            app.setPrimaryTarget(TargetDescriptor(
                                kind: .process, name: appInfo.localizedName,
                                bundleID: appInfo.bundleID.isEmpty ? nil : appInfo.bundleID,
                                pid: appInfo.pid
                            ))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(minHeight: 260)
        }
        .padding(24)
        .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear { refreshRunningApps() }
        .sheet(isPresented: $showPicker) { AppPickerSheet() }
        .navigationTitle("Targets")
    }

    private func refreshRunningApps() {
        let visible = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        runningApps = visible.compactMap { application in
            guard let name = application.localizedName else { return nil }
            return (name, application.bundleIdentifier ?? "", application.processIdentifier, name)
        }
        .sorted { $0.localizedName < $1.localizedName }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let nsurl = item as? URL {
                url = nsurl
            }
            guard let url, url.pathExtension == "app" else { return }
            DispatchQueue.main.async {
                let bundle = Bundle(url: url)
                let target = TargetDescriptor(
                    kind: .application, name: bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent,
                    bundleID: bundle?.bundleIdentifier,
                    path: url.path,
                    iconData: NSWorkspace.shared.icon(forFile: url.path).tiffRepresentation
                )
                app.setPrimaryTarget(target)
            }
            return
        }
        return true
    }
}

/// Empty-target drop zone: drag an .app here (Section 20).
struct TargetDropZone: View {
    let isTargeted: Bool
    var onPicker: () -> Void
    var onRunning: () -> Void

    private var titleColor: Color { isTargeted ? .red : .secondary }
    private var iconColor: Color { isTargeted ? .red : Color.secondary.opacity(0.4) }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(iconColor)
            Text(isTargeted ? "Release to set target" : "Drag an .app here")
                .font(.headline)
                .foregroundStyle(titleColor)
            HStack(spacing: 8) {
                Button("Choose Application…") { onPicker() }
                Button("Pick a Running Process") { onRunning() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(dropBackground)
        .overlay(dropBorder)
    }

    private var dropBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor).opacity(isTargeted ? 1 : 0.5))
    }

    private var dropBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.secondary.opacity(isTargeted ? 0.8 : 0.2),
                          style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6]))
    }
}

struct AppPickerSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [(name: String, bundleID: String, path: String)] = []
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Application").font(.title3.bold())
            TextField("Filter…", text: $query)
                .textFieldStyle(.roundedBorder)
            List(filteredApps, id: \.path) { application in
                Button {
                    let target = TargetDescriptor(
                        kind: .application, name: application.name,
                        bundleID: application.bundleID.isEmpty ? nil : application.bundleID,
                        path: application.path,
                        iconData: NSWorkspace.shared.icon(forFile: application.path).tiffRepresentation
                    )
                    app.setPrimaryTarget(target)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        AppIconView(iconData: nil, bundleID: application.bundleID.isEmpty ? nil : application.bundleID, size: 24)
                        Text(application.name)
                        Spacer()
                        Text(application.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 320)
        }
        .padding(20)
        .frame(width: 460, height: 440)
        .onAppear(perform: loadApps)
    }

    private var filteredApps: [(name: String, bundleID: String, path: String)] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

    private func loadApps() {
        var found: [(String, String, String)] = []
        let directories = ["/Applications", "/System/Applications",
                           NSString(string: "~/Applications").expandingTildeInPath]
        let fileManager = FileManager.default
        for directory in directories {
            guard let items = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = directory + "/" + item
                let bundle = Bundle(path: path)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? item.replacingOccurrences(of: ".app", with: "")
                found.append((name, bundle?.bundleIdentifier ?? "", path))
            }
        }
        apps = found.sorted { $0.0 < $1.0 }
    }
}

// MARK: - Developer

struct CLIGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CLI").font(.largeTitle.bold())
                Text("The chaos CLI drives the same engine as this app — perfect for CI, scripts, and Makefiles.")
                    .foregroundStyle(.secondary)

                CodeBlock(title: "Install", code: "sudo cp \"$(pwd)/build/Debug/Chaos.app/Contents/Helpers/chaos\" /usr/local/bin/chaos")
                CodeBlock(title: "Run a scenario non-interactively", code: "chaos run terrible-wifi --duration 120 --yes")
                CodeBlock(title: "Xcode build phase", code: "chaos run release-candidate --duration 600 --yes --name \"UI Tests $CONFIGURATION\"")
                CodeBlock(title: "Export the last report", code: "chaos records\nchaos report <id> --format md --out report.md")
            }
            .padding(24)
        }
        .navigationTitle("CLI")
    }
}

struct CodeBlock: View {
    let title: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.borderless)
            }
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

struct AutomationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Automation").font(.largeTitle.bold())
                Text("Trigger chaos from anywhere. The engine works headless — no GUI required.")
                    .foregroundStyle(.secondary)
                CodeBlock(title: "cron — nightly resilience run", code: "0 3 * * * /usr/local/bin/chaos run release-candidate --yes --name nightly")
                CodeBlock(title: "Git pre-push hook", code: "#!/bin/sh\nchaos run server-outage --duration 60 --yes --name pre-push")
            }
            .padding(24)
        }
        .navigationTitle("Automation")
    }
}

struct IntegrationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Integrations").font(.largeTitle.bold())
                Text("Honest status of what integrates with what.")
                    .foregroundStyle(.secondary)
                Label("CLI is fully supported today (same engine as the GUI).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("Xcode works via build phases calling the CLI — no private integration.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("Cloud sync is intentionally not built in. Your data stays local.", systemImage: "lock.shield.fill")
                    .foregroundStyle(.blue)
            }
            .padding(24)
        }
        .navigationTitle("Integrations")
    }
}

// MARK: - Command Palette

struct CommandPaletteView: View {
    @EnvironmentObject private var app: AppModel
    @State private var query = ""
    @State private var selectedIndex = 0
    // Local key monitor: guarantees Escape / ↑ / ↓ work regardless of which
    // control has focus (a focused text field otherwise eats arrow keys).
    @State private var keyMonitor: Any?

    private struct Command: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let action: () -> Void
    }

    private var commands: [Command] {
        var commands: [Command] = [
            Command(title: "Run Experiment", symbol: "play.circle") { app.runPrimaryExperiment() },
            Command(title: "New Experiment (Visual Builder)", symbol: "wand.and.stars") { app.showExperimentBuilder = true },
            Command(title: "Stop Chaos", symbol: "stop.circle") { app.stopChaos() },
            Command(title: "Emergency Stop", symbol: "exclamationmark.octagon") { app.emergencyStop() },
            Command(title: "Restore System", symbol: "arrow.uturn.backward.circle") { app.restoreEverything() },
            Command(title: "Repeat Last Experiment", symbol: "clock.arrow.circlepath") {
                if let last = app.history.first {
                    var config = last.config
                    config.id = UUID()
                    config.safetyConfirmed = true
                    app.launch(config)
                }
            },
        ]

        // Navigation
        for section in SidebarSection.allCases {
            commands.append(Command(title: "Go to \(section.title)", symbol: section.symbolName) {
                app.selectedSection = section
            })
        }

        // Applications (profiles)
        for profile in app.profiles.prefix(8) {
            commands.append(Command(title: "Run Test: \(profile.name)", symbol: "app.badge.checkmark") {
                app.runProfileTest(profile)
            })
        }

        // Faults (open library)
        for fault in FaultCatalog.all.prefix(20) {
            commands.append(Command(title: "Fault: \(fault.name)", symbol: fault.category.symbolName) {
                app.selectedSection = .faultLibrary
            })
        }

        // Scenarios
        for scenario in ScenarioLibrary.all.prefix(20) {
            commands.append(Command(title: "Scenario: \(scenario.name)", symbol: scenario.symbolName) {
                app.startExperiment(scenario: scenario, targets: app.primaryTarget.map { [$0] } ?? [])
            })
        }

        // Recipes: run / replay / duplicate / export
        for recipe in app.recipes.prefix(10) {
            commands.append(Command(title: "Recipe: \(recipe.name) — Run", symbol: "checklist") { app.runRecipe(recipe) })
            commands.append(Command(title: "Recipe: \(recipe.name) — Duplicate", symbol: "plus.square.on.square") {
                var copy = recipe
                copy.id = UUID().uuidString
                copy.name = recipe.name + " copy"
                PersistenceStore.shared.save(recipe: copy)
                app.recipes = PersistenceStore.shared.loadRecipes()
            })
        }

        // Suites
        for suite in app.suites.prefix(8) {
            commands.append(Command(title: "Suite: \(suite.name) — Run", symbol: "list.star") { app.startSuite(suite) })
        }

        // Recent experiments: replay / stop
        for record in app.history.prefix(8) {
            commands.append(Command(title: "Replay Experiment: \(record.config.name)", symbol: "arrow.uturn.backward.circle") {
                app.replay(record)
            })
        }

        return commands
    }

    private var filtered: [Command] {
        query.isEmpty ? commands : commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func run(_ command: Command) {
        app.showCommandPalette = false
        command.action()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard app.showCommandPalette else { return event }
            switch event.keyCode {
            case 53: // Escape
                app.showCommandPalette = false
                return nil
            case 125: // Down
                selectedIndex = min(max(0, filtered.count - 1), selectedIndex + 1)
                return nil
            case 126: // Up
                selectedIndex = max(0, selectedIndex - 1)
                return nil
            default:
                return event
            }
        }
    }

    var body: some View {
        ZStack {
            // Click anywhere outside the panel dismisses the palette.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { app.showCommandPalette = false }

            VStack(spacing: 0) {
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(16)
                    .onSubmit {
                        if filtered.indices.contains(selectedIndex) {
                            run(filtered[selectedIndex])
                        }
                    }
                Divider()
                List(filtered.indices, id: \.self) { index in
                    let command = filtered[index]
                    Button {
                        run(command)
                    } label: {
                        Label(command.title, systemImage: command.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(index == selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(width: 480, height: 360)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 30)
            // Escape dismisses; arrows move the selection (Enter runs it).
            .onExitCommand { app.showCommandPalette = false }
            .onMoveCommand { direction in
                switch direction {
                case .up: selectedIndex = max(0, selectedIndex - 1)
                case .down: selectedIndex = min(max(0, filtered.count - 1), selectedIndex + 1)
                default: break
                }
            }
            .padding(120)
        }
        .onChange(of: query) { _ in selectedIndex = 0 }
        .onAppear {
            selectedIndex = 0
            installKeyMonitor()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var app: AppModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                VStack(spacing: 16) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                    Text("Meet Chaos.").font(.largeTitle.bold())
                    Text("Your app works perfectly.\nLet's see what happens when it doesn't.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .tag(0)
                VStack(spacing: 16) {
                    Text("Three steps.").font(.title2.bold())
                    Label("Choose an application", systemImage: "app").padding(6)
                    Label("Choose what goes wrong", systemImage: "bolt").padding(6)
                    Label("CREATE CHAOS", systemImage: "bolt.fill").padding(6)
                }
                .tag(1)
                VStack(spacing: 16) {
                    Text("Trust is the product.").font(.title2.bold())
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Chaos never pretends a test happened when it didn't.", systemImage: "checkmark.seal")
                        Label("Chaos never claims restoration without verification.", systemImage: "checkmark.seal")
                        Label("Chaos never labels unsupported macOS behavior as real.", systemImage: "checkmark.seal")
                    }
                    .font(.callout)
                    Text("Chaos asks before anything extreme, restores everything on stop, and sweeps for leftovers if it ever crashes.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .tag(2)
            }
            .frame(height: 280)

            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                Spacer()
                Button(page < 2 ? "Next" : "Start Breaking Things") {
                    if page < 2 { page += 1 } else { app.completeOnboarding() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(32)
        .frame(width: 540)
    }
}

// MARK: - Settings

struct GeneralSettingsView: View {
    @AppStorage("chaos.menubar.enabled") private var menuBarEnabled = false

    var body: some View {
        Form {
            Text("Chaos stores everything locally under ~/Library/Application Support/Chaos. Nothing is uploaded, ever.")
                .foregroundStyle(.secondary)
            Section("Menu Bar") {
                Toggle("Show Chaos in the menu bar", isOn: $menuBarEnabled)
                Text("Off by default. When enabled, a small Chaos item offers status and emergency stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .navigationTitle("General")
    }
}

struct SafetySettingsView: View {
    @AppStorage("chaos.safety.requireExtremeConfirmation") private var requireExtremeConfirmation = true
    @AppStorage("chaos.safety.autoRestoreOnQuit") private var autoRestoreOnQuit = true

    var body: some View {
        Form {
            Toggle("Require explicit confirmation for Extreme scenarios", isOn: $requireExtremeConfirmation)
            Toggle("Restore everything when Chaos quits", isOn: $autoRestoreOnQuit)
            Text("Safety ceilings are always on: Chaos never fills your real disk and never allocates memory past a hard limit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle("Safety")
    }
}

struct PrivilegesView: View {
    var body: some View {
        Form {
            Label("Chaos runs unprivileged", systemImage: "checkmark.shield")
                .foregroundStyle(.green)
            Text("Most faults need no special access. Network faults use pf/dummynet, which triggers a one-time OS authorization prompt — Chaos never installs persistent privileged helpers.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle("Privileges")
    }
}

struct AppearanceSettingsView: View {
    var body: some View {
        Form {
            Text("Chaos follows your system appearance (light/dark). Accent: system red — the color of controlled destruction.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle("Appearance")
    }
}

struct NotificationSettingsView: View {
    @AppStorage("chaos.notify.onComplete") private var onComplete = true
    @AppStorage("chaos.notify.onFailure") private var onFailure = true
    @AppStorage("chaos.notify.onRestoreIssue") private var onRestoreIssue = true

    var body: some View {
        Form {
            Toggle("Notify when an experiment completes", isOn: $onComplete)
            Toggle("Notify when an assertion fails", isOn: $onFailure)
            Toggle("Notify when restoration needs attention", isOn: $onRestoreIssue)
        }
        .padding(24)
        .navigationTitle("Notifications")
    }
}

struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Text("Advanced knobs land with the Experiment Builder v2: conditional triggers, thresholds, staged escalation.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle("Advanced")
    }
}

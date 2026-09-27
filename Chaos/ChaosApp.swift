import SwiftUI
import ChaosKit

@main
struct ChaosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { app.bootstrap() }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Experiment…") { app.showExperimentBuilder = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("Chaos") {
                Button(app.isRunning ? "Stop Chaos" : "Run Experiment") {
                    if app.isRunning { app.stopChaos() } else { app.runPrimaryExperiment() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Emergency Stop") { app.emergencyStop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!app.isRunning)

                Divider()
                Button("Restore Everything") { app.restoreEverything() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()
                Button("Command Palette…") { app.toggleCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("Navigate") {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.offset) { index, section in
                    Button(section.title) { app.selectSection(section) }
                        .keyboardShortcut(KeyEquivalent(Character("\(min(index + 1, 9))")), modifiers: .command)
                }
            }
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Optional menu bar item (Section 22)
// SwiftUI's SceneBuilder cannot conditionally include scenes, so the optional
// menu-bar item uses a native NSStatusItem, rebuilt whenever the user toggles
// the setting (Settings → General). Default is OFF.
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var observer: NSObjectProtocol?

    func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
        rebuild()
    }

    func rebuild() {
        let enabled = UserDefaults.standard.bool(forKey: "chaos.menubar.enabled")
        if !enabled {
            statusItem?.menu = nil
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        let running = ExperimentEngine.shared.liveSnapshot != nil
        let status = NSMenuItem(title: running ? "CHAOS ACTIVE" : "No Active Experiments",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if running {
            menu.addItem(NSMenuItem(title: "Stop Chaos", action: #selector(AppDelegate.menuStopChaos), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Emergency Stop", action: #selector(AppDelegate.menuEmergencyStop), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Run Last Experiment", action: #selector(AppDelegate.menuRunLast), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Restore", action: #selector(AppDelegate.menuRestore), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Chaos", action: #selector(AppDelegate.menuOpen), keyEquivalent: ""))

        menu.items.forEach { $0.target = nil }
        item.menu = menu
        item.button?.image = NSImage(systemSymbolName: running ? "bolt.fill" : "bolt.slash",
                                     accessibilityDescription: "Chaos menu bar item")
        statusItem = item
    }
}

// MARK: - Offscreen snapshot harness (QA only)
// Launch with `-chaos.snapshot <path>` (and optional `-chaos.section <name>`,
// `-chaos.openBuilder`) to render the real view tree with real persisted state
// to a PNG and quit. Used for automated visual inspection; not reachable
// through any UI.
@MainActor
enum SnapshotHarness {
    static func captureIfNeeded(_ app: AppModel) {
        guard let raw = UserDefaults.standard.string(forKey: "chaos.snapshot"), !raw.isEmpty else { return }
        let path = (raw as NSString).expandingTildeInPath
        let openBuilder = UserDefaults.standard.bool(forKey: "chaos.openBuilder")
        let width = CGFloat(UserDefaults.standard.object(forKey: "chaos.snapshotWidth") as? Int ?? 1440)
        let height = CGFloat(UserDefaults.standard.object(forKey: "chaos.snapshotHeight") as? Int ?? 900)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Render offscreen: a borderless window backs the hosting view so
            // SwiftUI mounts normally. NOTE: NSVisualEffectView materials can't
            // composite without WindowServer access and may render as plain
            // white blocks in the PNG (harness artifact only — on-screen the
            // app renders them correctly). Content layout is unaffected.
            NSApp.appearance = NSAppearance(named: .darkAqua)
            let root: AnyView = openBuilder
                ? AnyView(ExperimentBuilderView().environmentObject(app))
                : AnyView(RootView().environmentObject(app))
            let host = NSHostingView<AnyView>(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.contentView = host
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    FileHandle.standardError.write(Data("snapshot: bitmap rep failed\n".utf8))
                    exit(2)
                }
                host.cacheDisplay(in: host.bounds, to: rep)
                guard let tiff = rep.tiffRepresentation,
                      let img = NSBitmapImageRep(data: tiff),
                      let png = img.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write(Data("snapshot: PNG encode failed\n".utf8))
                    exit(2)
                }
                do {
                    try png.write(to: URL(fileURLWithPath: path))
                } catch {
                    FileHandle.standardError.write(Data("snapshot: write failed: \(error)\n".utf8))
                    exit(2)
                }
                exit(0)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.startObserving()
        SnapshotHarness.captureIfNeeded(AppModel.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Fail safely: if an experiment is mid-flight at quit, stop and restore everything.
        if ExperimentEngine.shared.liveSnapshot != nil {
            ExperimentEngine.shared.stop(reason: .emergencyStop)
        }
        FaultCleanup.performBootSweep()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Menu bar actions (safe no-ops handled inside AppModel)
    @objc func menuStopChaos() { AppModel.shared.stopChaos() }
    @objc func menuEmergencyStop() { AppModel.shared.emergencyStop() }
    @objc func menuRestore() { AppModel.shared.restoreEverything() }
    @objc func menuOpen() { NSApp.activate(ignoringOtherApps: true); AppModel.shared.selectedSection = .dashboard }
    @objc func menuRunLast() {
        guard let last = AppModel.shared.history.first else { return }
        var config = last.config
        config.id = UUID()
        config.safetyConfirmed = true
        AppModel.shared.launch(config)
    }
}

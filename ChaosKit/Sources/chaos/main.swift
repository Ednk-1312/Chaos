// chaos — the Chaos CLI. Uses the exact same engine as the GUI app.
//
//   chaos list faults|scenarios|suites|recipes|targets
//   chaos run <scenario> [--seed N] [--duration S] [--target NAME] [--json] [--quiet]
//   chaos replay <record-id> [--json]
//   chaos suite <suite-id> [--json]
//   chaos stop
//   chaos restore
//   chaos status [--json]
//   chaos report <record-id> --format md|json|csv [--out PATH]

import Foundation
import ChaosKit

let args = Array(CommandLine.arguments.dropFirst())

// Headless mode: privileged fault activation never opens GUI dialogs.
setenv("CHAOS_HEADLESS", "1", 1)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("chaos: \(message)\n".data(using: .utf8)!)
    exit(2)
}

func flag(_ name: String) -> Bool { args.contains(name) }
func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let json = flag("--json")
let quiet = flag("--quiet")

func say(_ message: String) {
    if !json && !quiet { print(message) }
}

let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}()

guard let command = args.first else {
    print("""
    chaos — controlled failure injection for macOS

    USAGE:
        chaos list faults|scenarios|suites|recipes|targets
        chaos run <scenario-id> [options]     Run a scenario
        chaos replay <record-id> [options]    Replay a past experiment exactly
        chaos suite <suite-id>                Run a Chaos Suite sequentially
        chaos status [--json]                 Show engine state
        chaos stop                            Stop the running experiment
        chaos restore                         Full restore sweep
        chaos records                         List experiment history
        chaos report <id> --format md|json|csv [--out PATH]

    RUN OPTIONS:
        --seed N          Force a specific seed (reproducibility identity)
        --duration S      Override duration in seconds
        --target NAME     Attach a target by process name
        --yes             Skip the safety confirmation prompt (CI use)
        --json            Machine-readable output
        --quiet           Suppress progress output

    Exit codes: 0 passed · 1 failed · 2 usage/aborted · 3 warning/inconclusive · 4 stopped
    """)
    exit(0)
}

func resolveScenario(_ id: String) -> Scenario? {
    ScenarioLibrary.all.first { $0.id == id }
        ?? PersistenceStore.shared.loadUserScenarios().first { $0.id == id }
}

func outcomeExitCode(_ outcome: ExperimentOutcome) -> Int32 {
    switch outcome {
    case .passed: return 0
    case .failed: return 1
    case .warning, .inconclusive: return 3
    case .stopped: return 4
    default: return 3
    }
}

func waitForCompletion() -> ExperimentRecord? {
    let sema = DispatchSemaphore(value: 0)
    let box = RecordBox()
    let prev = ExperimentEngine.shared.onRecordUpdate
    ExperimentEngine.shared.onRecordUpdate = { record in
        prev?(record)
        if record.outcome != .running { box.record = record }
    }
    let prevState = ExperimentEngine.shared.onStateChange
    ExperimentEngine.shared.onStateChange = { state in
        prevState?(state)
        if case .idle = state { sema.signal() }
    }
    _ = sema.wait(timeout: .now() + 3600 * 2)
    return box.record
}

func runScenario(_ scenario: Scenario, seedOverride: UInt64?, durationOverride: TimeInterval?, targetName: String?, confirmed: Bool) -> ExperimentRecord? {
    var targets: [TargetDescriptor] = []
    if let targetName, !targetName.isEmpty {
        let pid = ProcessScanner.snapshot().first { $0.shortName == targetName }?.pid
        targets = [TargetDescriptor(kind: .process, name: targetName, pid: pid)]
        if pid == nil {
            say("warning: target '\(targetName)' is not currently running; liveness assertions will be skipped")
        }
    }

    let config = scenario.makeConfig(
        seed: seedOverride,
        targets: targets,
        safetyConfirmed: confirmed
    )
    let effective = durationOverride.map { duration -> ExperimentConfig in
        var trimmed = config
        trimmed.plannedDuration = duration
        return trimmed.with(bindings: config.bindings.map { b in
            var b = b
            b.duration = max(5, duration - b.startOffset)
            return b
        })
    } ?? config

    do {
        let record = try ExperimentEngine.shared.start(config: effective)
        say("experiment \(record.id.uuidString.prefix(8)) started — seed \(effective.seed)")
        return waitForCompletion()
    } catch {
        fail("\(error.localizedDescription)")
    }
}

switch command {

case "list":
    let sub = args.count > 1 ? args[1] : "scenarios"
    switch sub {
    case "faults":
        let supported = Set(DefaultFaultRegistry.supportedFaultIDs.map(\.rawValue))
        if json {
            let items = FaultCatalog.all.map { f in
                ["id": f.id.rawValue, "name": f.name, "severity": f.severity.rawValue,
                 "runnable": String(supported.contains(f.id.rawValue)),
                 "simulated": String(f.simulated)]
            }
            print(String(data: try! jsonEncoder.encode(items), encoding: .utf8)!)
        } else {
            for f in FaultCatalog.all {
                let mark = supported.contains(f.id.rawValue) ? "runnable" : "guided"
                let sim = f.simulated ? " [SIMULATED]" : ""
                print("\(f.id.rawValue.padding(toLength: 34, withPad: " ", startingAt: 0)) \(f.severity.title.padding(toLength: 9, withPad: " ", startingAt: 0)) \(mark.padding(toLength: 9, withPad: " ", startingAt: 0))\(sim) \(f.name)")
            }
        }
    case "scenarios":
        if json {
            let items = ScenarioLibrary.all.map { s in
                ["id": s.id, "name": s.name, "category": s.category, "extreme": String(s.isExtreme)]
            }
            print(String(data: try! jsonEncoder.encode(items), encoding: .utf8)!)
        } else {
            for (cat, list) in ScenarioLibrary.byCategory() {
                print("\n\(cat)")
                for s in list {
                    print("  \(s.id.padding(toLength: 24, withPad: " ", startingAt: 0)) \(s.summary)")
                }
            }
        }
    case "suites":
        let suites = PersistenceStore.shared.loadSuites()
        if json {
            print(String(data: try! jsonEncoder.encode(suites), encoding: .utf8)!)
        } else if suites.isEmpty {
            print("no suites saved — create one in the app or via a JSON file")
        } else {
            for s in suites { print("\(s.id.uuidString.prefix(8))  \(s.name)  (\(s.scenarioIDs.count) experiments)") }
        }
    case "recipes":
        let recipes = PersistenceStore.shared.loadRecipes()
        if json {
            print(String(data: try! jsonEncoder.encode(recipes), encoding: .utf8)!)
        } else if recipes.isEmpty {
            print("no recipes saved")
        } else {
            for r in recipes { print("\(r.id.prefix(8))  \(r.name) — \(r.purpose)") }
        }
    case "targets":
        let procs = ProcessScanner.snapshot().filter { $0.user == NSUserName() }
        if json {
            let items = procs.map { ["pid": String($0.pid), "name": $0.shortName, "cpu": String(format: "%.1f", $0.cpuPercent)] }
            print(String(data: try! jsonEncoder.encode(items), encoding: .utf8)!)
        } else {
            for p in procs.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(25) {
                print("pid \(String(p.pid).padding(toLength: 7, withPad: " ", startingAt: 0)) \(p.shortName)")
            }
        }
    default:
        fail("unknown list subject '\(sub)' — faults, scenarios, suites, recipes, targets")
    }

case "run":
    guard args.count > 1 else { fail("run needs a scenario id — try `chaos list scenarios`") }
    guard let scenario = resolveScenario(args[1]) else { fail("unknown scenario '\(args[1])'") }

    let seedOverride = value("--seed").flatMap(UInt64.init)
    let durationOverride = value("--duration").flatMap(TimeInterval.init)
    let targetName = value("--target")

    if !flag("--yes") {
        say("About to run: \(scenario.name)")
        say("  faults:    \(scenario.bindings.map(\.name).joined(separator: ", "))")
        say("  severity:  \(scenario.bindings.map { $0.severity }.max()?.title ?? "Low")")
        if !json && !quiet { print("Proceed? [y/N]: ", terminator: "") }
        guard let line = readLine(), line.lowercased().hasPrefix("y") else { exit(2) }
    }

    let record = runScenario(scenario, seedOverride: seedOverride, durationOverride: durationOverride,
                             targetName: targetName, confirmed: true)
    if let record {
        if json {
            let s = record.assertionSummary
            let payload: [String: Any] = [
                "status": record.outcome.rawValue,
                "passedAssertions": s.passed,
                "failedAssertions": s.failed,
                "inconclusiveAssertions": s.other,
                "seed": String(record.config.seed),
                "experimentID": record.id.uuidString,
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
        } else {
            say("outcome: \(record.outcome.title)")
        }
        exit(outcomeExitCode(record.outcome))
    }
    fail("experiment did not complete")

case "replay":
    guard args.count > 1 else { fail("replay needs a record id") }
    let idPrefix = args[1]
    guard let record = PersistenceStore.shared.loadRecords().first(where: { $0.id.uuidString.hasPrefix(idPrefix) }) else {
        fail("no record matching '\(idPrefix)'")
    }
    let plan = ReplayPlan(config: record.config)
    say(ReplayPlan.replayNotice)
    let replayRecord = runScenario(
        Scenario(id: "replay", name: record.config.name, category: "Replay",
                 summary: "Replay of \(record.config.name)", symbolName: "arrow.uturn.backward.circle",
                 bindings: plan.bindings),
        seedOverride: plan.seed, durationOverride: nil, targetName: nil, confirmed: true
    )
    if let replayRecord {
        if json {
            let s = replayRecord.assertionSummary
            let payload: [String: Any] = [
                "status": replayRecord.outcome.rawValue,
                "passedAssertions": s.passed,
                "failedAssertions": s.failed,
                "seed": String(replayRecord.config.seed),
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
        }
        exit(outcomeExitCode(replayRecord.outcome))
    }
    fail("replay did not complete")

case "suite":
    guard args.count > 1 else { fail("suite needs a suite id — `chaos list suites`") }
    let prefix = args[1]
    guard let suite = PersistenceStore.shared.loadSuites().first(where: { $0.id.uuidString.hasPrefix(prefix) }) else {
        fail("no suite matching '\(prefix)'")
    }
    guard let run = SuiteRunner.shared.start(suite: suite) else {
        fail("a suite is already running")
    }
    say("suite '\(suite.name)' started — \(suite.scenarioIDs.count) experiments")
    while SuiteRunner.shared.isRunning {
        Thread.sleep(forTimeInterval: 1.0)
    }
    let final = PersistenceStore.shared.loadSuiteRuns().first(where: { $0.id == run.id }) ?? run
    if json {
        let payload: [String: Any] = [
            "suite": suite.name,
            "completed": final.completedCount,
            "passed": final.passedCount,
            "failed": final.failedCount,
            "pending": final.pendingCount,
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        print(String(data: data, encoding: .utf8)!)
    } else {
        say("completed \(final.completedCount)/\(final.entries.count) — passed \(final.passedCount), failed \(final.failedCount)")
    }
    exit(final.failedCount > 0 ? 1 : 0)

case "status":
    if let rec = ExperimentEngine.shared.liveSnapshot {
        if json {
            let payload: [String: Any] = [
                "state": "running", "name": rec.config.name,
                "seed": String(rec.config.seed), "events": rec.events.count,
                "outcome": rec.outcome.rawValue,
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("state:   running\nname:    \(rec.config.name)\nseed:    \(rec.config.seed)\nevents:  \(rec.events.count)")
        }
    } else {
        print(json ? "{\"state\":\"idle\"}" : "idle — no experiment running")
    }

case "stop":
    guard ExperimentEngine.shared.liveSnapshot != nil else { fail("no experiment running") }
    ExperimentEngine.shared.stop(reason: .userStop)
    say("stop requested — restoration in progress")

case "restore":
    // CLI is headless: never trigger a GUI authorization prompt mid-script.
    // If privileges are missing, report honestly instead of pretending.
    let result = FaultCleanup.restoreEverything(allowPrompt: false)
    if json {
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
        print(String(data: data, encoding: .utf8)!)
    } else {
        for (k, ok) in result {
            print("\(k): \(ok ? "verified restored" : "UNABLE TO VERIFY — authorize via the Chaos app, then retry")")
        }
    }
    exit(result.values.allSatisfy(\.self) ? 0 : 1)

case "records":
    let records = PersistenceStore.shared.loadRecords()
    guard !records.isEmpty else { print("no experiments recorded yet"); exit(0) }
    for r in records.prefix(30) {
        let date = r.startedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
        print("\(r.id.uuidString.prefix(8))  \(r.outcome.title.padding(toLength: 12, withPad: " ", startingAt: 0)) \(date)  \(r.config.name)")
    }

case "report":
    guard let idPrefix = args.count > 1 ? args[1] : nil else { fail("report needs a record id") }
    guard let record = PersistenceStore.shared.loadRecords().first(where: { $0.id.uuidString.hasPrefix(idPrefix) }) else {
        fail("no record matching '\(idPrefix)'")
    }
    let format = value("--format") ?? "md"
    let content: Data
    switch format {
    case "json": content = (try? ReportGenerator.jsonData(for: record)) ?? Data("{}".utf8)
    case "csv": content = Data(ReportGenerator.csv(for: record).utf8)
    default: content = Data(ReportGenerator.markdown(for: record).utf8)
    }
    if let out = value("--out") {
        try? content.write(to: URL(fileURLWithPath: out))
        say("report written to \(out)")
    } else {
        FileHandle.standardOutput.write(content)
    }

default:
    fail("unknown command '\(command)' — run `chaos` for help")
}

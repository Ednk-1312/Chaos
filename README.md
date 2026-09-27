# Chaos

**Break your app before your users do.**

Chaos is a native macOS resilience-testing tool for deliberately introducing
controlled failures into development environments and verifying how applications
respond: network degradation, CPU and memory pressure, disk-near-full
simulation, filesystem and permission failures, process kills, dependency
outages, and seeded random chaos — all bounded, logged, reversible, and
observable.

> Your app works perfectly. That's the problem.

> **Status: developer preview.** The engine, safety model, and core workflows are
> real and tested; the UI has not been broadly validated across machines. Expect
> rough edges. Report anything you hit — see
> [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md).

## Why Chaos exists

Applications are normally tested under ideal conditions. Real systems get:
network failures, latency and packet loss, DNS outages, CPU and memory pressure,
process termination, dependency downtime, near-full disks, denied file access,
and more. Chaos lets you deliberately reproduce those conditions on demand,
observe what your app actually does, and verify that restoration returns the
machine to a verified-clean state — with evidence, not assumptions.

## Requirements

- macOS 14.0 or later (Apple Silicon or Intel for source builds; **release
  artifacts are Apple Silicon (arm64) only**)
- Xcode with the macOS 14+ SDK (built and tested with Xcode 27 / Swift 6.4; the
  project declares `SWIFT_VERSION = 6.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0`)
- No Apple Developer account required: the app is signed ad-hoc ("Signing: Automatic,
  Development Team: none") and all privileged operations use on-demand OS
  authorization rather than an embedded helper

## Install a release (no Xcode needed)

Grab `Chaos-v<version>.pkg` from [GitHub Releases](https://github.com/Ednk-1312/Chaos/releases) and run it.

What it does:

- installs **Chaos.app** into `/Applications` (standard Installer prompt;
  upgrading over an existing install replaces the app and leaves your data in
  `~/Library/Application Support/Chaos` untouched)
- adds a symlink `/usr/local/bin/chaos` → the CLI inside the app bundle, so
  `chaos` works from Terminal without the app running. The installer never
  overwrites an existing file there that isn't a Chaos symlink.

Signing status, honestly: preview packages and zips are **ad-hoc signed and not
notarized**, so Gatekeeper will warn on first launch of a *downloaded* copy
(right-click → Open, or remove the quarantine attribute). Building from source
has no such prompt. Developer ID signing + notarization is wired in the release
pipeline and activates automatically once signing credentials are configured
(see `RELEASING.md`).

To uninstall: drag `/Applications/Chaos.app` to the Trash and
`rm /usr/local/bin/chaos` (only if it's the Chaos symlink). User data in
`~/Library/Application Support/Chaos` is never removed by the installer.

## Open in Xcode

```bash
open Chaos.xcodeproj
```

Targets:

| Target | Product | What it is |
|---|---|---|
| `Chaos` | `Chaos.app` | The native SwiftUI app |
| `chaos` | `chaos` CLI | Same engine, headless — for scripts, CI, Makefiles |
| `chaos-stress` | worker binary | Purpose-built CPU/memory load generator |
| `ChaosKitTests` | test bundle | Engine, model, safety, and persistence tests |

Press **⌘R** to run the app. Select the `Chaos` scheme and run tests with **⌘U**.

## Build from the CLI

```bash
# 1. Build the engine, CLI, and stress worker (Swift Package Manager)
cd ChaosKit && swift build && cd ..

# 2. Build the app — a build phase embeds the CLI and stress worker
xcodebuild -project Chaos.xcodeproj -target Chaos -configuration Debug build

# Product: build/Debug/Chaos.app with
#   Contents/MacOS/Chaos           the app
#   Contents/MacOS/chaos-stress    CPU/memory load worker
#   Contents/Helpers/chaos         the CLI

# 3. Ad-hoc sign (no Apple Developer account needed)
codesign --force --sign - build/Debug/Chaos.app

# 4. Run the test suite
cd ChaosKit && swift test
```

All steps verified on a clean checkout.

**Development vs release CLI installs, clearly separated:**

- *Development*: `Tools/install-cli.sh` builds the CLI in release mode and
  installs it into your locally built app bundle — no sudo, no system changes.
- *Release*: the `.pkg` postinstall adds `/usr/local/bin/chaos` (see above).

Maintainer release tooling (`.pkg` + `.zip` + checksums + manifest, optional
Developer ID signing/notarization) lives in `Tools/Release/` — see
[`RELEASING.md`](RELEASING.md).

## Platform workflow

The product loop: **choose an app → define failure conditions → run experiment → observe behavior → evaluate assertions → diagnose failure → restore system → replay → verify fix.**

Key concepts:

- **Experiments** — full lifecycle states (Draft → Running → Restoring → Completed/Failed/Interrupted/Restoration Required), assertion outcomes with human-readable evidence for every result, and a persisted record with host snapshot, seed, and restoration ledger.
- **Replay** — every experiment has a reproducibility identity (plan + seed + timings). `chaos replay <id>` or the Replay button re-runs it exactly. Replay uses the same experiment plan and seed; system scheduling may introduce timing differences.
- **Bug Recipes** — save a failing experiment as a reusable recipe (target, fault sequence, assertions), then run/replay/delete it from the Recipes tab or the CLI.
- **Chaos Suites** — bundle scenarios into a release suite. Experiments run sequentially, each fully restored before the next; live progress, rerun-failed, stop, JSON summaries.
- **Random Chaos** — seeded random fault plans within chosen categories and severity ceilings; the generated plan is shown before launch and is replayable by seed.
- **Conditional Chaos** — WHEN-THEN rules with genuinely observable triggers only (process exit, process appears, memory threshold, endpoint down, another fault activated). Each rule fires at most once per experiment.
- **Restore Center** — verified restoration per subsystem. pf reset is verified by checking the anchor is actually empty; worker cleanup is verified against the process table. “UNABLE TO VERIFY” is shown when privileges are missing — never a fake success.

## The one-click flow

1. **Choose an app** (Targets tab, or a running process)
2. **Choose what goes wrong** (Scenarios tab)
3. **CREATE CHAOS**
4. Watch the live timeline, then stop or let it restore itself
5. Export the report (Markdown / JSON / CSV / PDF)

## CLI

```bash
.build/out/Products/Debug/chaos list faults|scenarios|suites|recipes|targets
.build/out/Products/Debug/chaos run terrible-wifi --duration 120 --yes --seed 842913 --json
.build/out/Products/Debug/chaos replay <record-id> --json
.build/out/Products/Debug/chaos suite <suite-id> --json
.build/out/Products/Debug/chaos status --json
.build/out/Products/Debug/chaos stop
.build/out/Products/Debug/chaos restore
.build/out/Products/Debug/chaos records
.build/out/Products/Debug/chaos report <id> --format md|json|csv [--out PATH]
```

`--yes` skips the interactive safety confirmation (for CI). `--json` emits
machine-readable output; `run` exits 0 on pass, 1 on failure, 3 on
warning/inconclusive, 4 on stop — usable directly in CI gates.

The CLI runs headless: privileged fault activation fails fast with an honest
message instead of opening a GUI authorization dialog mid-script. Run once
inside the app to authorize pf, or run the CLI as root in CI containers.

## Architecture

```
ChaosKit/                    # The engine — no UI, shared by app + CLI
  Models/                    #   Fault catalog, experiment/scenario/record models
  Engine/                    #   ExperimentEngine, restoration ledger, checkpoints,
                             #   random-chaos planner, monitoring, persistence, reports
  Faults/                    #   Network (pf/dummynet), resources (stress workers),
                             #   storage/filesystem, process/dependency, environment
Chaos/                       # SwiftUI app: dashboard, live view, builder, monitors
Tools/                       # Icon generator, install scripts
```

Every fault is a `FaultRunner` registered by `FaultID`; scenarios compose
bindings; experiments compose both. Adding a fault = one descriptor + one runner.

## Safety model

- **Least privilege** — the app runs unprivileged; network faults trigger a
  one-time OS authorization prompt. No persistent privileged helpers, ever.
- **Hard ceilings** — stress workers always leave ≥2 GB or 25% of RAM free;
  the real disk is never filled (sparse test volumes only).
- **Explicit restoration** — every subsystem reports restored/failed in the
  Restore Center; nothing is assumed.
- **Crash-safe** — a checkpoint tracks active faults and worker PIDs; the next
  launch kills orphaned workers and flushes network anchors.
- **Emergency stop** — ⌘. anywhere: cancel scheduled faults, kill workers,
  restore everything, verify, report what couldn't be restored.

## Honest simulation: REAL vs SIMULATED vs GUIDED vs PRIVILEGED

macOS does not permit apps to unplug hardware, revoke TCC privacy grants, or
change the system clock — so Chaos never pretends it can. The fault library
(49 faults) is explicitly classified, and the UI, safety review, reports, and
CLI all preserve the distinction:

| Class | Meaning | Examples |
|---|---|---|
| **REAL** | Genuinely executed against the OS | pf/dummynet network faults, CPU & memory pressure via a purpose-built worker, real sparse-volume disk fill, real file/permission manipulation, process kill/pause, dependency port blocking, real unmountable scratch volumes |
| **PRIVILEGED** | Real but needs one-time OS authorization | Offline mode, latency, packet loss, bandwidth cap, DNS failure (pf + dummynet). The app prompts once; the CLI fails fast with an honest message instead of opening a GUI dialog |
| **SIMULATED** | Faithful stand-in where macOS forbids the real thing | Clock skew/DST/rollover (no documented API to change the system clock), privacy-grant prompts (TCC cannot be scripted), low battery, device unplug |
| **GUIDED** | A checklist drill plus any real pieces that are possible | Device disconnect walkthrough, manual custom conditions |

Run `chaos list faults` to see the class of every fault (`runnable`/`guided`,
`[SIMULATED]` marks). The full catalog with per-fault capability notes lives in
[`ChaosKit/Sources/ChaosKit/Models/Fault.swift`](ChaosKit/Sources/ChaosKit/Models/Fault.swift)
— each descriptor documents why privilege is needed, what it affects, and how
restoration is verified.

Your failure tests stay on your Mac. Nothing is uploaded.

## Current limitations

- macOS constrains some failures by design; those are labeled SIMULATED/GUIDED
  as above, and the UI never claims otherwise.
- Network faults affect all processes on the machine — per-app network isolation
  is not possible with documented APIs (each descriptor says so).
- The app is developed and verified on one Apple Silicon Mac (macOS 26.7).
  Interactive UI behavior has not been validated across a hardware matrix.
- No notarized/distributed binary yet: you build from source, ad-hoc signed.

## Testing

```bash
cd ChaosKit && swift test
```

75 XCTest cases (+ a swift-testing suite) cover the engine, models, safety
counters, persistence round-trips, replay identity, recipes, scorecard
aggregation, and the privilege model. See `CONTRIBUTING.md` before adding tests
that touch real system state.

## Security

Chaos deliberately manipulates system conditions, so its security surface is
unusual. Please read [SECURITY.md](SECURITY.md) before reporting.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Safety-relevant changes get extra
scrutiny — please read the safety expectations there first.

## License

Chaos is released under the [MIT License](LICENSE).


# Chaos — Developer Preview 1

**First public release of Chaos.** This is a developer preview, not a
production-ready product: the engine, safety model, and core workflows are real
and tested, but the tool has been verified primarily on a single Apple Silicon
Mac and the UI has not been broadly validated across machines.

## What Chaos is

A native macOS resilience-testing tool for deliberately introducing controlled
failures into development environments and verifying how applications respond —
network degradation, resource pressure, process kills, dependency outages,
filesystem failures, and seeded random chaos, all bounded, logged, reversible,
and observable.

## What works

- The full experiment loop: choose application → configure experiment → review
  safety → run → observe → restore → inspect evidence → save recipe → replay →
  compare → add to suite
- 49-fault library with honest REAL / SIMULATED / GUIDED / PRIVILEGED
  classification (35 real, 14 simulated/guided)
- Assertions with human-readable evidence for every outcome
- Verified restoration (Restore Center), crash-safe checkpoint + boot sweep,
  emergency stop
- Bug recipes, deterministic seeds, exact replay, experiment comparison
- Chaos suites with verified restoration between experiments; rerun-failed
- Random chaos plans (seeded, previewed) and conditional WHEN-THEN rules
- CLI (`chaos`) sharing the engine, JSON output, CI-friendly exit codes
- Report export (Markdown / JSON / CSV / PDF)

## Who should try it

Developers building macOS apps or services who want to see how their software
behaves when the network dies mid-request, memory pressure spikes, or a
dependency goes dark — and who want restoration they can verify, not hope for.

## How to build it

```bash
xcodebuild -project Chaos.xcodeproj -target Chaos -configuration Debug build
cd ChaosKit && swift test
```

Requires macOS 14+ and Xcode with the macOS 14 SDK. No Apple Developer account
required. See the README for the full walkthrough and first experiment.

## Known limitations

- Some failures macOS won't let apps cause are SIMULATED or delivered as GUIDED
  drills (system clock, battery, privacy grants, device unplug) — always labeled
- Network faults affect the whole machine; per-app network isolation isn't
  possible with documented APIs
- Ad-hoc signed, build-from-source; no notarized download yet
- Verified on one machine configuration; expect rough edges

## Safety considerations

Chaos performs operations that affect system behavior. Privileged operations
(pf/dummynet) require explicit one-time OS authorization, every fault has
ceilings and a restoration path, restoration is verified before being reported
as restored, and a checkpoint protects against crashes leaving state behind.
Read the Safety model section of the README before your first experiment.

## Reporting bugs

Use the GitHub issue templates. Security issues: see SECURITY.md and report
privately.

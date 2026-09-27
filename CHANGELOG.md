# Changelog

All notable changes to Chaos are documented here.

## [Unreleased] — Developer Preview

First public preview of Chaos: a native macOS resilience-testing tool for
deliberately introducing controlled failures and verifying how applications
respond.

### Product

- Native SwiftUI macOS app (macOS 14+) with dashboard, sidebar navigation, and
  a ⌘K command palette
- Application profiles: per-app recommended tests, resilience history, and
  honest recommendations (dependency-fault tests are only recommended when a
  dependency is actually declared)
- Targets flow: pick an app, choose from running processes, or drag-and-drop;
  primary target and recents persist
- Optional menu-bar item (off by default) with run/stop/restore actions

### Experimentation

- Visual experiment builder: fault library → timeline → inspector, with a
  REVIEW CHAOS safety sheet before anything runs
- Pre-built scenario library (network, storage, memory, permissions, lifecycle,
  extreme) plus user-defined scenarios
- Assertions evaluated from observable system state, with human-readable
  evidence for every outcome (never bare pass/fail)
- Experiment records: full lifecycle states, host snapshot, seed, event stream,
  restoration ledger
- Deterministic seeds; exact replay of any past experiment (ReplayPlan =
  plan + seed + timings), with an honest notice about system-scheduling drift
- Failure inspection with replay comparison (same seed/side-by-side outcomes)
- Bug recipes: save a failing experiment as a reusable reproduction (faults,
  seed, targets, assertions); run/replay/duplicate from UI or CLI
- Chaos suites: sequential experiments with verified restoration between each,
  live progress, rerun-failed
- Random chaos: seeded random plans within category and severity ceilings,
  previewed before launch
- Conditional chaos: WHEN-THEN rules with genuinely observable triggers only,
  each firing at most once per experiment
- Resilience Scorecard: assertion outcomes aggregated per fault category across
  history, click-through to the underlying experiments

### Fault injection

- 49-fault catalog, each descriptor documenting capability, scope, privileges,
  and restoration: 35 real, 14 explicitly SIMULATED/GUIDED (clock, battery,
  privacy grants, device unplug — things macOS does not allow apps to do)
- Network faults use real pf anchor + dummynet pipes (same mechanism as
  Network Link Conditioner), one-time OS authorization, always flushed on stop
- CPU/memory pressure via a purpose-built `chaos-stress` worker with hard
  ceilings (never fills real RAM/disk; sparse test volumes only)
- Filesystem/permission faults create and manipulate Chaos-owned resources

### Observability

- Live monitor with per-fault active/restored status and unified event timeline
- System health (CPU, memory, disk, network) sampling
- Experiment history with search, outcome filters, compare
- Reports export: Markdown, JSON, CSV, PDF

### Restoration

- Restore Center with per-subsystem verified restoration ("Restored ✓ verified"
  only after actual verification; "UNABLE TO VERIFY" when privileges are
  missing — never a fake success)
- Crash-safe checkpoint: active faults and worker PIDs tracked; next launch
  kills orphaned workers and flushes network state (boot sweep)
- Emergency stop (⌘.) cancels scheduled faults, kills workers, restores, and
  reports anything that couldn't be restored

### CLI

- `chaos` CLI sharing the engine with the app: list/run/replay/suite/status/
  stop/restore/records/report; JSON output; documented exit codes
  (0 pass · 1 fail · 2 usage · 3 inconclusive · 4 stopped)
- Headless-safe: privileged operations fail fast with honest messages instead
  of opening GUI dialogs mid-script

### Testing

- 75 XCTest cases plus a swift-testing suite covering engine, models, safety
  counters, persistence round-trips, replay identity, recipes, and the
  scorecard aggregation

### UI

- SF Pro typography with tabular digits for numeric data; monospaced fonts
  reserved for identifiers
- Runtime-validated SF Symbol usage; uniform card layouts; accessible labels
  on key controls

### Notable reliability fixes during development

- Engine `Shell.run` pipe deadlock eliminated (large process listings could
  exceed the pipe buffer and stall fault liveness checks); suite runtime
  dropped from ~96 s to ~4.5 s as a result
- `[UUID: Value]` JSON encoding toolchain bug worked around for assertion
  results and evidence (string-keyed encoding with tolerant decoding)
- Legacy-record decoding kept backward compatible across model additions
  (recipe capture fields, experiment state, evidence, binding `enabled` flag)

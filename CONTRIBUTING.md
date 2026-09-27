# Contributing to Chaos

Thanks for helping build a better resilience-testing tool. Chaos deliberately
messes with real macOS subsystems, so this guide has a few non-negotiable
safety expectations on top of the usual ones.

## Prerequisites

- macOS 14+ and Xcode with the macOS 14+ SDK (tested with Xcode 27 / Swift 6.4)
- No Apple Developer account needed (ad-hoc signing)

## Getting started

```bash
git clone <repository-url>
cd Chaos
open Chaos.xcodeproj        # ⌘R to run the app
cd ChaosKit && swift test   # run the engine test suite
```

Command-line build:

```bash
xcodebuild -project Chaos.xcodeproj -target Chaos -configuration Debug build
```

## Project structure

```
ChaosKit/                    # The engine — no UI, shared by app + CLI
  Sources/ChaosKit/Models    #   Fault catalog, experiment/scenario/record models
  Sources/ChaosKit/Engine    #   ExperimentEngine, restoration ledger, checkpoints,
                             #   planner, monitoring, persistence, reports
  Sources/ChaosKit/Faults    #   Fault runners (network, resources, filesystem, …)
  Sources/chaos              #   The CLI
  Sources/chaos-stress       #   CPU/memory load worker
  Tests/ChaosKitTests        #   XCTest + swift-testing suites
Chaos/                       # SwiftUI app
Tools/                       # Icon generator, CLI install script
```

Adding a fault = one `FaultDescriptor` (honest `capabilityNote`, restoration
description, correct `simulated` flag) + one `FaultRunner` + tests.

## Coding expectations

- Match the existing style; keep `ChaosKit` UI-free.
- Every fault descriptor must tell the truth: what's real, what's simulated,
  what needs privilege, and how restoration is verified.
- Never replace a verification step with an optimistic success message. If
  restoration can't be verified, the UI must say "unable to verify".

## Test expectations

- New engine/behavior changes need tests. `swift test` must stay green.
- Persistence changes need a round-trip test (see `PersistenceAndSafetyTests`
  for the established pattern).

**Do not create tests that casually damage a real developer machine.** Tests
must not fill the actual boot volume, kill processes they don't own, or mutate
system network state. Use isolated `PersistenceStore` directories, mock
runners, the existing fixtures, or the engine's built-in ceilings. If a test
needs privileged system state, test the decision logic around it, not the
destructive act itself.

## Pull requests

Keep PRs focused. The template will ask you to confirm:

- tests added/updated where appropriate, and the suite passes
- safety implications considered (especially fault scope and restoration)
- privileged/system behavior considered
- documentation updated if behavior changed
- no secrets or personal data added

## Issue reporting

Use the bug or feature templates. For anything safety-related, also read
[SECURITY.md](SECURITY.md) — report privately, not in public issues.

## Safety expectations for contributors

- Least privilege: don't add anything requiring a persistent privileged helper.
- Bounded effects: every fault must have explicit ceilings and a restoration path.
- Honest classification: REAL / SIMULATED / GUIDED / PRIVILEGED labels are a
  product feature, not documentation decoration. Preserve them in UI, reports,
  and CLI output.

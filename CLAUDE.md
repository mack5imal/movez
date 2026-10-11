# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

movez is a macOS 14+ menu-bar agent (`LSUIElement`, unsandboxed, no network) that schedules
movement breaks through the working day and plays a routine generated from a 159-movement library.
Swift 5 language mode, SwiftUI + AppKit, no third-party dependencies. Needs `brew install xcodegen swiftlint`.

## Commands

```sh
make build          # xcodegen generate, then Debug build into build/DerivedData
make test           # full XCTest suite; filtered summary on stdout, full log in build/test.log
make lint           # swiftlint --strict (warnings fail)
make snapshots      # render every UI surface to build/snapshots/*.png, fails if any is missing
make hygiene        # overlay window-hygiene check; must launch via `open` (see README)
make panel-hygiene  # floating panels must never take focus; run straight from the binary
make run            # open the Debug app
```

Run a single test class or method (run `make gen` first if `project.yml` or the file list changed):

```sh
xcodebuild -project movez.xcodeproj -scheme movez -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  test -only-testing:movezTests/SchedulerCoreTests/testSomething
```

Don't pass `-quiet` to `xcodebuild test`: it hides the "Executed N tests" summary.

`project.yml` is the source of truth for the Xcode project. The generated `movez.xcodeproj` is
committed, so regenerate it (`make gen`, which `build`/`test` already do) after adding, moving or
removing files and commit the result. Bundled resource folders (Fonts, Chimes) are declared
`type: folder` so their structure survives.

Headless modes of the binary (`build/DerivedData/Build/Products/Debug/movez.app/Contents/MacOS/movez`):
`--smoke`, `--snapshot <surface|all|list> --out <dir>`, `--probe-signals`, `--overlay-hygiene`,
`--panel-hygiene` (parsed in `App/LaunchArguments.swift`).

## Sources of truth

Behaviour and visuals are specified by the root documents, in this precedence order:
`product-brief-v1.md`, `scheduler-research-v1.md`, `movement-library-v4.json` (bundled directly
from the repo root; never copy it or hard-code a movement), `design_handoff_movez_ui/`.
`docs/DECISIONS.md` is the numbered log of where the implementation departs from or resolves those
documents. Read it before changing behaviour, and add an entry when you make a new such decision.

## Architecture

**Pure scheduler, impure coordinator.** `Scheduler/` is a value-type state machine:
`Scheduler.handle(_ event:, now:) -> [SchedulerEffect]` is total, has no timers, and never calls
`Date()`. Everything time-dependent goes through the injected `Clock` (`SystemClock` supports a
debug time scale; tests use `ManualClock`). The event handlers are split across the
`Scheduler+*.swift` extensions (actions, idle, sleep, pause, hours, suppression).
`SchedulerSnapshot` is the whole persisted state; `StatePersistence` writes it so a relaunch resumes.

**`AppCoordinator`** (`App/`, `@MainActor`) is the only thing that connects the scheduler to the
world. It owns the clock and sends `.tick` every 2 s, feeds signal readings in as events, applies
each returned effect (building the routine for a break, writing history, persisting the snapshot)
and publishes the view state every surface binds to. The split is deliberate: the scheduler decides
*when*, and never knows what a movement is; the coordinator knows movements and history and never
decides when a break happens. The coordinator hands effects on to UI through `EffectSink`s (overlay,
panels, menu bar, chimes), so it never touches AppKit itself; tests use `RecordingEffectSink`.

**Signals** (`Signals/`): idle, microphone, screen capture, fullscreen and power, each behind a
protocol in `SignalSources.swift` with fakes in `FakeSignals.swift`. `SignalAggregator` polls them
and stops entirely while paused or off hours (`Scheduler.pollingRequired`). Screen-capture
detection is a heuristic driven by `Resources/capture-signatures.json`. Debug injections go through
`SignalOverrides`, which holds a value in front of the real source; a one-shot injection is undone
by the next poll.

**Routines** (`Library/` → `Routine/`): `LibraryLoader` decodes and validates the JSON into
`MovementLibrary`; `RoutineBuilder` and `MicroBreakBuilder` generate from it with `SeededRandom`,
using `RoutineContext` (what was served today, recency, equipment, settings); `RoutineValidator` checks
the shape of the result.

**UI** (`UI/`): `DesignSystem/` (tokens, Manrope text styles, controls) plus the surfaces
(full-break `Overlay/`, heads-up/micro/toast `Panels/`, `MenuBar/`, `Settings/`), each with a view
model that is unit-tested. `UI/Debug/SnapshotRenderer` + `SnapshotFixtures` render every surface
offscreen from frozen fixtures; that is how a UI change is reviewed. Add a new surface to the
fixtures so `make snapshots` covers it.

## Testing conventions

- Scheduler tests drive `SchedulerHarness` (`Tests/movezTests/SchedulerTestSupport.swift`): a
  `ManualClock` anchored at Monday 2026-09-07 09:00, 2 s ticks, always-on working hours unless a
  test passes `.standard`. Whole days replay in milliseconds, so prefer simulating time over
  shortcuts into state.
- Coordinator-level tests (`CoordinatorTestSupport.swift`) inject stores and a `RecordingEffectSink`; assert effect order with
  `order(of:)`, since persist and menu-refresh effects interleave everywhere.
- The app detects an XCTest host (`AppDelegate.isHostingTests`) and doesn't start the real
  coordinator. Tests must never read or write the user's real Application Support data or
  `UserDefaults`; pass explicit stores and a scratch `UserDefaults` suite.

## Conventions

- Everything that touches state or UI is `@MainActor`; strict concurrency is `targeted`.
- Comments explain *why*, in full sentences, matching the existing doc comments.
- Commit subjects use `feat:` / `fix:` / `docs:` prefixes, lower-case, describing behaviour.
- `.supergoal/` holds the original build run's roadmap and state; it's history, not something to edit.

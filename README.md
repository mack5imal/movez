# movez

A macOS menu-bar agent that schedules short movement breaks through the working day and
plays a generated routine from a 147-movement library.

## Prerequisites

- macOS 14 or later, Xcode 15 or later (open it once so the toolchain is licensed)
- `brew install xcodegen swiftlint`

## Build, test, lint

```sh
make build      # generate movez.xcodeproj and build Debug
make test       # run the XCTest suite
make lint       # swiftlint --strict
make snapshots  # render every UI surface to PNG
make run        # launch the built app
make app        # print the path of the built .app
make hygiene    # open the break overlay on every display and check its window hygiene
make assets     # re-fetch Manrope and regenerate the chimes
```

`make gen` alone regenerates `movez.xcodeproj` from `project.yml`. The generated project is
committed so the repo opens in Xcode without XcodeGen, but `project.yml` is the source of truth.

## Repo layout

```
project.yml                 XcodeGen spec (source of truth for the Xcode project)
Makefile                    build / test / lint / snapshot entry points
Sources/movez/App           app entry point, delegate, launch arguments
Sources/movez/UI            design system and the four UI surfaces
Sources/movez/Resources     Info.plist, Manrope, chimes
Tests/movezTests            XCTest suite
scripts/                    font fetch and chime synthesis
```

The Markdown and JSON documents at the repository root — `product-brief-v1.md`,
`scheduler-research-v1.md`, `movement-library-v4.md`, `movement-library-v4.json` and the
`design_handoff_movez_ui/` folder — are the source of truth for behaviour and visual design.
`movement-library-v4.json` is bundled into the app directly from the repository root; there is
no second copy to keep in sync.

## Notes

- The app runs as an `LSUIElement` agent: it has a menu-bar item and no Dock icon.
- App Sandbox is **off**. movez inspects the frontmost window and the running process list to
  tell whether you are presenting or screen-sharing, and reads microphone activity state, all of
  which the sandbox blocks. It makes no network calls and writes only to its own Application
  Support directory.
- **Screen-capture detection is a heuristic.** macOS has no public API that reports whether the
  screen is being recorded or shared, so movez watches for the tools people actually use
  (`Sources/movez/Resources/capture-signatures.json`). It is deliberately conservative: a false
  positive silently postpones a break, which is worse than missing one share. Tools that sit in
  the menu bar all day — Loom, CleanShot X, Kap — are listed but disabled, because their merely
  running says nothing about whether a recording is live. Zoom and Teams run all day too, but
  both spawn a share helper that exists only while a share is live, so they are gated on that.
  Add your own signatures to that file if you use something else.
- **Focus.** There is no supported way to read the current Focus, so movez ships a Focus Filter
  instead: System Settings → Focus → *your Focus* → Focus Filters → Add Filter → movez. Turn
  "Pause breaks" on and movez waits until that Focus ends.
- `movez --probe-signals` prints one line per monitor for five seconds, which is how to check the
  adapters on a new machine. `movez --smoke` is the build's readiness check.
- **Run `--overlay-hygiene` through `open`, not the raw binary** (`make hygiene` does). macOS 14
  grants activation rights through Launch Services; a binary exec'd from a shell never becomes the
  active app, so its overlay can never take keyboard focus and the check reports `key=false` even
  though the shipped app is fine.
- Manrope is bundled under the SIL Open Font License 1.1 (`Sources/movez/Resources/Fonts/OFL.txt`).
- The chimes are synthesised locally by `scripts/gen_chimes.py`; no audio is downloaded.

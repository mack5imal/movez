# movez

A macOS menu-bar agent that schedules short movement breaks through the working day and
plays a generated routine from a 174-movement library.

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
make panel-hygiene  # show each floating panel and check it never takes focus
make assets     # re-fetch Manrope and regenerate the chimes
```

`make gen` alone regenerates `movez.xcodeproj` from `project.yml`. The generated project is
committed so the repo opens in Xcode without XcodeGen, but `project.yml` is the source of truth.

## Versions

Settings ends with a line like `movez 0.5.0 (38) · library v4.2 · 174 movements`. Each part is read
from what is installed, so nothing else needs editing when one of them moves:

- **App version** (`0.5.0`): `MARKETING_VERSION` in `project.yml`, changed with
  `make version V=0.6.0`. A minor bump for a release with features, a patch bump for one with only
  fixes; 1.0 is reserved for when the app is called done.
- **Build number** (`38`): stamped on every build with the commit count (`git rev-list --count
  HEAD`), so it never needs bumping.
- **Library version** (`v4.2`): the `version` field of `movement-library-v4.json`, with the same
  number in the title of `movement-library-v4.md` (a test holds them together). The filename keeps
  only the major version, so a minor library revision touches the two library files and nothing
  else.

## Install

`make run` launches the app out of the build directory, which is right for development and wrong
for daily use: the path is a build artifact, and a login item pointing into it breaks at the next
`make clean`. To actually live with movez, install a Release build and run that one:

```sh
xcodebuild -project movez.xcodeproj -scheme movez -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
ditto build/DerivedData/Build/Products/Release/movez.app /Applications/movez.app
open /Applications/movez.app
```

Then turn on Launch at Login in Settings. Re-run those three lines to update the installed copy;
the login item follows the path, so it keeps working.

## Repo layout

```
project.yml                 XcodeGen spec (source of truth for the Xcode project)
Makefile                    build / test / lint / snapshot entry points
Sources/movez/App           app entry point, delegate, coordinator, launch arguments
Sources/movez/Library       the movement library, decoded and validated
Sources/movez/Routine       routine and micro-break generation
Sources/movez/Scheduler     the sitting-to-break state machine (pure, clock-injected)
Sources/movez/Signals       idle, microphone, screen capture, fullscreen, power
Sources/movez/UI            design system and the five UI surfaces
Sources/movez/Resources     Info.plist, Manrope, chimes
Tests/movezTests            XCTest suite
scripts/                    font fetch and chime synthesis
```

The Markdown and JSON documents at the repository root — `product-brief-v1.md`,
`scheduler-research-v1.md`, `movement-library-v4.md`, `movement-library-v4.json` and the
`design_handoff_movez_ui/` folder — are the source of truth for behaviour and visual design.
`movement-library-v4.json` is bundled into the app directly from the repository root; there is
no second copy to keep in sync.

## The surfaces

`make snapshots` renders every one of them offscreen, at 2×, from frozen fixtures. That is how a
screen is reviewed without waiting an hour for a break to come round.

| Surface | What it is |
|---|---|
| `gallery` | Every colour, type style and control in the design system on one sheet |
| `overlay-full`, `overlay-collapsed`, `overlay-side`, `overlay-end`, `overlay-other-display` | The full break: a movement running, an instruction the user has collapsed, a per-side movement, the end card, and what the other displays show |
| `headsup`, `headsup-deferred` | The minute before a break, and the variant for a break that waited for a call |
| `micro-countin`, `micro-running` | The micro-break's thirty-second count-in and its minute |
| `toast` | "Away 7 min · counted as your break", with the reversal |
| `menu-sitting`, `menu-paused`, `menu-offhours`, `menu-icon` | The dropdown in each mode, and the menu-bar glyph at five moments |
| `settings`, `settings-hours`, `settings-library`, `settings-exceptions`, `settings-custom` | The settings window and its three sheets, plus the custom preset |
| `debug` | The settings window with the debug disclosure open |

## Known limitations

- **Screen-capture detection is a heuristic** — see the note below. It will miss a tool that is
  not in `capture-signatures.json`.
- **Fullscreen detection is a guess about intent.** A maximised editor looks exactly like a
  presentation, which is what the per-app exceptions list in Settings is for.
- **Launch at login needs the app to live somewhere permanent.** `SMAppService` records the
  bundle's path, so an app registered out of `build/DerivedData` stops launching the moment
  `make clean` removes it. Install it (see **Install** above) before turning the toggle on.
  Registration itself does not need a Developer ID: on macOS 15.6 an ad-hoc signature with no
  team identifier registers fine, and the login item survives a rebuild that changes the code
  hash. Should macOS refuse anyway, movez shows the refusal under the toggle rather than letting
  it silently spring back.
- **Working hours are one window a day.** A split shift has to be handled by pausing.
- **The break overlay covers every display but the menu bar.** That is deliberate: a break must
  never trap the user.
- **The app is unsandboxed**, for the reasons in the notes below.

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
- `movez --panel-hygiene` shows each floating panel for a second and fails if any of them moves
  the frontmost app, activates movez, or lands off its specified inset. Unlike the overlay check
  it is run straight from the binary, because not activating is the whole point.
- Idle CPU sits at roughly 0.5% while movez is counting down, and at nothing at all while it is
  paused or off hours: the signal monitors stop entirely rather than polling into a void.
- Manrope is bundled under the SIL Open Font License 1.1 (`Sources/movez/Resources/Fonts/OFL.txt`).
- The chimes are synthesised locally by `scripts/gen_chimes.py`; no audio is downloaded.

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
- Manrope is bundled under the SIL Open Font License 1.1 (`Sources/movez/Resources/Fonts/OFL.txt`).
- The chimes are synthesised locally by `scripts/gen_chimes.py`; no audio is downloaded.

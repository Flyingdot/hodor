# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Hodor is a macOS 14+ menu bar app (SwiftUI `MenuBarExtra`, SwiftPM only, no Xcode project, no dependencies) that
forwards fixed local URLs to dev servers on remote hosts via `ssh -N -L`. The directory is still called `tunneler`.
It's a personal tool, so keep it simple. Design decisions and behaviour details: @docs/DEVELOPMENT.md

## Commands

- `swift build` builds the debug binary. `swift test` runs the tests.
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest. Filter by suite or test:
  `swift test --filter ProjectStoreTests/defaultsToWinterfell`.
- `scripts/bundle.sh` builds `build/Hodor.app` (release, ad-hoc signed). `--install` copies it to
  `~/Applications` but exits 1 while Hodor is running, so quit it first (`pkill -x Hodor`). Then run it with
  `open ~/Applications/Hodor.app`. The bare `swift run` binary skips Info.plist (`LSUIElement`).
- Formatting: `swift format -i -r Sources Tests` (config in `.swift-format`). A PostToolUse hook formats each edited
  `.swift` file and runs `swift build`, so don't revert formatter changes. Write `///` doc comments in short sentences.

## Gotchas

- Targets: `HodorCore` (models, store, ssh), `HodorUI` (views), `Hodor` (app entry, `AppModel`). Only `ContentView`'s
  `init(store:tunnels:)` and `MenuBarIcon` are public. Tests use `@testable import`.
- The app icon lives in `assets/AppIcon.svg`. After changing it, run `scripts/make-icon.sh` (needs Chrome) and commit
  the regenerated `assets/AppIcon.icns`. The menu bar glyphs and the header mark are drawn in code in
  `HodorUI/Brand.swift`, along with the brand colors.
- Every ssh call uses `-o BatchMode=yes`. Hosts must work with key auth from `~/.ssh/config`.
- Discovery runs `ss`/`/proc` on the remote, so remote hosts must be Linux. winterfell's login shell is fish,
  which is why the snippet is wrapped in `sh -c '…'`. The script must not contain single quotes (a test checks this).
- `ProjectStore` saves and re-syncs the tunnels on every `didSet` of `hosts`/`projects`. Build the new array and
  assign it once instead of mutating elements in a loop.
- Store tests must use the injected temp `fileURL`, never the real config at
  `~/Library/Application Support/Hodor/config.json`.
- `TunnelManagerTests` spawns a real `/usr/bin/ssh` to `hodor-test.invalid` on ports 14297–14299 and can take about 10 s.
- SIGTERM/SIGINT go through `NSApplication.terminate` → `stopAll()`, so `pkill Hodor` is safe. A crash leaves the
  ssh children running and holding their ports.
- Agents can't capture the screen. `HodorUITests` renders the views through `NSHostingView` (not `ImageRenderer`,
  which leaves out AppKit controls) into `.build/ui-snapshots/*.png`. Read those PNGs to check UI changes. Tests
  pass fixture discovery and a stub to `ContentView`'s internal init, so they never run ssh.
- Live end-to-end checks against `winterfell` (install, restart Hodor, real tunnels) are allowed without asking.

## Workflow

- Commit straight to `main`. Use Conventional Commits with the scopes `core` and `ui`, e.g.
  `feat(core): store an ssh host per project`.
- After notable changes (new behaviour, integration results), append to the Log in `docs/DEVELOPMENT.md` and keep
  "Behaviour details" / "Known limitations" current. Skip the log for small fixes.

# Hodor – development notes

Menu bar app that forwards fixed local URLs (e.g. `https://localhost:4200`) to dev servers
running on `winterfell`, so switching between worktrees is one click instead of a new
`ssh -N -L 4200:localhost:4201 winterfell`.

## Requirements (v1)

- A project has a name and a URL. The local port comes from the URL.
- Per project, pick one dev server running on winterfell. Show every listener, no filtering.
- Several projects can be active at the same time.
- One URL per project.
- Personal tool: keep it simple.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| UI | SwiftUI `MenuBarExtra` (`.window` style), macOS 14+ | Native, no dependencies |
| Build | Swift package + `scripts/bundle.sh` → `build/Hodor.app` | No Xcode project to maintain |
| Tunnels | One `ssh -N -L <local>:localhost:<remote> <host>` child process per active project | Same thing as the manual workflow, reuses `~/.ssh/config` and the agent |
| Discovery | `ssh <host> ss -Htlnp` + `/proc/<pid>/cwd` | Port plus worktree directory gives a useful label |
| Persistence | JSON at `~/Library/Application Support/Hodor/config.json` | Easy to inspect and hand-edit |
| Hosts | List of ssh hosts in the config (default `[winterfell]`), host stored per project next to `remotePort` | Projects on different machines at once; ssh config does the rest |

## Work packages

1. Skeleton: package, shared models (`Project`, `DevServer`, `TunnelStatus`), `ProjectStore`, these notes.
2. Core: `DevServerDiscovery` (remote command + parser) and `TunnelManager` (ssh processes,
   restart on exit), plus unit tests.
3. Bundling: `scripts/bundle.sh`, Info.plist with `LSUIElement` (no Dock icon).
4. UI: project list, add/edit/delete, server picker, active toggle, status, refresh, quit.
5. Integration: end-to-end check against winterfell, README, commits.

WP2 and WP3 ran as sub-agents in parallel with WP4.

## Log

- WP1 done: skeleton builds.
- WP3 done (sub-agent): `scripts/bundle.sh` builds, ad-hoc signs and installs (`--install`); app runs as `UIElement`.
- WP2 done (sub-agent): discovery + tunnel manager. The login shell on winterfell is fish, so the remote
  snippet runs under `sh -c '…'`. Verified against winterfell: discovery lists 22, 631, 3780 (node, cwd ~),
  tunnel 14280 → 3780 returns HTTP 200, auto-retry recovers after a port conflict clears.
- WP4 done: menu bar UI. Activating a project turns off other projects with the same local port.
- WP5 integration:
  - Seeded an active project, launched the bundled app: tunnel restored on startup, HTTP 200 through it.
  - Found and fixed: SIGTERM killed the app but left the ssh child running (port stays busy). SIGTERM/SIGINT
    now go through `NSApplication.terminate`, which stops all tunnels. Re-verified: no ssh left after `pkill`.
  - Render check: screen capture is not available from the agent session, so the real `ContentView` was
    rendered offscreen into a PNG via a temporary hook (not committed). Layout, status dot and server labels OK.
  - `swift test`: 14 tests in 4 suites pass.
- Renamed Tunneler → Hodor (he holds the door; he's from Winterfell). Bundle id `ch.meimail.hodor`, config in
  `~/Library/Application Support/Hodor`. Menu bar icon is a door, open while at least one tunnel runs.
- Multi-host support:
  - Config: `hosts: [String]` replaces `host`; each project has `host` + `remotePort`. Old configs migrate on
    load (the single host becomes the list, projects with a selected server get that host). The old key is
    dropped on the next save.
  - `TunnelManager.sync(projects:)` reads the host from each project; its spec already compared the host, so
    switching a project to another machine restarts the tunnel.
  - UI: all hosts are queried in parallel (task group). The picker labels servers `host · :port · process · dir`
    when there is more than one host. Hosts panel behind the server icon: per-host server count or ssh error,
    add/remove. Removing a host deselects and deactivates its projects.
  - Render check with a temporary offscreen hook (winterfell + unresolvable `castle-black`): the castle-black
    error shows, winterfell servers still load. `swift test`: 17 tests pass.
- UI render tests:
  - Views moved to a `HodorUI` library so tests can import them. `ContentView` has an internal init that takes
    fixture discovery results and a stub instead of ssh.
  - `HodorUITests` renders through `NSHostingView` in light mode into `.build/ui-snapshots/*.png`. `ImageRenderer`
    was not used because it leaves out AppKit-backed controls (toggle, picker, text field). The tests only check
    sizes; the PNGs are for looking at. This replaces the uncommitted offscreen hook.
  - Re-verified the installed app: tunnel 4200 restored on launch through winterfell, HTTP 200.
- Logo "Wedged Open" (picked from three proposals): a snow-capped door held ajar by a coral doorstop, with amber
  server light spilling through the gap.
  - App icon: `assets/AppIcon.svg` → `scripts/make-icon.sh` (headless Chrome, because CoreSVG drops the shadows,
    plus `iconutil`) → `assets/AppIcon.icns`, which is committed. `bundle.sh` copies it to `Contents/Resources`, and
    `CFBundleIconFile` points to it.
  - The menu bar uses template glyphs drawn in code (`MenuBarIcon`): a shut door when idle, and the door ajar with a
    wedge while a tunnel runs. They replace the SF Symbols.
  - UI colors come from the icon (`Brand.swift`). Night blue/frost is the tint. Amber marks a running tunnel (status
    dot with a glow, toggle). Coral is used for errors. The header shows a small version of the icon (`HodorMark`).
  - Render tests: added `brand` (mark plus glyphs) and `content-dark` (dark mode).
  - Live check: 24 tests pass. The installed app has the icon, and tunnel 4200 was restored on launch (ssh
    listening). There was no HTTP response because nothing was listening on 4200 on winterfell at the time.
- Hosts page: the server icon used to show the hosts list above the projects with no way back. Hosts is now
  its own page in the popup, with a back chevron in the header. Each host shows a status dot, its server count
  (or the ssh error) and how many projects use it. Removing a host that projects use takes a second click.
  `SSHConfig` reads the `Host` aliases from `~/.ssh/config` and suggests those not added yet (one click to add).
  An ssh error on the projects page opens the hosts page when clicked. Render test `content-hosts` added. The
  popup can't be opened from the agent session (AppleScript and synthetic clicks don't open it), so the agent
  checked the snapshots and the hosts page and refresh-on-open were confirmed by hand in the installed app.
- Server picker by worktree: winterfell listed ~40 listeners, most of them with the same long path. Discovery now
  also runs one `git rev-parse` per listener (worktree top level, common git dir, branch), and the process is the
  executable's name (`/proc/<pid>/exe`), because `comm` is cut at 15 characters (`Snapbean.TeamsM`). The picker
  only lists your own processes inside a git worktree, in one section per worktree (`repo › worktree (branch)`),
  each item `:port · subdirectory · process`. "Show all listeners" on the hosts page brings back the rest under
  "Other listeners". Live: 26 of 39 listeners on winterfell remain, in two worktree sections; tunnel 4200
  restored on launch, HTTP 200. The open menu can't be rendered offscreen (SwiftUI fills it only while it
  tracks), so the grouping is checked through `ProjectRow.groups` in a test.

## Behaviour details

- Discovery lists every TCP listener the tunnel can reach on the remote (`127.0.0.1`, `0.0.0.0`, `*`, `[::]`,
  `[::1]`). Sockets bound to other addresses (Tailscale IP, `127.0.0.53`, docker bridge) can't be reached via
  `localhost` and are left out. Process name and directory are only visible for your own processes.
- Process names come from the executable (`/proc/<pid>/exe`), falling back to `/proc/<pid>/comm`. .NET apps
  built with an apphost show their own name, not `dotnet`; the label drops it when the subdirectory ends with it.
  node is named after what it runs: a process title it set (`next-server`), else its script (`vite.js` → `vite`).
  Only for node does discovery send `argv[0]` and the first non-flag argument, nothing else from the command line.
- The picker hides listeners without a pid (other users, root) and those outside a git worktree, unless "Show all
  listeners" is on (`showAllServers` in the config). A selected server that is hidden still shows at the top.
- Worktree sections are titled `repo › worktree`, with the branch in brackets unless the folder is named after it
  (`/` written as `+`). The main checkout shows `repo (branch)`.
- Aspire: `dcp` (Aspire's orchestrator) listens on the ports declared in the AppHost and proxies them to the
  services, which get random ports (30000+) on every run. Pick the dcp port to survive restarts. All dcp ports
  share the AppHost directory, so the picker can't tell which service is behind which.
- Discovery runs on the first open (SwiftUI `.task`), on every later open (the popup window becomes key,
  `NSWindow.didBecomeKeyNotification`) and on the reload button. An open while a query is still running is skipped.
- A tunnel that dies (sleep, network change, port in use) shows the ssh error and is retried every 5 s while active.
- Changing the server of an active project restarts its tunnel immediately.

## Known limitations / ideas

- If the app crashes (not quit/killed), its ssh children survive and hold the ports until killed by hand.
- `running` means the ssh process is alive, not that the remote port answers.
- Host suggestions only read `~/.ssh/config` itself: `Include` files are not followed, and `Host` patterns
  (`*`, `?`, `!`) are skipped.
- Discovery needs Linux (`ss`, `/proc`); macOS hosts would need an `lsof` fallback.
- No launch-at-login yet (add the app to Login Items manually).

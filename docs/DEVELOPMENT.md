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
| Host | Defaults to `winterfell`, stored in the config | No need for a settings UI yet |

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

## Behaviour details

- Discovery lists every TCP listener the tunnel can reach on the remote (`127.0.0.1`, `0.0.0.0`, `*`, `[::]`,
  `[::1]`). Sockets bound to other addresses (Tailscale IP, `127.0.0.53`, docker bridge) can't be reached via
  `localhost` and are left out. Process name and directory are only visible for your own processes.
- Process names come from `/proc/<pid>/comm`, so node shows up as `node-MainThread`.
- Discovery runs when the menu content appears (SwiftUI `.task`; not verified whether that's on every open) and
  on the reload button.
- A tunnel that dies (sleep, network change, port in use) shows the ssh error and is retried every 5 s while active.
- Changing the server of an active project restarts its tunnel immediately.

## Known limitations / ideas

- If the app crashes (not quit/killed), its ssh children survive and hold the ports until killed by hand.
- `running` means the ssh process is alive, not that the remote port answers.
- Host can only be changed in `config.json` (restart the app afterwards).
- No launch-at-login yet (add the app to Login Items manually).

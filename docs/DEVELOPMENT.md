# Tunneler – development notes

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
| Build | Swift package + `scripts/bundle.sh` → `build/Tunneler.app` | No Xcode project to maintain |
| Tunnels | One `ssh -N -L <local>:localhost:<remote> <host>` child process per active project | Same thing as the manual workflow, reuses `~/.ssh/config` and the agent |
| Discovery | `ssh <host> ss -Htlnp` + `/proc/<pid>/cwd` | Port plus worktree directory gives a useful label |
| Persistence | JSON at `~/Library/Application Support/Tunneler/config.json` | Easy to inspect and hand-edit |
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

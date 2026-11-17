# Hodor

Hodor holds the door. A macOS menu bar app that forwards fixed local URLs such as `https://localhost:4200` to dev
servers running on machines in your network (by default `winterfell`) through `ssh -L`. It replaces typing
`ssh -N -L 4200:localhost:4201 winterfell` by hand every time you switch to another worktree.

## Requirements

- macOS 14 or later
- A Swift toolchain (Xcode or the Command Line Tools)
- Key-based ssh access to each host, configured in `~/.ssh/config` (`ssh <host>` must work without a prompt)
- Linux hosts for the dev server list (it uses `ss` and `/proc`); tunnels work to any host running sshd

## Build and run

```sh
scripts/bundle.sh            # builds build/Hodor.app
open build/Hodor.app
scripts/bundle.sh --install  # also copies the app to ~/Applications
```

The app has no Dock icon; it lives in the menu bar as a door, which is wedged open while at least one tunnel runs.

## Usage

1. Add a project with a name and a URL, e.g. `myapp` and `https://localhost:4200`. The local port comes from the URL.
2. Pick one of the dev servers. With more than one host, the list shows which machine each server runs on.
3. Toggle the project on. The URL now reaches that dev server.

Several projects can be active at the same time. To switch worktrees, pick another server for the
project; the tunnel restarts right away. Activating a project turns off any other project on the same
local port.

## Hosts

Click the server icon in the menu to add or remove hosts. A host is anything `ssh` accepts: an alias
from `~/.ssh/config` or a hostname. All hosts are queried in parallel; an unreachable one shows its
ssh error and doesn't block the others. Removing a host turns off the projects that used it.

## Agents

Coding agents can point projects at their own dev server, on this Mac or on any host, with `~/.hodor/hodor`:

```sh
~/.hodor/hodor projects                                # local URL, current target, status
~/.hodor/hodor use 4300 --worktree "$PWD" --port 4311 --wait   # serve this worktree's :4311 at localhost:4300
~/.hodor/hodor status 4300 --wait                      # wait until the URL answers
~/.hodor/hodor help
```

Hodor installs the script on this Mac and, over ssh, on every host. It talks to a socket in `~/.hodor` that is
only accessible to you. On the hosts, that socket is forwarded back to the Mac with `ssh -R`, so the
hosts can't reach the Mac in any other way. Agents can only change and toggle the projects you set up, never
add or delete projects or hosts. **Pin** a project (its `⋯` menu) to keep agents off it. A project changed by an
agent says so in its row until you pick a server yourself. Turn it all off with "Let agents steer Hodor" on the
hosts page.

To teach your agents when and how to use it, install the [`hodor` skill](skills/hodor/SKILL.md) on each machine
they run on (the Mac and every host). It uses the [skills CLI](https://github.com/vercel-labs/skills), which needs
Node.js 22.20 or later:

```sh
npx skills add Flyingdot/hodor --skill hodor -g -a claude-code -y   # into ~/.claude/skills; leave out -a to pick agents
npx skills update -g                                                # after the skill changes
```

The skill describes the workflow and leaves the exact syntax to `~/.hodor/hodor help`, so it rarely needs
updating. The CLI sends anonymous usage data unless `DISABLE_TELEMETRY=1` is set.

## Configuration

Hosts and projects are stored in `~/Library/Application Support/Hodor/config.json`. Without a config,
the host list starts with `winterfell`. Configs from before multi-host support (a single `host`) are
migrated when loaded.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

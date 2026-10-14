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

The app has no Dock icon; it lives in the menu bar as a door, which is open while at least one tunnel runs.

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

## Configuration

Hosts and projects are stored in `~/Library/Application Support/Hodor/config.json`. Without a config,
the host list starts with `winterfell`. Configs from before multi-host support (a single `host`) are
migrated when loaded.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

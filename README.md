# Tunneler

A macOS menu bar app that forwards fixed local URLs such as `https://localhost:4200` to dev
servers running on `winterfell` through `ssh -L`. It replaces typing
`ssh -N -L 4200:localhost:4201 winterfell` by hand every time you switch to another worktree.

## Requirements

- macOS 14 or later
- A Swift toolchain (Xcode or the Command Line Tools)
- Key-based ssh access to the host, configured in `~/.ssh/config`

## Build and run

```sh
scripts/bundle.sh            # builds build/Tunneler.app
open build/Tunneler.app
scripts/bundle.sh --install  # also copies the app to ~/Applications
```

The app has no Dock icon; it lives in the menu bar.

## Usage

1. Add a project with a name and a URL, e.g. `myapp` and `https://localhost:4200`. The local port comes from the URL.
2. Pick one of the dev servers running on the host.
3. Toggle the project on. The URL now reaches that dev server.

Several projects can be active at the same time. To switch worktrees, pick another server for the
project; the tunnel restarts right away. Activating a project turns off any other project on the same
local port.

## Configuration

Projects are stored in `~/Library/Application Support/Tunneler/config.json`. The host defaults
to `winterfell` and can be changed in that file.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

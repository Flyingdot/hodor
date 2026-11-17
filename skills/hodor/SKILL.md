---
name: hodor
description: Serve a dev server at its usual URL on the user's Mac (e.g. https://localhost:4300) through the Hodor menu bar app, then check that it answers. Use when you started a dev server in a worktree and the user, or you on the Mac, should open it at the project's fixed localhost URL, or when asked to switch which worktree a localhost URL shows.
---

# Hodor

Hodor is a menu bar app on the user's Mac. It forwards fixed local URLs, such as `https://localhost:4300`, to dev
servers on the user's machines over ssh. Each URL belongs to a project the user set up in Hodor. You can point a
project at another dev server and switch it on or off with `~/.hodor/hodor`, on the Mac and on every host Hodor
uses. You can't add projects or hosts.

Run `~/.hodor/hodor help` for the exact commands. It always matches the installed app.

## Show your dev server at the project's URL

1. `~/.hodor/hodor projects` lists the projects: local port, name, URL, current target and whether it's on. Pick
   the project whose URL the app is normally opened at. If none fits, tell the user and stop.
2. Start the dev server and note the port it listens on. It must listen on `localhost` (or all interfaces).
3. From the worktree, point the project at it and wait until the URL answers:

   ```sh
   ~/.hodor/hodor use 4300 --worktree "$PWD" --port 4311 --wait
   ```

   `4300` is the project (its local port or name). `--port` is your server's port. Always pass it: worktrees
   usually have other listeners too, such as the agent itself. Hodor finds the host by looking for that port in
   your worktree. Without a worktree, `--port N --host H` works too.
4. Tell the user which URL now shows which worktree. If the project was on and pointed somewhere else before,
   say what it pointed at (from step 1), since the user's open tab now shows your server.

Leave the project as it is when you're done, unless the user asks you to switch it back.

## Check a URL from the Mac

`~/.hodor/hodor status 4300 --wait` waits until the project runs and its URL answers (60 s by default, or pass
seconds). Then open the URL. Self-signed certificates are normal there.

## When it fails

- Exit 1: Hodor rejected the command. The message says why: the project is pinned (the user keeps agents off
  it), the name or port is ambiguous, or no server was found. Fix the arguments or tell the user. Don't
  retry with another project to get around a pin.
- Exit 2: Hodor can't be reached. It isn't running, agent control is off, or the link to this host is down. Tell
  the user.
- `~/.hodor/hodor` doesn't exist: Hodor hasn't connected to this machine yet. Tell the user.

Never start your own `ssh -L` tunnels or edit Hodor's config to get around these. Turning a project on turns off
other projects on the same local ports, so only switch projects you need.

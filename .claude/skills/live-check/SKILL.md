---
name: live-check
description: End-to-end check of Hodor. Runs the tests, installs the bundled app, restarts it and confirms active tunnels answer through their remote hosts. Use after changes to tunnels, discovery, the store or app lifecycle, or before saying a change works.
---

Run each step and stop at the first failure. Report what failed and include its output.

1. `swift test`. All tests must pass. `TunnelManagerTests` takes about 10 s because it uses real ssh.
2. Quit the running app: `pkill -x Hodor`. Wait until `pgrep -x Hodor` returns nothing. Then confirm that no
   tunnel processes survived: `pgrep -fl 'ssh -N .*-L'` should list nothing that Hodor started.
3. `scripts/bundle.sh --install`.
4. `open ~/Applications/Hodor.app`. Give it a few seconds to restore its tunnels.
5. Read `~/Library/Application Support/Hodor/config.json`. For each project with `isActive` set and both `host`
   and `remotePort` set:
   - `lsof -nP -iTCP:<localPort> -sTCP:LISTEN` shows an `ssh` listener.
   - `curl -sk -o /dev/null -w '%{http_code}' <project url>` returns an HTTP status, not `000`. A listener alone
     only shows that ssh is alive, not that the remote server answers.
   If no project is active, say so. Do not change the user's real config to make one active.
6. For a discovery change, also run the remote command against each configured host (default `winterfell`, see
   `DevServerDiscovery.remoteCommand`) and check that the parsed output matches what the menu shows.
7. For a UI change, look at the PNGs that step 1 wrote to `.build/ui-snapshots/` (from
   `Tests/HodorUITests/RenderTests.swift`). If the change adds a new state or view, add a render test for it first.

Finish with a short pass/fail list, one line per step. If the change is notable, append the results to the
Log in `docs/DEVELOPMENT.md`.

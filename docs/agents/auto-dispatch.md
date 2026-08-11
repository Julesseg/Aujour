# Auto-dispatch: unblocked issues → Paseo agent sessions

When a PR merges and closes an issue that was blocking other issues, the newly
unblocked issues get implemented automatically: a fresh Claude Code session is
spawned for each one via [Paseo](https://paseo.sh) on a self-hosted Mac runner.
Sessions run on the Mac's Claude subscription login (no API credits) and are
visible in the Paseo desktop/mobile apps.

## How it works

Two workflows split detection from execution:

1. **`unblock-dispatch.yml`** (GitHub-hosted, pure scripting) runs on every
   `issues: closed` event where the issue was closed as *completed*. It scans
   open `ready-for-agent` issues, parses each body's `## Blocked by` section
   (`- #N` bullets), and keeps issues whose blockers are now all closed. For
   each, it applies the `agent-dispatched` label (the idempotency guard) and
   fires `agent-implement.yml` with the issue number.
2. **`agent-implement.yml`** (self-hosted Mac runner) runs
   `paseo run --detach --worktree claude/issue-<N> … "/implement issue #<N>"`.
   The `/implement` skill in the repo's Claude config carries the workflow
   instructions — implement per AGENTS.md, push, open a PR that closes the
   issue. `--detach` means the session runs under the Paseo daemon and outlives
   the (short) runner job; `--worktree` keeps parallel sessions from clobbering
   one checkout.

### Scope rules

- Only issues labeled `ready-for-agent` are dispatched.
- Only issues that were **actually blocked** (at least one `- #N` bullet under
  `## Blocked by`) qualify — never-blocked issues are started manually, and
  epics (`[Epic]` title prefix) are always skipped.
- At most **3** issues carry the `agent-dispatched` label at once. Unblocked
  issues beyond the cap are deferred; because every dispatcher run re-scans all
  formerly-blocked open issues, they're picked up automatically the next time
  any issue closes.
- If a session gives up, it removes the issue's `agent-dispatched` label and
  comments — which frees a slot and makes the issue eligible again.

### Model, reasoning effort, and permission mode

Sessions default to **Opus 5 at high reasoning effort, in bypass mode**. Three
optional repository Actions variables override that without touching the
workflow (Settings → Secrets and variables → Actions → Variables):

| Variable         | Default              | Passed as    |
| ---------------- | -------------------- | ------------ |
| `PASEO_MODEL`    | `claude-opus-5`      | `--model`    |
| `PASEO_THINKING` | `high`               | `--thinking` |
| `PASEO_MODE`     | `bypassPermissions`  | `--mode`     |

Leave a variable unset (or set it empty) to fall back to the default — unlike
`PASEO_PROJECT_DIR`, none of the three are required. The defaults are pinned in
the workflow rather than inherited from the Paseo daemon, whose own defaults
move as new models ship.

See the current legal values with `paseo provider models claude` (efforts are
per-model, currently `low`/`medium`/`high`/`xhigh`/`max`/`ultracode` on the
Opus and Sonnet lines). Modes come from the provider:
`plan`/`default`/`acceptEdits`/`auto`/`bypassPermissions`.

`bypassPermissions` is the default because nobody is around to answer a
permission prompt in a detached CI session — the provider's own default
(`default`, "Always Ask") would stall the session on its first tool use until
the daemon times it out.

**The workflow validates the model and effort before spawning**, because
`paseo run` itself does not: given an unknown `--model` it creates the session
anyway rather than erroring, which would leave a typo'd variable silently
running every issue on the wrong model. So the spawn step checks the pair
against `paseo provider models claude --json` first and fails red — listing the
valid values — instead of dispatching. `--mode` needs no such check; the CLI
rejects an unknown one outright.

## Repo prerequisites

- **Create the `ready-for-agent` label** (repo → Issues → Labels): the
  dispatcher only ever considers issues carrying it. The `agent-dispatched`
  label, by contrast, is created automatically on first dispatch.
- **Add an `/implement` skill** at `.claude/skills/implement/`. The dispatch
  prompt is just `/implement issue #<N>`, so the skill is what actually tells
  the session how to work. This template does not ship one yet — without it a
  dispatched session receives an unresolvable slash command.
- **Use the `## Blocked by` convention** in issue bodies. The dispatcher parses
  `- #N` bullets under that exact heading:

  ```markdown
  ## Blocked by

  - #12
  - #15
  ```

  An issue with no such section (or an empty one) is treated as never-blocked
  and is left for manual dispatch.

## One-time Mac setup

1. **Register the runner**: repo → Settings → Actions → Runners → *New
   self-hosted runner* (macOS/ARM64), then install it as a service so it
   survives reboots: `./svc.sh install && ./svc.sh start`. Jobs queue for up to
   24 h while the Mac is offline/asleep.
2. **Paseo daemon at login**: make sure the Paseo daemon starts automatically
   (the desktop app's login-item setting) and that `paseo ls` works from a
   terminal. The runner looks for `paseo` on `PATH` plus `/opt/homebrew/bin`,
   `/usr/local/bin`, and `~/.local/bin`.
3. **Point at the checkout**: set the repository Actions **variable**
   `PASEO_PROJECT_DIR` to the absolute path of this repo's clone on the Mac
   (Settings → Secrets and variables → Actions → Variables). Sessions spawn
   worktrees off this clone.
4. **`gh` and `claude` logged in**: sessions read issues with `gh` and run on
   the Claude CLI's subscription login, so both must be authenticated for the
   account the daemon runs under.

## Manual dispatch

`agent-implement.yml` also accepts a manual run from the Actions tab with any
issue number — handy for kicking off a never-blocked issue through the same
pipeline. Add the `agent-dispatched` label yourself if you want it counted
against the in-flight cap.

# Auto-dispatch: ready issues → Paseo agent sessions

Issues marked `ready-for-agent` get implemented automatically once nothing is
blocking them: a fresh Claude Code session is spawned for each one via
[Paseo](https://paseo.sh) on a self-hosted Mac runner. Sessions run on the Mac's
Claude subscription login (no API credits) and are visible in the Paseo
desktop/mobile apps.

## How it works

Two workflows split detection from execution:

1. **`unblock-dispatch.yml`** (GitHub-hosted, pure scripting) runs when an issue
   is closed as *completed*, or on a manual `workflow_dispatch`. It scans open
   `ready-for-agent` issues, parses each body's `## Blocked by` section (`- #N`
   bullets), and keeps the ones that are ready to work — never blocked, or with
   every blocker now closed. For each, it applies the `agent-dispatched` label
   (the idempotency guard) and fires `agent-implement.yml` with the issue
   number.
2. **`agent-implement.yml`** (self-hosted Mac runner) runs
   `paseo run --detach --worktree claude/issue-<N> … "/implement issue #<N>"`.
   The `/implement` skill in the repo's Claude config carries the workflow
   instructions — implement per AGENTS.md, push, open a PR that closes the
   issue. `--detach` means the session runs under the Paseo daemon and outlives
   the (short) runner job; `--worktree` keeps parallel sessions from clobbering
   one checkout.

### Scope rules

- Only issues labeled `ready-for-agent` are dispatched.
- An issue qualifies when **nothing blocks it** — either it lists no `- #N`
  bullets under `## Blocked by` at all, or every bullet it lists is closed.
- **Umbrella issues are always skipped**: epics (`[Epic]` title prefix) and
  specs (`Spec:` title prefix). A human slices these into per-milestone child
  issues; a single agent session should never attempt one.
- At most **3** issues carry the `agent-dispatched` label at once. Ready issues
  beyond the cap are deferred; because every dispatcher run re-scans every open
  `ready-for-agent` issue, they're picked up automatically on the next run.
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
  and qualifies on any dispatcher run. Since the dispatcher only runs on an
  issue close or a manual re-scan, a never-blocked issue starts either the next
  time anything closes or when you run the workflow by hand.

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

`unblock-dispatch.yml` accepts a manual run from the Actions tab, which
re-scans the backlog under the normal scope rules. This is how never-blocked
issues get started — nothing has to close first — and how you drain a backlog
after raising the in-flight cap or fixing a `## Blocked by` list.

`agent-implement.yml` also accepts a manual run with any issue number, which
bypasses the scope rules entirely — the escape hatch for an umbrella issue or
one you haven't labeled `ready-for-agent`. Add the `agent-dispatched` label
yourself if you want it counted against the in-flight cap.

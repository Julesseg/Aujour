# Auto-dispatch: ready issues → T3 Code agent sessions

Issues marked `ready-for-agent` get implemented automatically once nothing is
blocking them: a fresh Claude Code session is spawned for each one in
[T3 Code](https://t3.chat/code) on a self-hosted Mac runner. Sessions run on the
Mac's Claude subscription login (no API credits) and are visible in the T3 Code
app like any session you started by hand.

## How it works

Two workflows split detection from execution:

1. **`unblock-dispatch.yml`** (GitHub-hosted, pure scripting) runs when an issue
   is closed as *completed*, or on a manual `workflow_dispatch`. It scans open
   `ready-for-agent` issues, parses each body's `## Blocked by` section (`- #N`
   bullets), and keeps the ones that are ready to work — never blocked, or with
   every blocker now closed. For each, it fires `agent-implement.yml` with the
   issue number and comments on the issue.
2. **`agent-implement.yml`** (self-hosted Mac runner) re-checks the issue, then
   starts a session in the T3 Code app running on that Mac: it cuts a
   `claude/issue-<N>` worktree off `origin`'s default branch, creates a thread
   on it, and sends `/implement issue #<N>`. The `/implement` skill in the
   repo's Claude config carries the workflow instructions — claim the issue
   with the `agent-dispatched` label, implement per AGENTS.md, push, open a PR
   that closes the issue. The session belongs to the app rather than to the
   job, so it outlives the (short) runner job; the per-issue worktree keeps
   parallel sessions from clobbering one checkout.

   There is no T3 Code CLI equivalent of `paseo run`, so the step drives the
   app's local HTTP API (`POST /api/orchestration/dispatch`) directly. It mints
   its own credential per run with `t3 auth session issue --token-only`, which
   signs a short-lived bearer token against the state directory the app owns —
   so nothing long-lived has to be stored in a repo secret. The app writes its
   address to `~/.t3/userdata/server-runtime.json` on startup; the step reads it
   there and fails red if nothing is listening.

### Who applies `agent-dispatched`

The session does, as its first act — never the dispatcher. The label therefore
means *a session really started on this issue*, not *a session was asked for*.
That distinction matters when the Mac runner is offline: `agent-implement.yml`
then sits queued for up to 24 h and may never run at all. A label applied at
dispatch time would leave that issue looking claimed forever, holding an
in-flight slot with nothing working it.

Between dispatch and the session's first move nothing is labeled, so the
dispatcher reads the spawn runs themselves to fill the gap. A run of
`agent-implement.yml` holds its issue while it is queued or in progress, and
for a 30-minute grace period after it succeeds — long enough for the session to
boot and label the issue. A run that failed, was cancelled, or expired unclaimed
in the queue holds nothing, so the issue goes back in the pool and is dispatched
again on the next run. (Because the runs list is the guard, the dispatcher waits
for each run it fires to become visible before moving on.)

### The spawn-time re-check

A spawn job can sit queued for hours, so what was true when the dispatcher
fired it may not be true when the Mac finally picks it up. Before spawning
anything, `agent-implement.yml` fetches the issue again and does nothing if:

- **the issue is closed** — you finished it by hand while the Mac was asleep,
  and a session for it now would redo settled work; or
- **the issue already carries `agent-dispatched`** — a session is already on
  it, so this run is a duplicate that queued behind the first.

Both leave a notice on the run rather than failing it: nothing went wrong, the
work simply no longer needs doing. A manual run can override either check by
ticking **force**, which is how you re-dispatch an issue whose session died
holding the label.

### Scope rules

- Only issues labeled `ready-for-agent` are dispatched.
- An issue qualifies when **nothing blocks it** — either it lists no `- #N`
  bullets under `## Blocked by` at all, or every bullet it lists is closed.
- **Umbrella issues are always skipped**: epics (`[Epic]` title prefix) and
  specs (`Spec:` title prefix). A human slices these into per-milestone child
  issues; a single agent session should never attempt one.
- At most **3** issues are in flight at once — counting both issues that carry
  the `agent-dispatched` label and issues whose spawn run is still live. Ready
  issues beyond the cap are deferred; because every dispatcher run re-scans
  every open `ready-for-agent` issue, they're picked up automatically on the
  next run. While the Mac is offline the cap applies to the queue, so at most
  3 sessions pile up waiting for it.
- If a session gives up, it removes the issue's `agent-dispatched` label and
  comments — which frees a slot and makes the issue eligible again.

### Model, reasoning effort, and runtime mode

Sessions default to **Opus 5 at high reasoning effort, in full-access mode**.
Three optional repository Actions variables override that without touching the
workflow (Settings → Secrets and variables → Actions → Variables):

| Variable         | Default          | Sets                            |
| ---------------- | ---------------- | ------------------------------- |
| `PASEO_MODEL`    | `claude-opus-5`  | the thread's model              |
| `PASEO_THINKING` | `high`           | the model's `effort` option     |
| `PASEO_MODE`     | `full-access`    | the thread's runtime mode       |

The names still say `PASEO_` on purpose: they carried over unchanged from the
Paseo pipeline, so a repo that was already dispatching needs no re-configuring.
Leave a variable unset (or set it empty) to fall back to the default — unlike
`PASEO_PROJECT_DIR`, none of the three are required. The defaults are pinned in
the workflow rather than inherited from T3 Code, whose own defaults move as new
models ship.

Runtime modes are `full-access`, `auto`, `auto-accept-edits`, and
`approval-required`; the workflow also accepts the Paseo spellings
`bypassPermissions`, `acceptEdits`, and `default` and maps them onto the first,
third, and fourth. Anything else fails the run with the list of valid values.
`full-access` is the default because nobody is around to answer a permission
prompt in a CI-spawned session — an approval-gated mode would stall it on its
first tool use.

**The model and the effort cannot be checked before dispatching.** Paseo's
`provider models claude --json` has no equivalent on T3 Code's HTTP API: the
model catalog only travels over the app's WebSocket channel, and dispatching
with a bad model is accepted rather than rejected. So the spawn step watches the
session for two minutes afterwards instead, and fails red with the provider's
own error if it never comes up — which is what a typo'd `PASEO_MODEL` looks
like. A session that is merely slow to start leaves a warning rather than a
failure: nothing labeled the issue, so the next dispatcher run re-dispatches it
anyway.

## Repo prerequisites

- **Create the `ready-for-agent` label** (repo → Issues → Labels): the
  dispatcher only ever considers issues carrying it. The `agent-dispatched`
  label, by contrast, is created automatically on first dispatch — the
  dispatcher creates it ahead of the session that will apply it.
- **Keep the `/implement` skill** at `.claude/skills/implement/`. The dispatch
  prompt is just `/implement issue #<N>`, so the skill is what actually tells
  the session how to work — including claiming the issue with the
  `agent-dispatched` label. Without it a dispatched session receives an
  unresolvable slash command.
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
2. **T3 Code running at login**: T3 Code is a desktop app, not a daemon, so the
   Mac has to be logged into its GUI with the app open — a locked screen is
   fine, a logged-out one is not. Set it as a login item, and check
   `~/.t3/userdata/server-runtime.json` exists and its `origin` answers
   `/api/health`. Set `T3CODE_HOME` for the runner if the app uses a data
   directory other than `~/.t3`.
3. **The `t3` CLI**: the spawn step mints its credential with it. `npm i -g t3`
   makes it a no-op; otherwise the step falls back to `npx -y t3@<version>`,
   which needs Node on the runner's `PATH` and downloads the package on a cold
   npm cache. The runner looks on `PATH` plus `/opt/homebrew/bin`,
   `/usr/local/bin`, and `~/.local/bin`.
4. **Point at the checkout**: set the repository Actions **variable**
   `PASEO_PROJECT_DIR` to the absolute path of this repo's clone on the Mac
   (Settings → Secrets and variables → Actions → Variables). Sessions spawn
   worktrees off this clone, under `~/.t3/worktrees/<repo>/`. The workflow
   registers the clone as a T3 Code project on first dispatch if it is not one
   already.
5. **`gh` and `claude` logged in**: sessions read issues with `gh` and run on
   the Claude CLI's subscription login, so both must be authenticated for the
   account running T3 Code.

## Manual dispatch

`unblock-dispatch.yml` accepts a manual run from the Actions tab, which
re-scans the backlog under the normal scope rules. This is how never-blocked
issues get started — nothing has to close first — and how you drain a backlog
after raising the in-flight cap or fixing a `## Blocked by` list.

`agent-implement.yml` also accepts a manual run with any issue number, which
bypasses the scope rules entirely — the escape hatch for an umbrella issue or
one you haven't labeled `ready-for-agent`. It still counts against the in-flight
cap: the run holds the issue while it is live, and the session it spawns labels
the issue like any other. The spawn-time re-check still applies — a closed or
already-claimed issue needs **force** ticked.

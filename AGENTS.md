# Aujour

A markdown-file journaling app for iPhone and iPad: one file per day, spawned
from templates, living in a plain folder that can sit inside an Obsidian
vault. Vocabulary in `CONTEXT.md`, foundational decisions in `docs/adr/`,
product decisions in `docs/design/v1-decisions.md`.

## Agent skills

### Auto-dispatch of ready issues

When an issue closes as completed (or on a manual re-scan),
`unblock-dispatch.yml` finds `ready-for-agent` issues that nothing blocks —
never blocked, or with every `## Blocked by` entry closed — and spawns a T3 Code
agent session for each on the self-hosted Mac runner (capped, umbrella
`[Epic]`/`Spec:` issues skipped). The session claims its issue with the
`agent-dispatched` label as its first act — the dispatcher never applies it, so
the label cannot mark an issue as claimed when the runner was down and no
session ever started. See `docs/agents/auto-dispatch.md`.

### Conflict watch

A pull request that conflicts with its base gets *no* CI checks at all —
GitHub cannot build the merge commit — so it looks exactly like a PR whose
CI has not started, and stalls unnoticed. `conflict-watch.yml` sweeps open
PRs whenever `main` moves (plus daily) and labels the conflicted ones
`has-conflicts` with a comment explaining the silence. It cannot run on
`pull_request`, since that is the trigger that does not fire.

With several agents in flight at once this is routine, so `/implement`
merges `origin/main` in before opening a PR rather than waiting to be told.

### Issue tracker

Issues live in GitHub Issues (`gh` CLI); external PRs are not a triage
surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label names for all five canonical roles (needs-triage, needs-info,
ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See
`docs/agents/domain.md`.

### Permission prompts — don't "fix" them by editing the allow list

`.claude/settings.json` is loaded and its `defaultMode` takes effect, but the
`allow` list does **not** stop the prompts that scheduled check-ins produce.
Each `send_later` trigger bakes a `session_context.allowed_tools` snapshot at
creation time, and that snapshot contains **no MCP tools at all** — so a woken
check-in has neither `mcp__github__*` (to read CI) nor `send_later` (to re-arm)
pre-approved, and asks the human every time. Nothing written in this repo
changes that snapshot.

Four commits were spent adding tool names, server names, and guessed server
names to `allow` before this was understood. `defaultMode` is the only lever
here; it is set to `bypassPermissions`. If prompts return, fix the trigger's
`allowed_tools`, or stop arming check-ins — do not add another `allow` entry.

Note on MCP rule names: connector servers are keyed by **UUID**, not display
name, so `mcp__Figma` and `mcp__Google_Calendar` never matched anything and
have been removed. Check `mcpServers` in the session's MCP config for the real
key before writing any `mcp__…` rule.

## Conventions

### Conventional Commits — commit subjects *and* PR titles

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/),
enforced by a `PreToolUse` hook (`.claude/hooks/validate-commit-msg.py`). **PR
titles must match too.** Title PRs `<type>(<scope>)!: <description>` using the
same types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`.

### Logic lives in Core, UI stays thin

`AujourCore` (in `Core/`) is a pure SwiftPM package: all business logic belongs
there, covered by `cd Core && swift test` — the fast loop that runs on any
platform. The `App/` target is a thin SwiftUI layer over it, verified by the
XCUITest suite. When implementing a feature, put the behavior in Core with unit
tests first, then wire the UI on top.

Some of the app layer is not UI and cannot live in Core either — the store over
the user's real folder, iCloud, file coordination. That code gets unit tests in
`App/AujourTests` (Swift Testing, hosted by the app, run by the same
`xcodebuild test` CI job as the XCUITest suite): fast, headless, and against
real temporary folders. Reach for it whenever the alternative is an
acceptance-level UI test proving something about a non-UI seam. It is not a
licence to move logic out of Core — the test target follows its subject, so
anything that would need neither a file system nor a system framework to test
should not have been written in `App/` in the first place.

### Always implement the UI part of an issue — never ask

**If an issue requires UI work, implement it. Do not ask whether you should,
and do not skip, defer, or stub it.** The fact that you may not be able to run
the UI tests on the box you are on (cloud/web sessions cannot — see below) is
**never** a reason to leave it out, hand it back to the user, or ask for
permission. The correct action is always: write the UI code, push it, and let
CI verify it.

#### CI is the canonical UI gate (background, not a decision to revisit)

The `App · XCUITest (macOS)` job in `.github/workflows/ci.yml` is the
canonical, reproducible gate for the UI test suite, and it runs on every PR.
You **never** need to run the UI suite locally as a precondition for
implementing an issue.

Whether the box you are on can run the UI suite at all is **environment-
specific**, so it is not stated here as a flat fact — a `SessionStart` hook
(`.claude/hooks/platform-guidance.sh`) reports it per session: cloud/web
sessions run on Linux with no iOS simulator and cannot build the `App/` target
or run XCUITest; a developer's Mac has Xcode and *can* run the suite locally,
though doing so is slow and optional. Follow whatever that hook tells you.

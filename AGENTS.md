# Aujour

A markdown-file journaling app for iPhone and iPad: one file per day, spawned
from templates, living in a plain folder that can sit inside an Obsidian
vault. Vocabulary in `CONTEXT.md`, foundational decisions in `docs/adr/`,
product decisions in `docs/design/v1-decisions.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`gh` CLI); external PRs are not a triage
surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label names for all five canonical roles (needs-triage, needs-info,
ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See
`docs/agents/domain.md`.

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

### Scope local test runs to the change — CI runs everything

Every PR runs the exhaustive matrix: the full Core suite on Linux and the full
XCUITest suite on both device families. A local run before a commit or push is
a smoke check, not a second gate — scope it to what the session touched and let
CI catch fallout elsewhere. A red CI leg on a test you did not run locally is
the system working, not a process failure.

- Iterating on Core: `swift test --filter <TypeName>` for the types under
  work. Before pushing, one full `cd Core && swift test` — it is fast enough
  to always be worth it.
- App-hosted unit tests (`App/AujourTests`): add `-only-testing:AujourTests`
  to the `xcodebuild test` invocation the SessionStart hook prints, which
  keeps the UI suite out of the run; narrow further with
  `-only-testing:AujourTests/<TypeName>`.
- Watching one UI behavior locally:
  `-only-testing:AujourUITests/<TestClass>/<testMethod>`, where the class is
  one of the feature classes over `AujourUITestCase`. The full UI suite on
  both families is CI's job.

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

---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

**Before anything else**, if the work is a GitHub issue, claim it:

```sh
gh issue edit <number> --add-label "agent-dispatched"
```

This session is the only thing that applies that label — the auto-dispatcher
deliberately does not, so the label always means a session really started and
never that one was merely asked for (see `docs/agents/auto-dispatch.md`). Claim
the issue first, before any other work: until you do, the dispatcher is holding
the issue on a grace period that runs out.

If the label does not exist yet, create it and retry: `gh label create
agent-dispatched --color 1d76db --description "An agent session has been
dispatched for this issue"`.

If you give up on the issue, remove the label and comment saying why — that
hands it back to the dispatcher and frees an in-flight slot.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Always finish by committing your work to the current branch, then **bring the
base branch in before opening the PR**: `git fetch origin main` and merge (or
rebase onto) `origin/main`, resolving any conflicts and re-running the full
test suite afterwards. Do this even if the branch was current when you
started — other agents merge while you work.

A pull request that conflicts with its base gets **no CI checks at all**:
GitHub cannot build the merge commit, so it never creates them, and the PR
looks identical to one whose CI has not started yet. Left alone it stalls
unnoticed. Conflicts found here are also far cheaper to resolve, while you
still have the context that produced the code.

Then push the branch and open a pull request (`gh pr create`) — every time,
without asking. The PR title must follow Conventional Commits, and the body
should list the acceptance criteria and how they were verified. This is the
default close-out for every `/implement` run; do not stop at a local commit.

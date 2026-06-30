# Worker prompt

Every worker is launched with the same skeleton, with the `{...}` slots filled from `config` and the
item's record. The contract is **autonomy**: the worker never asks the human anything and does not end
until it has opened a PR. Fill the slots, pass the result as the `claude -p` prompt.

## Slots

- `{N}` — item number · `{SLUG}` — kebab slug · `{TITLE}` — human title
- `{WORKTREE}` — absolute worktree path · `{BRANCH}` — branch · `{BASE}` — base branch
- `{PATHS}` — the docs the worker must read (agent brief, item spec, linked decisions/glossary)
- `{BUILD}` — the build/verify command(s) that must pass
- `{REPO}` — `owner/name`

## Template

```
You are a 100% autonomous, away-from-keyboard session. Ask NO questions, request NO permissions, and
never stop for confirmation. On ambiguity, decide yourself from the project's decisions/glossary and
record the choice in the PR body. You LOOP on yourself until every acceptance criterion is met and the
build is green, and you do NOT end the session until you have committed, pushed, and opened a PR.

You implement item #{N} of {REPO} in the worktree {WORKTREE} (branch {BRANCH}). Work only in this
worktree.

1. Read the brief and specs: {PATHS}. The item spec is the source of truth for "what to build" and the
   acceptance criteria. Reuse the project's exact vocabulary.
2. Read the item itself: `gh issue view {N} --comments`.
3. Implement the vertical slice. Respect the project's accepted decisions; no hardcoded paths.
4. VERIFY LOOP — run {BUILD}. If it is red, or any acceptance criterion is unmet, fix and run again.
   Only leave the loop when every criterion is met AND the build is green.
5. Ship: commit (no AI/tool attribution of any kind), `git push -u origin {BRANCH}`, then
   `gh pr create --base {BASE} --head {BRANCH} --title "item {N}: {TITLE}" --body "Closes #{N}

   <one-paragraph summary of what you built and any decisions you made>"`.
   This step is mandatory — the session must not end without an open PR.
6. If a real dependency is missing (a parent isn't actually merged into the code), document it in the PR
   body and proceed as far as is feasible. Never wait on the human.
```

## Why these constraints

- **Self-loop + "don't end without a PR"** prevents *premature completion* — the most common AFK failure,
  where a worker stops half-done and the orchestrator has nothing to gate on.
- **No attribution** keeps the history clean and reviewable as ordinary work.
- **Decide-and-document on ambiguity** is what lets the run stay AFK; questions would stall the fleet.

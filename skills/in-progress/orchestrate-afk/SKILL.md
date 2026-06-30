---
name: orchestrate-afk
description: Drive a backlog of dependency-ordered work items to merged PRs with a fleet of away-from-keyboard Claude Code sessions — one git worktree and one headless `claude -p` per item, throttled, gated on green CI or human review. Use to run a triaged backlog AFK on your own machine without writing orchestration code.
disable-model-invocation: true
argument-hint: "A backlog/issue source to orchestrate, or nothing to set one up"
---

# Orchestrate AFK

One **orchestrator** session drives a **fleet** of **workers** — each an autonomous headless
`claude -p` in its own git worktree — through a dependency-ordered backlog, until every item is a
merged PR. No SDK and no TypeScript: the whole machine is this skill plus one JSON state file.

This is the **no-code, Claude-Code-native** sibling of Sandcastle (a TypeScript SDK for the same
idea): parallel worktrees and AFK loops, but driven from inside Claude Code and with **scheduling**
built in. It consumes the `ready-for-agent` briefs that `/triage` produces — point it at a triaged
backlog and walk away.

## Reference docs

- [STATE-FORMAT.md](STATE-FORMAT.md) — state file schema, the status state machine, the ready-set rule
- [WORKER-PROMPT.md](WORKER-PROMPT.md) — the prompt skeleton every worker runs
- [scripts/dispatch-worker.template.sh](scripts/dispatch-worker.template.sh) — launch one worker
- [scripts/sync-and-merge.template.sh](scripts/sync-and-merge.template.sh) — the gate (poll PRs, merge green)

## Vocabulary

- **Fleet** — the workers in flight at once; capped by `max_parallel`.
- **Worker** — one detached headless `claude -p` running [WORKER-PROMPT.md](WORKER-PROMPT.md) inside its
  own worktree. The orchestrator observes it **only** through the PR it opens, never its logs.
- **Wave** — one orchestrator wake: sync → gate → recompute → dispatch → reschedule.
- **Gate** — the rule that promotes a PR: green CI → merge, red → escalate to the human, pending → wait.
  Configured as **auto-merge** or **human-review**.
- **Stagger** — the minimum delay between two dispatches; it protects your token budget, not correctness.
- **Trigger / Checkpoint** (from `/loop-me`) — the orchestrator fires on a **schedule** trigger; a red
  gate is the **checkpoint** where the human is pulled in. Everything before that runs autonomously.

## Setup

Run this once, interactively, before the first wave. Ask with `AskUserQuestion`, **batched ≤ 4 per
call**, each question with its own options — never one "all correct?" toggle. Offer a default (in
**bold**) and an escape hatch on every question.

**Batch 1 — the shape of the run:**

1. **Work source** — GitHub issues labelled `ready-for-agent` **(default)** / an explicit issue list / a
   dependency-graph README. This is where items and their `blocked_by` edges come from.
2. **Gate** — **auto-merge on green CI** / human-review each PR before it merges.
3. **Max parallel** — **2** / 1 (sequential) / 3.
4. **Cadence & scheduler** — **`ScheduleWakeup` self-loop (~38 min)** / a cron routine (`CronCreate`,
   hourly floor) / fully sequential (next dispatch only when one finishes).

**Batch 2 — the project specifics:**

5. **CI check** — the exact name of the required check (e.g. `Windows GPU`), or "no CI gate, merge when
   mergeable".
6. **Naming** — worktree path, branch, and PR-title templates, plus the base branch (**default
   `main`**). Example: worktree `../<repo>-item<N>`, branch `feat/item-<N>-<slug>`.
7. **Worker recipe** — the build/verify commands and the docs each worker must read. These fill the
   `{BUILD}` and `{PATHS}` slots of [WORKER-PROMPT.md](WORKER-PROMPT.md).
8. **Permission mode** — **`acceptEdits`** / `bypassPermissions`. Workers must run non-interactively.

Then build the state file per [STATE-FORMAT.md](STATE-FORMAT.md) from the dependency graph, and
**reconcile**: list existing worktrees (`git worktree list`) and open PRs (`gh pr list --state all`),
fold them into the state, and never recreate one.

**Done when:** the state file exists, every item has a status, and all in-flight worktrees/PRs are
reconciled into it.

## Orchestration loop

Each wave runs these steps in order. **At most one dispatch per wave** — that honors the stagger for
free and keeps token bursts down.

1. **Sync** — for every open PR, read `state`, `mergeable`, and `statusCheckRollup`
   (`scripts/sync-and-merge.template.sh`); write each result back to the state file.
   **Done when** every open PR's status is current.
2. **Gate** — per `pr_open` item:
   - **green** (required check SUCCESS + mergeable) → if gate is auto-merge,
     `gh pr merge <n> --squash --delete-branch` → `merged` → teardown worktree, prune, fast-forward the
     base branch. If gate is human-review, leave it and **checkpoint** the human ("PR #n is green and
     ready to merge").
   - **red** (required check FAILURE) → `failed`, **checkpoint** the human, do **not** unblock
     dependents, do **not** auto-retry.
   - **pending** → leave `pr_open`, re-check next wave.

   **Done when** every green PR is merged (or surfaced) and every red one escalated.
3. **Recompute ready** — any `pending` item whose `blocked_by` are **all** `merged` becomes `ready`.
4. **Dispatch** — while `count(status ∈ {dispatched, pr_open}) < max_parallel` **and**
   (`last_dispatch_at` is null or `now − last_dispatch_at ≥ stagger_minutes`): take the **lowest-numbered**
   `ready` item, create its worktree+branch if absent, run `scripts/dispatch-worker.template.sh`, set
   `dispatched` + `dispatched_at` + `last_dispatch_at`. **Done when** one worker is dispatched, or there
   is no capacity / nothing ready.
5. **Reschedule or finish** — items remain → schedule the next wave on the chosen trigger; everything
   `merged` → emit a final summary and **stop** (schedule nothing).

## Key rules

- Never more than `max_parallel` workers in flight.
- Never dispatch an item whose `blocked_by` is not **entirely** `merged`.
- A failure **never propagates**: dependents stay `pending`, nothing is auto-retried, the human decides.
- Never recreate an existing worktree or branch — reconcile and reuse.
- The orchestrator **never reads a worker's logs or token budget**. Coordinate only through the state
  file and PR/CI. This is what makes the loop crash-resumable and the pattern project-agnostic.
- Keep commits and PRs free of any AI/tool attribution.

## Relationship to Sandcastle and triage

- **Sandcastle** (`@ai-hero/sandcastle`) is a TypeScript SDK for orchestrating agents in local sandboxes
  (Docker/Podman) — you program against it. This skill is the **no-code** path: same parallel-worktree
  and AFK-loop idea, run from inside Claude Code, **plus** scheduling. For hardened container isolation
  you can later have a worker call `sandcastle.run()`; this skill does not require it.
- **`/triage`** moves issues to `ready-for-agent` and writes the agent brief. This skill **consumes**
  that output and never re-triages. Point it at a backlog `/triage` has already prepared.

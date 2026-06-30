# State format

The state file is the **single source of truth** for a run. It is plain JSON on disk so the loop
survives a crash, a restart, or a new session — any wave reconstructs everything from it. Keep it next
to the run (e.g. `orchestration-state.json` in the orchestrator's working dir).

## Schema

```json
{
  "config": {
    "repo": "owner/name",
    "root": "/abs/path/to/repo",
    "max_parallel": 2,
    "stagger_minutes": 38,
    "gate": "auto_merge_on_green_ci",
    "ci_check_name": "Windows GPU",
    "scheduler": "schedule_wakeup",
    "base_branch": "main",
    "worktree_template": "../{repo}-item{N}",
    "branch_template": "feat/item-{N}-{slug}",
    "pr_title_template": "item {N}: {title}",
    "permission_mode": "acceptEdits",
    "excluded": []
  },
  "last_dispatch_at": null,
  "items": [
    {
      "n": 1,
      "slug": "short-kebab-title",
      "blocked_by": [],
      "status": "pending",
      "branch": null,
      "worktree": null,
      "pr": null,
      "dispatched_at": null
    }
  ]
}
```

- `gate` — `auto_merge_on_green_ci` or `human_review`.
- `scheduler` — `schedule_wakeup`, `cron`, or `sequential`.
- `ci_check_name` — the one required check the gate keys on; `null` means "merge when mergeable".
- `excluded[]` — item numbers to skip (e.g. closed `wontfix`).

## Status state machine

```
pending ──(every blocked_by == merged)──▶ ready
ready ──(worker dispatched)──▶ dispatched
dispatched ──(worker opens PR)──▶ pr_open
pr_open ──(required check SUCCESS + mergeable, gate auto)──▶ merged
pr_open ──(required check FAILURE)──▶ failed        [terminal until a human acts]
```

- `merged` is the only success sink. `failed` is terminal and **non-propagating**: its dependents stay
  `pending` forever until a human intervenes. Never auto-retry a `failed` item.
- Under `human_review`, a green `pr_open` stays `pr_open` (the human merges); the loop only surfaces it.

## Ready-set rule

Each wave, recompute: an item is `ready` iff `status == pending` **and** every number in its
`blocked_by` belongs to an item with `status == merged`. Dispatch picks the **lowest-numbered** ready
item, so ordering is deterministic and reproducible.

## Reconciliation (at setup, and defensively each wave)

The state file must match reality before any dispatch:

- `git worktree list` — an existing worktree for an item → keep its `worktree`/`branch`, never recreate.
- `gh pr list --state all --json number,headRefName,state` — map open PRs to items by branch, set `pr`
  and `pr_open`; map a `MERGED` PR to `merged`.
- A branch that already has local commits but no PR → the worker stopped before shipping; finish it
  (push + open PR) rather than redispatching from scratch.

Reconciliation is why the run is idempotent: re-entering setup on a live run changes nothing.

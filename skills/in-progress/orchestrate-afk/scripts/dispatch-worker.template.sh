#!/usr/bin/env bash
# dispatch-worker.template.sh — launch ONE AFK worker for a backlog item.
# Copy, fill the CONFIG block, and run from the orchestrator. Idempotent: an existing
# worktree is reused, never recreated. The worker runs detached; its stdout/stderr go to a
# per-worker log the orchestrator never reads (it gates on the PR only).
set -euo pipefail

# --- CONFIG (fill these) ---------------------------------------------------
ROOT="/abs/path/to/repo"                 # config.root
BASE="main"                              # config.base_branch
N="04"                                   # item number (zero-pad to taste)
SLUG="cv-kalman-tracker"                 # item slug
WORKTREE="${ROOT}/../$(basename "$ROOT")-item${N}"   # config.worktree_template
BRANCH="feat/item-${N}-${SLUG}"          # config.branch_template
PERMISSION_MODE="acceptEdits"            # config.permission_mode (or bypassPermissions)
LOG_DIR="${ROOT}/.afk-logs"
PROMPT_FILE="$1"                         # path to the filled WORKER-PROMPT.md text
# ---------------------------------------------------------------------------

mkdir -p "$LOG_DIR"

# Create the worktree+branch only if absent (reconcile, don't recreate).
# Match the branch in the worktree list rather than the path, to stay slash-format agnostic.
if ! git -C "$ROOT" worktree list --porcelain | grep -qF "branch refs/heads/${BRANCH}"; then
  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git -C "$ROOT" worktree add "$WORKTREE" "$BRANCH"
  else
    git -C "$ROOT" worktree add -b "$BRANCH" "$WORKTREE" "$BASE"
  fi
fi

# Launch the worker detached. The orchestrator tracks the resulting PR, not this process.
( cd "$WORKTREE" && \
  claude -p "$(cat "$PROMPT_FILE")" \
    --permission-mode "$PERMISSION_MODE" \
    --add-dir "$WORKTREE" \
    > "${LOG_DIR}/worker-${N}.log" 2>&1 & )

echo "dispatched item ${N} -> ${BRANCH} (log: ${LOG_DIR}/worker-${N}.log)"

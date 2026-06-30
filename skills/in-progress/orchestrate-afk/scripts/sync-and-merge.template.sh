#!/usr/bin/env bash
# sync-and-merge.template.sh — the GATE. Print each open PR's status, and (if auto-merge)
# merge the green ones and tear down their worktrees. The orchestrator parses stdout to
# update the state file. Red PRs are reported, never merged; dependents are not unblocked here.
set -euo pipefail

# --- CONFIG (fill these) ---------------------------------------------------
ROOT="/abs/path/to/repo"          # config.root
BASE="main"                       # config.base_branch
CI_CHECK="Windows GPU"            # config.ci_check_name ("" => merge when mergeable)
GATE="auto_merge_on_green_ci"     # or human_review
# ---------------------------------------------------------------------------

cd "$ROOT"

# One line per open PR: "<num> <branch> <verdict>"  verdict in {green,red,pending}
gh pr list --state open --json number,headRefName --jq '.[] | "\(.number) \(.headRefName)"' |
while read -r num branch; do
  roll=$(gh pr view "$num" --json mergeable,statusCheckRollup \
    --jq '{m:.mergeable, c:[.statusCheckRollup[]? | {name:(.name//.context), s:(.status//.state), r:(.conclusion//.state)}]}')
  mergeable=$(jq -r '.m' <<<"$roll")
  if [ -n "$CI_CHECK" ]; then
    concl=$(jq -r --arg n "$CI_CHECK" '.c[] | select(.name==$n) | .r' <<<"$roll")
  else
    concl="SUCCESS"
  fi

  case "$concl" in
    SUCCESS) [ "$mergeable" = "MERGEABLE" ] && verdict=green || verdict=pending ;;
    FAILURE|CANCELLED|TIMED_OUT|ERROR) verdict=red ;;
    *) verdict=pending ;;
  esac
  echo "$num $branch $verdict"

  if [ "$verdict" = green ] && [ "$GATE" = auto_merge_on_green_ci ]; then
    gh pr merge "$num" --squash --delete-branch || true
    # teardown the worktree for this branch, if any
    wt=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
      /^worktree /{w=$2} $0=="branch "b{print w}')
    [ -n "${wt:-}" ] && git worktree remove "$wt" --force || true
    git branch -D "$branch" 2>/dev/null || true
  fi
done

# Reintegrate merged work into the local base branch for the next dispatch.
git fetch --prune origin
git checkout "$BASE" && git merge --ff-only "origin/$BASE"

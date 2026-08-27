#!/bin/bash
# bridge-code.sh <task-id> <repo-path> <prompt-file> <file1> [file2 ...]
set -euo pipefail

TASK_ID="$1"; REPO_PATH="$2"; PROMPT_FILE="$3"; shift 3
FILES=("$@")

OMNIROUTE_BASE="${OMNIROUTE_BASE:-http://localhost:20128/v1}"
OMNIROUTE_MODEL="${OMNIROUTE_MODEL:-auto}"

if ! curl -sf -m 5 "${OMNIROUTE_BASE}/models" >/dev/null 2>&1; then
  echo "ERROR: OmniRoute server not reachable at ${OMNIROUTE_BASE}" >&2
  exit 1
fi

WORKTREE_DIR="$(mktemp -d -t omniroute-worktree-XXXXXX)"
cd "$REPO_PATH"

if ! git rev-parse --verify -q HEAD >/dev/null; then
  echo "ERROR: ${REPO_PATH} has no commits yet (unborn HEAD); git worktree needs at least one commit to branch from" >&2
  rmdir "$WORKTREE_DIR" 2>/dev/null || true
  exit 1
fi

SUCCEEDED=0
cleanup_worktree() {
  if [ "$SUCCEEDED" -ne 1 ]; then
    cd "$REPO_PATH" 2>/dev/null || true
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    git branch -D "omniroute/${TASK_ID}" 2>/dev/null || true
  fi
}
trap cleanup_worktree EXIT

git worktree add -q "$WORKTREE_DIR" -b "omniroute/${TASK_ID}"

cd "$WORKTREE_DIR"
export OPENAI_API_BASE="$OMNIROUTE_BASE"
export OPENAI_API_KEY="${OMNIROUTE_API_KEY:-omniroute-local}"

AIDER_TIMEOUT_SEC=360
aider --model "openai/${OMNIROUTE_MODEL}" --yes-always --no-auto-commits --verbose --no-show-model-warnings \
    --message "$(cat "$PROMPT_FILE")" "${FILES[@]}" >"${WORKTREE_DIR}/.aider-output.log" 2>&1 &
AIDER_PID=$!
( sleep "$AIDER_TIMEOUT_SEC"; kill -TERM "$AIDER_PID" 2>/dev/null ) &
WATCHDOG_PID=$!

set +e
wait "$AIDER_PID"
AIDER_EXIT=$?
set -e
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

if [ "$AIDER_EXIT" -ne 0 ]; then
  echo "ERROR: aider failed or was killed after ${AIDER_TIMEOUT_SEC}s, see ${WORKTREE_DIR}/.aider-output.log" >&2
  exit 1
fi

git add -A
DIFF="$(git diff --cached)"
if [ -z "$DIFF" ]; then
  echo "ERROR: aider produced no changes" >&2
  exit 1
fi

SUCCEEDED=1
echo "WORKTREE_PATH=${WORKTREE_DIR}"
echo "$DIFF"

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
git worktree add -q "$WORKTREE_DIR" -b "omniroute/${TASK_ID}"

cd "$WORKTREE_DIR"
export OPENAI_API_BASE="$OMNIROUTE_BASE"
export OPENAI_API_KEY="${OMNIROUTE_API_KEY:-omniroute-local}"

if ! aider --model "openai/${OMNIROUTE_MODEL}" --yes-always --no-auto-commits \
      --message "$(cat "$PROMPT_FILE")" "${FILES[@]}" >"${WORKTREE_DIR}/.aider-output.log" 2>&1; then
  echo "ERROR: aider failed, see ${WORKTREE_DIR}/.aider-output.log" >&2
  exit 1
fi

git add -A
DIFF="$(git diff --cached -- "${FILES[@]}")"
if [ -z "$DIFF" ]; then
  echo "ERROR: aider produced no changes" >&2
  exit 1
fi

echo "WORKTREE_PATH=${WORKTREE_DIR}"
echo "$DIFF"

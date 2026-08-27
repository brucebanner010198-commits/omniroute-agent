---
name: omniroute-agent
description: Use this skill instead of the Agent tool for any sub-agent-shaped work (implementation, research, review). Tries a free local model via OmniRoute first, reviews the result, retries once, and falls back to a real Claude sub-agent only if both attempts fail.
---

# OmniRoute agent bridge

## When to use this

Any time you would otherwise call the `Agent` tool for implementation,
research, or review work. Do not use this for the main conversation turn
itself, and skip straight to a real `Agent` call if the user explicitly asks
for one ("use a real sub-agent", "skip OmniRoute"), see Escape hatch below.

## Steps

1. **Generate a task ID.** `TASK_ID=$(date +%s)-$$` (or similar unique string).

2. **Pick a path.**
   - Code-editing work (the task modifies files in a real repo) → code path.
   - Research, review, or any other text-shaped task → text path.

3. **Code path:**
   - Write the task prompt to a temp file.
   - Run `~/.claude/skills/omniroute-agent/scripts/bridge-code.sh "$TASK_ID" <repo-path> <prompt-file> <files...>`.
   - If it exits non-zero: this is attempt failure #1 (or #2). Go to step 5.
   - If it succeeds: read the printed `WORKTREE_PATH` and diff.

4. **Text path:**
   - Gather any repo context the task needs yourself first (read files, grep)
     and inline it into the prompt, the free model behind this bridge has no
     tools. If the task needs more context than reasonably fits in one
     prompt (a broad codebase survey, "find every caller of X" across a large
     repo), this task is out of scope for OmniRoute: skip straight to writing
     the exhausted marker (step 6) and use a real `Agent` call.
   - Write the prompt (with inlined context) to a temp file.
   - Run `~/.claude/skills/omniroute-agent/scripts/bridge-text.sh <prompt-file>`.
   - If it exits non-zero: this is attempt failure #1 (or #2). Go to step 5.

5. **Review the result yourself.**
   - Code: read the diff. Does it do what was asked? Does it look correct
     and complete? Same bar you'd apply reviewing a real sub-agent's report.
   - Text: does it factually answer the task?
   - Pass → step 7 (accept).
   - Fail, and this was the first attempt → retry once: refine the prompt
     with what was wrong and what to fix, re-run the same bridge (step 3 or
     4). This second attempt's result also goes through this review step.
   - Fail, and this was the second attempt (or the bridge itself failed
     twice) → step 6 (fallback).

6. **Fallback: write the exhausted marker.**
   ```bash
   mkdir -p .claude
   touch ".claude/.omniroute-exhausted-${TASK_ID}"
   ```
   Then make the real `Agent` call for this task as you normally would. The
   `PreToolUse` hook will see the marker, allow the call, and delete the
   marker.

7. **Accept the result.**
   - Text: use the response directly, same as a sub-agent's report.
   - Code: `bridge-code.sh` runs Aider with `--no-auto-commits`, so the diff
     is uncommitted in the worktree. Commit it there first, then merge the
     branch into the real working tree, then clean up:
     ```bash
     git -C "$WORKTREE_PATH" add -A
     git -C "$WORKTREE_PATH" commit -m "omniroute: <short summary of the task>"
     git merge --no-ff "omniroute/${TASK_ID}"
     git worktree remove "$WORKTREE_PATH"
     git branch -d "omniroute/${TASK_ID}"
     ```
     The user's working tree is only touched at the `git merge` step, never
     before.

## Escape hatch

If the user explicitly asks to skip OmniRoute for this task, write the
exhausted marker directly (step 6) without attempting the bridge scripts,
then make the real `Agent` call.

---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development (Thin Local Extension)

This skill is a thin extension layer.

## Base Workflow

1. Invoke `superpowers:subagent-driven-development`.
2. Follow upstream process exactly, including review order (spec first, then code quality).

Do not re-implement or diverge from upstream process details in this file.

## Required Extra Behavior

Use local sync script to persist plan/task status:

```bash
SYNC=~/.codex/skills/plan-progress-sync/scripts/sync-plan-status.sh
```

When task state changes, run:

- Task started:
  ```bash
  "$SYNC" --plan <plan-path> --event task_started --task-id TNN --mode subagent-driven-development
  ```
- Task completed (immediately after marking completed in `update_plan`):
  ```bash
  "$SYNC" --plan <plan-path> --event task_completed --task-id TNN --mode subagent-driven-development
  ```
- Task blocked:
  ```bash
  "$SYNC" --plan <plan-path> --event task_blocked --task-id TNN --task-title "<blocker>" --mode subagent-driven-development
  ```
- Plan completed:
  ```bash
  "$SYNC" --plan <plan-path> --event plan_completed --mode subagent-driven-development
  ```

## Enforcement

- A task is not considered done until the `task_completed` sync command succeeds.
- If sync fails, stop and fix sync first.
- Keep plan task headings in `### Task N:` format.

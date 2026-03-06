---
name: my-executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---

# Executing Plans (Thin Local Extension)

This skill is a thin extension layer.

## Base Workflow

1. Invoke `superpowers:executing-plans`.
2. Follow the upstream workflow exactly.

Do not re-implement or diverge from upstream process details in this file.

## Required Extra Behavior

Use local sync script to persist plan/task status:

```bash
SYNC=~/.codex/skills/plan-progress-sync/scripts/sync-plan-status.sh
```

When task state changes, run:

- Task started:
  ```bash
  "$SYNC" --plan <plan-path> --event task_started --task-id TNN --mode executing-plans
  ```
- Task completed (immediately after marking completed in `update_plan`):
  ```bash
  "$SYNC" --plan <plan-path> --event task_completed --task-id TNN --mode executing-plans
  ```
- Task blocked:
  ```bash
  "$SYNC" --plan <plan-path> --event task_blocked --task-id TNN --task-title "<blocker>" --mode executing-plans
  ```
- Plan completed:
  ```bash
  "$SYNC" --plan <plan-path> --event plan_completed --mode executing-plans
  ```

## Enforcement

- A task is not considered done until the `task_completed` sync command succeeds.
- If sync fails, stop and fix sync first.
- Keep plan task headings in `### Task N:` format.

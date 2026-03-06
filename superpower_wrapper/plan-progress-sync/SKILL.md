---
name: plan-progress-sync
description: Use when executing tasks from docs/plans files and you need persistent plan-level and task-level status tracking across sessions.
---

# Plan Progress Sync

Persist execution status into markdown files so progress survives session resets.

## What It Updates

- `docs/plans/INDEX.md` (global status board)
- Current plan file:
  - `## Execution Status`
  - `## Task Status`

The sync script also auto-detects and writes `Design Ref` when missing.

## Script

- `~/.codex/skills/plan-progress-sync/scripts/sync-plan-status.sh`

## Events

- `task_started`
- `task_completed`
- `task_blocked`
- `plan_completed`

## Usage

```bash
SYNC=~/.codex/skills/plan-progress-sync/scripts/sync-plan-status.sh

# Start or switch active task
"$SYNC" --plan docs/plans/2026-03-05-feature.md --event task_started --task-id T03 --mode executing-plans

# Mark task complete (updates both plan and global index)
"$SYNC" --plan docs/plans/2026-03-05-feature.md --event task_completed --task-id T03 --mode executing-plans

# Record blocker
"$SYNC" --plan docs/plans/2026-03-05-feature.md --event task_blocked --task-id T04 --task-title "DB migration lock timeout" --mode subagent-driven-development

# Mark whole plan complete
"$SYNC" --plan docs/plans/2026-03-05-feature.md --event plan_completed --mode executing-plans
```

## Rules

- Run sync immediately after task state changes.
- Treat task completion as done only after sync succeeds.
- Keep plan task headings in `### Task N:` format so task parsing is stable.

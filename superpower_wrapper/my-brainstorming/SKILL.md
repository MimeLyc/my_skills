---
name: my-brainstorming
description: Thin local wrapper around the upstream brainstorming skill. Use before any creative work when you want an explicit user-centered requirement clarification phase before any technical stack, architecture, or code discussion; records the clarified user requirements in the design doc, then defers the rest of the workflow to the upstream brainstorming skill.
---

# Brainstorming (Thin Local Extension)

This skill is a thin extension layer.

## Base Workflow

1. Read `~/.codex/superpowers/skills/brainstorming/SKILL.md`.
2. Follow the upstream workflow exactly after applying the extra behavior below.

Do not re-implement or diverge from upstream process details in this file.

## Required Extra Behavior

Before discussing technical stack, architecture, APIs, file layout, implementation details, or code structure, run an explicit **user-requirements clarification phase**.

During this phase:

- Stay in the user's world: goals, users, scenarios, expectations, constraints, and success outcomes.
- Do **not** discuss concrete technologies, frameworks, architecture, data models, APIs, filenames, or code.
- Ask one question at a time until the main user journeys, edge cases, failure paths, and non-goals are clear.
- Prefer questions about who is using the solution, what triggers the workflow, what the user expects to happen, and what can go wrong.
- Summarize the confirmed requirements in plain product language before moving into any technical design.
- Only start technical/design exploration after the user has confirmed that the requirement summary is accurate enough.

Minimum requirement coverage before moving on:

1. Target users or roles
2. Core user goals
3. Primary usage scenarios
4. Edge cases and failure scenarios
5. Constraints and success criteria
6. Explicit out-of-scope items or non-goals

## Design Doc Requirement

When writing the design document, include a dedicated requirements section near the top that captures the clarified user-facing needs.

Use this structure or an equivalent one:

```markdown
## User Requirements

### Users and Goals
### Primary Scenarios
### Edge Cases and Failure Paths
### Constraints and Success Criteria
### Out of Scope
### Open Questions or Assumptions
```

This section must be written in user/product language first, before the technical design sections that follow.

## Enforcement

- Do not let technical brainstorming begin before the user-requirements clarification phase is complete.
- Do not skip writing the user-requirements section into the design doc.
- If the upstream brainstorming workflow changes, continue to follow the upstream file directly rather than copying its instructions here.

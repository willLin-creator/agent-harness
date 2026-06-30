---
name: unify
version: 1.0.0
description: |
  Loop closure after implementation. Compares plan vs. actual, logs decisions,
  records deferred issues, and updates project state. Every plan must close
  with /unify — no orphan plans.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Write
  - Edit
  - AskUserQuestion
---

# /unify — Close the Loop

Run this after completing an implementation task. Every plan gets a unify step — no exceptions.

## When to trigger
- After finishing work from your plan / plan-review step
- After completing a set of related issues from a single initiative
- After any multi-file implementation effort
- When switching to a different workstream

## Process

### Step 1: Gather What Was Planned

Identify the source plan. Check (in order):
1. The most recent plan / plan-review output in this conversation
2. Issues in your issue tracker that were worked on
3. `TODOS.md` items that were addressed
4. Ask the user if unclear: "What was the plan I should compare against?"

### Step 2: Compare Plan vs. Actual

For each planned task/item, classify as:

| Status | Meaning |
|--------|---------|
| DONE | Completed as planned |
| DONE_DIFFERENT | Completed, but approach changed — document why |
| DEFERRED | Not done — moved to backlog or future work |
| DROPPED | Intentionally removed — document why |
| BLOCKED | Could not complete — document blocker |

Present the comparison:
```
PLAN vs. ACTUAL — [Feature/Initiative Name]

DONE (N):
  - [task] — as planned
  - [task] — as planned

DONE_DIFFERENT (N):
  - [task] — planned: [X], actual: [Y], reason: [why]

DEFERRED (N):
  - [task] — reason: [why], where tracked: [issue tracker / TODOS / backlog]

DROPPED (N):
  - [task] — reason: [why]

BLOCKED (N):
  - [task] — blocker: [what], owner: [who]
```

### Step 3: Log Decisions

Extract every decision made during implementation that wasn't in the original plan. These are valuable context for future sessions.

Format:
```
DECISIONS MADE DURING IMPLEMENTATION

1. [Decision] — because [reason]. Affects: [what downstream]
2. [Decision] — because [reason]. Affects: [what downstream]
```

### Step 4: Record Deferred Issues

Anything that came up during implementation but was intentionally not addressed. Each must have a tracking location.

For each deferred issue:
- **What:** One-line description
- **Why deferred:** Scope, time, dependency, needs more info
- **Where tracked:** Issue tracker ID, `TODOS.md`, or `my-tasks.yaml`
- **Risk of deferring:** What breaks or degrades if this stays unresolved

If a deferred issue has no tracking location, ask: "Should I add this to `TODOS.md` or create a ticket in the issue tracker?"

### Step 4.5: Compound Learnings Check

Before updating state, scan the decisions log (Step 3) and deferred issues (Step 4) for
compound-worthy patterns:
- A solved problem that other team members will hit (auth flow, migration pattern, integration approach)
- A reusable framework or scoring rubric that emerged
- A premise that shifted during implementation and changes how we should approach the next thing

If any qualify, prompt:
```
COMPOUND CANDIDATE — [Initiative Name]
[1-line summary of the pattern/decision]

Capture this as a reusable learning doc (e.g. in a learnings/ folder) so the team can reuse it? [Y/N]
```

Don't auto-fire — compounding is high-value but the call is yours. One prompt per
qualifying pattern. If nothing qualifies (most loop closures won't have a compound moment),
skip silently and proceed to Step 5.

---

### Step 5: Update Project State

Update `STATE.md` in the project root (create if it doesn't exist):

```markdown
# Project State
**Last updated:** [date]
**Last unify:** [date] — [feature/initiative name]

## Current Work
[What's active right now — empty if between initiatives]

## Recent Decisions
[Last 10 decisions from Step 3, newest first]

## Active Blockers
[Anything currently blocked, with owner]

## Deferred Issues
[Accumulated deferred items with tracking locations]
```

If `STATE.md` already exists, append new decisions and update the header — don't overwrite existing content.

### Step 6: Update Lessons (if applicable)

Check: did anything go wrong during implementation that should be logged to a `lessons.md`?
- Approach that didn't work and had to be changed
- Assumption that proved wrong
- Pattern that should be reused

If yes, log it. If no, move on.

### Step 7: Present Summary

```
UNIFY COMPLETE — [Feature/Initiative Name]

Plan completion: [N/M tasks done] ([percentage]%)
Decisions logged: [count]
Deferred issues: [count] ([count] tracked, [count] need tracking)
State updated: STATE.md

Loop closed. Ready for next initiative.
```

## Rules

- **Never skip unify.** If the user moves to a new task without unifying, remind them once: "We haven't closed the loop on [X] — want to /unify first?"
- **Deferred issues must be tracked.** No "we'll get to it later" without an issue-tracker ticket, `TODOS.md` entry, or `my-tasks.yaml` item.
- **Decisions are first-class.** The most valuable output of unify is often the decisions log — it prevents re-litigating the same choices in future sessions.

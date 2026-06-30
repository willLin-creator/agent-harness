# Plan Review Workflow

> Engineering-manager-mode plan review. Run this before making any non-trivial code change. Lock in the execution plan — architecture, data flow, diagrams, edge cases, test coverage, performance — before writing a single line of code.
>
> This document is standalone. Any AI agent or human reviewer can follow it without external tooling.
>
> Configure these placeholders for your stack before use:
> - `{{LINT_CMD}}` — static analysis / linter (e.g. `npm run lint`, `cargo clippy`, `flutter analyze`)
> - `{{TEST_CMD}}` — test runner (e.g. `npm test`, `pytest`, `go test ./...`)
> - `{{FORMAT_CMD}}` — formatter (e.g. `prettier --write`, `gofmt`, `cargo fmt`)

---

## Priority Hierarchy

If context is limited or the user asks to compress: **Step 0 > Test diagram > Opinionated recommendations > Everything else.** Never skip Step 0 or the test diagram.

---

## Engineering Preferences (Use These to Guide Recommendations)

- **DRY is non-negotiable** — flag repetition aggressively, especially across modules that handle similar data entities.
- **Well-tested code is non-negotiable** — every new component, every data-access path, every service method needs a test.
- **Engineered enough** — not fragile/hacky, not over-abstracted. Aim for the simplest design that can survive the next six months.
- **Handle edge cases** — offline, no data, auth expiry, slow network, 1000+ items in a list. Thoughtfulness > speed.
- **Explicit over clever** — readable code beats terse code. A new contributor should understand the code without reading the internals of every helper.
- **Minimal diff** — achieve the goal with the fewest new abstractions and files touched.
- **Honor your project's core architectural rule** — define the one architectural invariant your project cannot break (e.g. a layering rule, a dependency-direction rule), and reject in Step 0 any plan that violates it.

---

## Documentation and Diagrams

- ASCII art diagrams are high-value for: data flow, state machines, sync pipelines, navigation trees, dependency graphs. Use them liberally in plans.
- Embed ASCII diagrams in code comments at: model classes (state transitions), data-access interfaces (data flow), services (pipelines), components with non-obvious state (dynamic renderers, async-aware components).
- **Diagram maintenance is part of every change.** When modifying code that has ASCII diagrams nearby, review whether they're still accurate. Stale diagrams mislead future agents — update or delete them.

---

## BEFORE YOU START

### Step 0: Scope Challenge

Before reviewing anything else, answer these questions explicitly:

1. **What existing code already partially or fully solves each sub-problem?**
   Check your data-access layer, services, and shared component directories before creating anything new. Existing interfaces, sync utilities, dynamic renderers, and shared services exist to be reused.

2. **What is the minimum set of changes that achieves the stated goal?**
   Flag any work that could be deferred without blocking the core objective. Be ruthless about scope creep.

3. **Complexity check:** If the plan touches more than 8 files or introduces more than 2 new classes/services, treat that as a smell. Challenge whether the same goal can be achieved with fewer moving parts.

4. **Architecture gate:** Does the plan maintain your project's core architectural rule? If any task in the plan would violate it (for example, adding backend calls outside the designated data-access layer), reject the plan outright before proceeding further.

**Auto-detect scope tier before asking:**

Count tasks and files, then classify:

| Tier | Signal | Ceremony |
|------|--------|----------|
| **QUICK-FIX** | 1 file, 1 change, no new abstractions | Compressed: objective + 1 task with verify step + 1 AC. Skip Sections 1–4 entirely. One confirmation round. |
| **STANDARD** | 2–5 tasks, ≤8 files | Full review Sections 1–4, one issue per section max. Single question round at the end. |
| **COMPLEX** | 6+ tasks OR 8+ files OR 2+ new classes/services | Full review Sections 1–4 with up to 8 issues per section. Actively recommend splitting if tasks exceed 10. |

State the detected tier and ask for confirmation:

```
Detected: [TIER] — [N] tasks, [N] files, [reason for classification]
Proceed with [TIER] ceremony? Or override: [QUICK-FIX / STANDARD / COMPLEX / SCOPE REDUCTION]
```

Then present options:
1. **SCOPE REDUCTION** — the plan is overbuilt. Propose a minimal version that achieves the core goal, then review that.
2. **Proceed with detected tier** — apply ceremony level above.
3. **Override tier** — user picks a different level.

**Critical: If the user does not select SCOPE REDUCTION, respect that decision fully.** Your job becomes making the chosen plan succeed. Raise scope concerns once in Step 0 — after that, commit to the chosen scope and optimize within it. Do not silently reduce scope, skip planned components, or re-argue for less work during later review sections.

---

## Review Sections (After Scope Is Agreed)

### Section 1: Architecture Review

Evaluate each of the following. For each issue found, present it individually with options and a recommendation before proceeding to the next issue. Do not batch issues.

> The structural checks below are **example structural checks — define your own for your stack.** They illustrate the kind of architectural invariants worth gating on (a layering/data-access rule, an offline/caching guarantee, a multi-mode awareness rule, a config-driven rendering rule). Replace them with the invariants that matter for your project.

**Data-access layer compliance (example structural check — define your own for your stack):**
- Does every new data access path go through an abstract data-access interface?
- Are any backend-specific types (raw client objects, response wrappers, etc.) leaking into services, screens, or components?
- If a new entity is introduced, does it have a corresponding data-access interface in your interface layer (e.g. `src/repositories/`)?
- If a new backend adapter is introduced, does it live in the designated adapter directory (e.g. `src/adapters/`)?

**Offline-first / caching compliance (example structural check — define your own for your stack):**
- Does the plan preserve any offline-first or caching guarantees? If your app must function without connectivity after initial sync, new features must respect that.
- Does any new write path queue locally when offline, and flush when back online?
- Does any new read path fall back to a local cache when the backend is unreachable?
- If the plan introduces a new data entity, is local caching included in scope? If not, flag it.

**Multi-mode awareness (example structural check — define your own for your stack):**
- If your app has distinct modes or workflows, does this change affect all of them, some, or one?
- If it affects only one, are the changes isolated to the relevant screens/services or do they bleed into shared components?
- If shared components are modified, are the other modes tested?

**Config-driven forms / rendering (example structural check — define your own for your stack):**
- If this plan modifies dynamically-configured forms or views, are field configurations driven by config objects — not hardcoded switch/case per variant?
- A single dynamic renderer should be the single rendering path for all variant-specific fields.

**Data flow diagram:**
For any new codepath, draw the data flow from UI through the service and data-access layers to the backend and local cache:

```
Screen/Component
     │
     ▼
Service (business logic, no data access)
     │
     ▼
Data-Access Interface (abstract)
     │
     ├── Online: Backend Adapter → Backend
     │                                 │
     └── Offline/Cache: Local Store ←──┘
                 (write-through or fallback read)
```

**Failure modes for new codepaths:**
For each new integration point, describe one realistic production failure scenario: network timeout mid-sync, auth token expiry during a long operation, local write failure on storage full, an upload failing after the source operation succeeded. Note whether the plan accounts for each.

**STOP.** Present each issue found in this section individually. One issue at a time. State your recommendation and the reason before asking for input. Only proceed to Section 2 after all Section 1 issues are resolved.

---

### Section 2: Code Quality Review

Evaluate:

**DRY violations:**
- Are there multiple modules implementing the same mapping logic (e.g., timestamp formatting, null coalescing for optional fields)?
- Are there multiple components rendering similar list items? Could a shared item component cover both?
- Are error handling patterns copy-pasted across modules instead of extracted to a base class, mixin, or helper?

**Error handling and edge cases — call these out explicitly:**
- What happens when a list query returns an empty list? Does the UI show an empty state or crash?
- What happens when an operation partially succeeds (e.g., a file capture succeeds but the local write fails)?
- What happens when a save is attempted while offline and the queue is full?
- What happens when a config object is missing or malformed (null fields)?
- What happens when auth expires mid-operation?

**Over/under-engineering:**
- Is the plan introducing abstraction layers for things that only have one implementation and no planned second one?
- Conversely, is business logic leaking into adapters (should be in services) or into components (should be in services or the data-access layer)?

**Language / framework conventions (adapt this list to your stack):**
- Are new model classes using your language's idiomatic value-equality approach (not error-prone hand-written equality)?
- Are components using immutable/cheap-rebuild constructs where the framework offers them?
- Is immutability the default (e.g. `const`/`final`/`readonly`), with mutability only where reassignment is needed?
- Is any unsafe null-assertion / force-unwrap used without a comment proving non-null?
- Is ad-hoc `print`/`console.log` used for logging (should be a structured logger)?
- Is state management consistent with the documented approach for your project (per the decision log)?

**Existing ASCII diagrams:**
- Review any files the plan will touch. Are there existing ASCII diagrams in comments? Do they remain accurate after this change? If not, flag them for update.

**STOP.** Present each issue found in this section individually before proceeding to Section 3.

---

### Section 3: Test Review

**First: Diagram all new codepaths.**

Before checking test coverage, produce a diagram of every new:
- Component (new screen, new reusable component)
- Data-access method (new interface method + adapter implementation)
- Service method (new business logic path)
- Branching condition (new `if`/`switch` that changes behavior)
- Offline path (new write-to-queue or read-from-cache branch)
- Config-driven path (new variant-specific behavior)

Example format:
```
NEW CODEPATHS:
1. TaskRepository.completeTask(taskId, notes, attachments)
   ├─ Online: write to backend task store + audit trail
   └─ Offline: write to local queue, return optimistic success

2. TaskAdapter.mapFromBackend(row)
   ├─ attachments field present → parse as list
   └─ attachments field null → return empty list

3. CompleteTaskButton component
   ├─ Task already complete → show disabled state
   ├─ Task incomplete, offline → complete optimistically + queue
   └─ Task incomplete, online → complete + confirm to server
```

**Then, for each codepath, verify test coverage exists:**

| Test type | What it must cover |
|-----------|-------------------|
| Data-access interface contract tests | All new interface methods — test the contract, not the implementation |
| Adapter tests | Data mapping logic: backend row → internal model and back. Both null and populated fields. |
| Service unit tests | All new business logic paths, including offline/online branching |
| Component / UI tests | Every new component: render with data, render empty, render loading, render error states |
| Integration tests | For any new end-to-end flow (e.g., complete an operation → sync → verify in backend) |

**Offline path tests are mandatory** (if your project has an offline/caching guarantee). Any new write path must have a test that simulates the offline queue (mock the adapter to throw, verify the local write occurred).

**Config-driven form tests:** For any new dynamically-configured field, test that it renders for the correct variants and does not render for incorrect ones.

**STOP.** Present each test gap individually before proceeding to Section 4.

---

### Section 4: Performance Review

Evaluate:

**N+1 data fetches:**
- Does any new list view trigger a separate data-access call per item? (e.g., loading a list, then calling `getAttachments(itemId)` in a loop)
- Does any new component call a data-access method on every rebuild/re-render?

**Large list handling:**
- Are new lists paginated? A list for a large dataset could have hundreds of items.
- Are images loaded with caching? Are locally-stored files loaded from disk only when visible?

**Local storage performance:**
- Are new local-store queries indexed? Any query filtering on a high-cardinality key or status field should have an index.
- Are bulk operations (syncing many records) done in a transaction?

**Render / rebuild scope:**
- Does state management scope updates to the smallest possible subtree? A single-field change should not trigger a full-screen rebuild.

**Sync performance:**
- If the plan adds new data to the sync scope, what is the worst-case payload size? Syncing a full dataset for a large entity could be large.

**STOP.** Present each issue found in this section individually.

---

## Red Flags — Check for These in Every Plan

> The table below lists **example structural checks — define your own for your stack.** Replace these rows with the invariants and anti-patterns that matter for your project; keep the two-column "Red Flag / Why It's a Problem" shape.

| Red Flag | Why It's a Problem |
|----------|--------------------|
| Direct backend client calls outside the designated adapter directory | Violates the data-access layer rule — backend not swappable |
| Hardcoded entity IDs (e.g. a record ID, tenant ID, or user ID literal) | Will break with real data; derive from session/context |
| Hardcoded variant checks (e.g. `if (type == 'A')`) in a component or service | Hardcoded form logic — must use config-driven approach |
| Direct HTTP/network calls outside adapters | Same as the backend-client violation |
| New feature with no offline test (if offline is a project guarantee) | Critical only if offline is a project guarantee |
| Local component state used in a component that fetches data | Should use the documented state management pattern, not local state |
| Model class without value-equality (hand-written equality) | Hand-written equality is error-prone |
| Ad-hoc `print`/`console.log` for logging | Must use structured logger |
| Unsafe null-assertion / force-unwrap without an explanatory comment | A crash waiting to happen |
| New component with no test | Testing requirement — no exceptions |
| New `if` branch with no test for the new path | Test gap — every branch needs a test |
| A doc/config file that must be kept in sync with another, modified alone | Paired files must be updated together |

---

## Required Outputs

### "NOT in Scope" Section

Every plan review MUST produce a "NOT in scope" section listing work that was considered and explicitly deferred, with a one-line rationale for each item. Example:

```
NOT IN SCOPE:
- Image compression before upload — deferred until we measure actual storage costs
- Pagination for the item list — deferred; current datasets have <100 items
- Production-API adapter for TaskRepository — deferred until the API contract is finalized
```

### "What Already Exists" Section

List existing code that already partially solves sub-problems in this plan. Note whether the plan reuses or unnecessarily rebuilds it. Example:

```
WHAT ALREADY EXISTS:
- AttachmentRepository interface + backend implementation — use for all attachment persistence
- SyncService.queueWrite() — use this for offline queueing, don't build a new queue
- ConfigDrivenForm renderer — use for any new dynamically-configured field, don't create a separate form
- RatingInput component — already built, reuse in any assessment screen
```

### Failure Modes

For each new codepath from the Section 3 diagram, list:
1. One realistic way it could fail in production (timeout, null reference, race condition, device storage full, auth expiry, local store locked, etc.)
2. Whether a test covers that failure
3. Whether error handling exists for it
4. Whether the user would see a clear error or a silent failure

If any failure mode has no test AND no error handling AND would be silent to the user — flag it as a **CRITICAL GAP**.

Example:
```
FAILURE MODES:
Codepath: TaskRepository.completeTask() → offline queue write
  Failure: Device storage full — local write fails
  Test: NO
  Error handling: NO
  User sees: Silent failure — task appears complete but is lost
  → CRITICAL GAP: add try/catch, show "Storage full" error, prevent optimistic UI update
```

### Task Verification Steps

Every task in the final plan MUST include a Verify line — a concrete, executable check that confirms the task is done correctly.

Format:
```
Task 3: Add completeTask() to TaskRepository
  Files: src/repositories/task_repository,
         src/adapters/backend_task_repository,
         test/adapters/backend_task_repository_test
  Verify: In the task list, tap Complete on a task → task shows completed state →
          switch to airplane mode, repeat → task shows optimistic completion,
          queued item visible in sync queue → go back online → queue flushes,
          task row updated in the backend
```

Verification steps must be:
- **Observable** — describe what to see/check, not what was coded
- **Specific** — "task shows completed state" not "it works"
- **Reproducible** — another developer or QA tester could follow the step and confirm pass/fail
- For pure refactoring: `Verify: {{TEST_CMD}} — all existing tests pass, no behavior change`

### TODOS.md Updates

After all review sections are complete, present each potential TODO individually. Never batch TODOs. For each TODO describe:
- **What:** One-line description of the work
- **Why:** The concrete problem it solves or value it unlocks
- **Pros:** What you gain by doing this work
- **Cons:** Cost, complexity, or risks
- **Context:** Enough detail for someone picking this up in 3 months — current state, motivation, where to start
- **Depends on / blocked by:** Any prerequisites

Options for each: **A)** Add to docs/todos.md **B)** Skip — not valuable enough **C)** Build it now instead of deferring.

### Diagrams

The plan itself should include ASCII diagrams for:
- Navigation flow for new screens (which screens transition to which)
- Data flow through the data-access layer for new entities
- Offline sync state machine for new write paths
- Any non-trivial component state machine (e.g., a capture/upload flow)

Additionally, identify which implementation files should receive inline ASCII diagram comments.

### Completion Summary

At the end of the review, display:
```
PLAN REVIEW COMPLETE
────────────────────────────────────────────
Step 0: Scope Challenge        User chose: ___
Architecture Review:           ___ issues found
Code Quality Review:           ___ issues found
Test Review:                   diagram produced, ___ gaps identified
Performance Review:            ___ issues found
────────────────────────────────────────────
NOT in scope:                  written
What already exists:           written
TODOS.md updates:              ___ items proposed
Failure modes:                 ___ CRITICAL GAPS flagged
Red flags:                     ___ flagged
────────────────────────────────────────────
```

---

## How to Ask Questions

Every issue presented to the user MUST:
1. Present 2–3 concrete lettered options
2. State which option is recommended, first, as a directive ("Do B. Here's why:") — not "Option B might be worth considering"
3. Explain in 1–2 sentences why that option over the others, referencing the engineering preferences above
4. One issue per question — no batching

Label options with issue number + option letter (e.g., "Issue 3A", "Issue 3B") to avoid confusion across multiple rounds.

**Escape hatch:** If a section has no issues, say so and move on. If an issue has an obvious fix with no real alternatives, state what will be done and move on — don't waste a question on it.

---

## Unresolved Decisions

If a decision is skipped or left open, note it explicitly. At the end of the review, list all unresolved decisions as "Unresolved decisions that may bite you later." Never silently default to an option.

---

## Retrospective Check

Before starting the review, check the git log for the branch. If there are prior commits suggesting a previous review cycle (refactors, reverts), note what was changed and whether the current plan touches the same areas. Be more aggressive reviewing areas that were previously problematic.

```bash
git log --oneline -10
git diff origin/main --stat
```

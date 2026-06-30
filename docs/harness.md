# Multi-Agent Development Harness

> Generator-Evaluator architecture for autonomous, agent-driven software development.
> Inspired by [Anthropic's harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps).

This is a **language- and stack-agnostic template**. Wherever you see `{{LINT_CMD}}`, `{{TEST_CMD}}`, or `{{FORMAT_CMD}}`, substitute the commands for your own toolchain. Structural checks shown as tables are **examples from one project** — replace them with the architectural rules that matter for your stack.

---

## How This Works In Practice

You use **your IDE + coding agent** (e.g. a coding-agent CLI such as Claude Code) for everything. The "multi-agent" pattern is implemented as **two prompting modes within the same tool** — not two separate tools.

```
┌─────────────────────────────────────────────────────────────┐
│  YOUR IDE + CODING AGENT                                    │
│                                                             │
│  Mode 1: GENERATE                                           │
│    "Build the feature per the sprint contract               │
│     at docs/sprints/[feature].md"                           │
│    → Agent reads project rules, requirements, contract      │
│    → Builds code + tests                                    │
│    → Writes BUILD_SUMMARY.md                                │
│                                                             │
│  Mode 2: EVALUATE                                           │
│    "Evaluate the latest changes against the sprint contract │
│     at docs/sprints/[feature].md.                           │
│     Follow the evaluator criteria in docs/harness.md."      │
│    → Agent reads the criteria                               │
│    → Runs lint + tests                                      │
│    → Checks structural rules, permissions, offline, etc.    │
│    → Outputs APPROVED or FIX LIST                           │
│                                                             │
│  Loop: if FIX LIST → "Fix these issues: [paste fix list]"   │
│        → back to generate mode                              │
│        → re-evaluate                                        │
└─────────────────────────────────────────────────────────────┘
```

**The separation matters even in one tool** because:
- Generate mode is creative — "build this feature, make it work"
- Evaluate mode is critical — "find what's wrong, be skeptical"
- The same model is better at criticism when explicitly asked to criticize than when asked to generate AND self-evaluate simultaneously (the GAN insight from the [Anthropic article](https://www.anthropic.com/engineering/harness-design-long-running-apps))

## Architecture

```
  Intent (you write — a sentence or two)
         │
         ▼
  ┌──────────────┐
  │ PLAN-REVIEW  │──→ drafts & sharpens the Sprint Contract
  │ (automated)  │
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │   GENERATE   │──→ code + BUILD_SUMMARY.md
  │  (prompt 1)  │
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │   EVALUATE   │──→ APPROVED or FIX LIST
  │  (prompt 2)  │
  └──────┬───────┘
         │
    ┌────┴────┐
    │ Issues? │── Yes ─→ "Fix these: [fix list]" ─→ back to GENERATE (max 3)
    └────┬────┘
       No │
         ▼
  ┌──────────────┐
  │  RISK GATE   │── low risk ───→ Merge → CI
  │ (risk tier)  │── high risk ──→ flag for your review → Merge → CI
  └──────────────┘
```

## Roles

### Planner (You)

- Writes the *intent* for each feature (a sentence or two); reviews and approves the sprint contract the harness drafts from it
- Makes architecture decisions when the evaluator flags tradeoffs
- Reviews final output when the risk gate flags it (low-risk changes can merge without a deep review)
- Owns product judgment — "does this feel right for the user?"

### Generator (Coding Agent — generate prompt)

- Reads: requirements doc, project rules, design references, sprint contract
- Builds: screens, components, data adapters, models, tests
- Follows: the project's coding workflow (Plan → Implement → Self-Review)
- Outputs: working code + a `BUILD_SUMMARY.md` describing what was built and how it maps to the sprint contract

### Evaluator (Coding Agent — evaluate prompt)

- Reads: generator output, project rules, code-review workflow
- Runs automated checks (see Evaluator Criteria below)
- Outputs: either a specific issue list (sent back to the generator) or "approved" (ready for merge)
- Never generates new features — only evaluates and identifies gaps

### Quick-Reference Prompts

**Plan (draft the contract from intent):**
```
Here's my intent: [one or two sentences on what you want].
Run the plan-review workflow (workflows/plan-review.md) to turn it into a
sprint contract at docs/sprints/[feature].md: scope challenge, testable
behaviors, failure modes, and what's not in scope. Show me the contract.
```

**Generate:**
```
Build the feature described in docs/sprints/[feature].md.
Follow the project coding workflow. Write tests alongside code.
When done, write a BUILD_SUMMARY.md in docs/sprints/.
```

**Evaluate:**
```
Evaluate the latest changes against the sprint contract at
docs/sprints/[feature].md. Follow the evaluator criteria in
docs/harness.md. Output APPROVED or a numbered FIX LIST with
file:line references.
```

**Fix:**
```
Fix these issues from the evaluator: [paste fix list].
Update BUILD_SUMMARY.md with what was fixed.
```

---

## The Front of the Loop: Intent to a Quality Sprint Contract

The loop's output quality is set *before* generation starts. A vague contract guarantees iterations; a sharp one usually converges in a single pass. So the front of the loop is a real step, not a formality, and it's where you declare intent.

Run `workflows/plan-review.md` to turn intent into the contract:

1. **Declare and pressure-test intent (Step 0, Scope Challenge):** the minimum change that achieves the goal, what already exists (so you don't rebuild), an architecture gate that rejects plans violating your core invariant, and an explicit scope tier with a SCOPE REDUCTION option. Intent isn't just stated, it's challenged.
2. **The plan-review outputs _are_ the sprint contract.** They map directly:

| plan-review output | sprint contract field |
|---|---|
| Testable behaviors with observable Verify steps | Testable Behaviors |
| "NOT in scope" | Not in This Sprint |
| "What already exists" | informs Files; prevents rebuild |
| Failure modes + CRITICAL GAPs | Architecture Constraints / behaviors |
| Per-codepath test coverage | Testable Behaviors / Acceptance |

This closes the loop in both directions. If you skip the front-of-loop work and the loop runs 3+ times, that *is* the signal the contract was underspecified. And when `workflows/debug.md` classifies a failure as **Intent** or **Spec** (not Code), it points right back here: re-plan the contract, don't patch the code. Same discipline, front and back.

**Review lenses (credit).** This harness ships an *engineering* review lens (`workflows/plan-review.md`) plus code review. For changes that warrant it, I also run **product, design, and strategic (CEO-style) plan reviews** using gstack's `plan-eng-review` / `plan-ceo-review` skills, which are gstack's and not included here. The harness is the build loop; those lenses help decide *what* is worth building, not how to build it reliably.

---

## Sprint Contract Template

Before the generator starts any feature, create a sprint contract. This is the "negotiated agreement" between planner, generator, and evaluator.

```markdown
# Sprint Contract: [Feature Name]

## Goal
[1-2 sentences — what the user can do after this is built]

## Files to Create/Modify
- src/[area]/[file] (new)
- src/[area]/[file] (new)
- src/[area]/[file] (modify)
- test/[corresponding tests]

## Testable Behaviors (Evaluator will verify these)
1. [ ] [Specific observable behavior — e.g., "User sees only the items assigned to them"]
2. [ ] [e.g., "Tapping Complete on an item emits a completed event"]
3. [ ] [e.g., "Offline: completing an item queues the action and syncs when back online"]
4. [ ] [e.g., "The action bar renders the expected set of buttons"]
5. [ ] [e.g., "A read-only user sees items but all action buttons are disabled"]

## Architecture Constraints
[Define the structural rules that matter for YOUR stack. Examples:]
- All data access goes through repository/service interfaces
- Permission checks gate all write actions
- Configuration-driven behavior (no hardcoded variants)
- Offline-capable (no blocking network calls in the happy path)

## Not in This Sprint
- [Explicit exclusions to prevent scope creep]

## Acceptance
- {{LINT_CMD}} (your linter / static analysis): zero warnings
- {{TEST_CMD}} (your test suite): all pass
- Evaluator approves all testable behaviors
- Docs updated if new screens or user actions were added
```

---

## Evaluator Criteria

The evaluator runs checks in this order. Any CRITICAL failure sends the code back to the generator with a specific fix list.

### Pass 1 — Automated (CRITICAL — blocks approval)

Run the commands for your stack. Configure each placeholder once:

```bash
# 1. Static analysis / linting — zero warnings
{{LINT_CMD}}

# 2. All tests pass — no skipped tests
{{TEST_CMD}}

# 3. Formatting — no diffs
{{FORMAT_CMD}}
```

### Pass 2 — Structural Review (CRITICAL — blocks approval)

The evaluator runs structural checks that enforce **your project's architecture**. The table below shows **example checks from one project** (a layered app with a repository/adapter pattern over a swappable backend). **Define the structural rules that matter for your stack** — these are illustrative, not prescriptive.

| Example Check | How to Verify | Failure = |
|-------|--------------|-----------|
| Repository pattern | Grep for direct backend-client imports outside the adapter layer (e.g. `src/adapters/`) | CRITICAL |
| Backend-type leakage | Grep for backend-specific types in UI / view / service layers | CRITICAL |
| Hardcoded IDs | Grep for UUID/ID literals outside test files and seed data | CRITICAL |
| Offline breaking | Any `await` on a network call without a try/catch + local fallback | CRITICAL |
| Permission check | Any write action without a permission-service guard | CRITICAL |
| Config-driven behavior | Any hardcoded variant logic that should be read from configuration | CRITICAL |
| Authorization at the data layer | Row-level / record-level access rules are enforced and tested | CRITICAL |

> The point of Pass 2 is that the evaluator mechanically enforces the architecture decisions you care about, so they don't erode one PR at a time. Write the grep/check that catches the violation, then list the rule here.

### Pass 3 — Behavioral Verification (CRITICAL — blocks approval)

For each testable behavior in the sprint contract:

1. Check that a test exists that exercises the behavior
2. If the behavior involves access scoping: verify the test runs as the correct user/role
3. If the behavior involves offline: verify the test simulates offline (no network) and the action still succeeds locally

### Pass 4 — Quality Review (INFORMATIONAL — non-blocking)

| Check | Notes |
|-------|-------|
| DRY violations | Duplicated code blocks > 10 lines |
| Component size | Any component / module past your size budget → suggest extraction |
| Naming clarity | Would a new contributor understand this without reading the implementation? |
| Theme / token compliance | Uses design tokens, not hardcoded values |
| Responsive layout | Layouts tested at the form factors you support |
| Theming | Light + dark (or all supported themes) render correctly |
| Voice / tone | Error messages, empty states, confirmations follow the project's tone guide |

### Pass 5 — Sprint Contract Verification

Go through each testable behavior in the sprint contract and mark pass/fail:

```
SPRINT CONTRACT VERIFICATION — [Feature Name]

✅ 1. User sees only the items assigned to them
✅ 2. Tapping Complete emits a completed event
❌ 3. Offline: completing an item queues the action — TEST MISSING
✅ 4. Action bar renders correctly
✅ 5. Read-only user sees disabled buttons

RESULT: 1 issue found → send back to generator
FIX LIST:
- Add test: test/[area]/sync_queue_test — verify the completed action is queued when offline
- Verify the sync queue's enqueue path is called in the complete action handler
- Update user docs if the sprint added new user-facing screens or actions
```

---

## Feedback Loop Protocol

### When Evaluator Finds Issues

The evaluator produces a **fix list** — not vague feedback, but specific files, line numbers, and what needs to change.

```markdown
## Evaluator Fix List — [Feature Name] (Iteration 2)

### CRITICAL (must fix before re-evaluation)
1. **Repository violation** — `src/screens/detail_screen:47`
   Direct backend-client call. Must use the repository/service interface instead.

2. **Missing permission check** — `src/components/action_bar:23`
   Complete button is always enabled. Must wrap with a permission-service guard.

3. **Missing test** — no test for offline completion queueing
   Create `test/services/sync_queue_test` with: enqueue completed action → verify queue has 1 item → simulate online → verify event emitted.

### INFORMATIONAL (fix if easy, otherwise defer)
4. DetailScreen is past the size budget — consider extracting Header and Checklist sub-components.
```

### Generator Response

The generator:
1. Reads the fix list
2. Applies each fix
3. Runs `{{LINT_CMD}}` + `{{TEST_CMD}}` locally
4. Outputs an updated `BUILD_SUMMARY.md` noting what was fixed
5. Submits for re-evaluation

### Max Iterations

- **3 iterations max** per sprint contract
- If the evaluator still finds CRITICAL issues after 3 rounds, escalate to the planner (you) for a decision
- Common reason for 3+ iterations: the sprint contract was underspecified — fix the contract, not the loop

---

## Evaluation Tiers

The level of review scales with the risk of the change. **Default to the lightest tier that fits.**
Using a heavier tier than needed burns tokens without proportional quality gain.

```
Risk        ──────────────────────────────────────────────►
            DIRECT BUILD         SELF-REVIEW         FULL HARNESS
Cost        $                    $$                   $$$
Evaluator   none                 inline (same ctx)    subagent (new ctx)
```

### Tier 1 — Direct Build (bug fixes, ≤2 files)
**When:** Bug fix, copy change, config tweak, or any change where the scope is obvious and small.
**Flow:** Build → `{{LINT_CMD}}` + `{{TEST_CMD}}` + `{{FORMAT_CMD}}` → commit.
**No evaluator.** The automated checks are sufficient.

### Tier 2 — Self-Review (standard features, 3-8 files)
**When:** New screens within established patterns, adding components, wiring existing providers/services. Sprint contract has ≤8 testable behaviors. No new architectural patterns.
**Flow:** Generator builds → runs automated checks inline (same context) → runs structural checks inline → writes BUILD_SUMMARY → commit.
**Key difference from Tier 3:** The generator self-evaluates using the evaluator criteria (Pass 1-5 from this doc) without spawning a separate agent. This saves the token cost of a subagent re-reading the same files.

**Self-review checklist (run inline before committing):**
```bash
# Automated (CRITICAL)
{{LINT_CMD}}
{{TEST_CMD}}
{{FORMAT_CMD}}

# Structural (CRITICAL) — your project's rules, checked inline
# - No backend-client imports outside the adapter layer
# - No hardcoded IDs outside test/
# - No backend types in UI/view/service layers
# - Permission guards on write actions

# Contract (CRITICAL)
# - Walk through each testable behavior, verify test or implementation exists
```

### Tier 3 — Full Harness (architecture changes, 8+ files, new patterns)
**When:** New interfaces, new navigation patterns, new adapter types, schema-touching changes, offline/sync flow changes, or any sprint that introduces patterns other sprints will copy.
**Flow:** Generator builds → Evaluator subagent reviews (fresh context, skeptical) → Fix loop (max 3) → commit.
**Why the subagent matters here:** Architecture changes have cascading consequences. A separate evaluator context eliminates self-evaluation bias on structural decisions that affect the entire codebase.

### Tier Selection Guide

| Signal | Tier |
|--------|------|
| 1-2 files, no new abstractions | **Tier 1** — Direct Build |
| New screen using existing components/providers | **Tier 2** — Self-Review |
| Filling in placeholder content (wiring an existing view/picker) | **Tier 2** — Self-Review |
| New component used by multiple screens | **Tier 2** — Self-Review |
| New repository interface or adapter | **Tier 3** — Full Harness |
| New navigation pattern (shell routes, deep links) | **Tier 3** — Full Harness |
| Changes to sync engine, event emitter, or offline flow | **Tier 3** — Full Harness |
| Sprint introduces patterns other sprints will copy | **Tier 3** — Full Harness |

**When in doubt, start at Tier 2.** Escalate to Tier 3 only if you realize during the build that you're making architectural decisions.

---

## Sprint Contract Example

A single, fully-generic example. Adapt the behaviors and constraints to your own feature.

```markdown
# Sprint Contract: Task List Feature

## Goal
A user can see their assigned tasks grouped by category, with an action bar to act on each task.

## Files
- src/screens/tasks/task_list_screen (new)
- src/components/tasks/task_card (new)
- src/components/tasks/action_bar (new)
- test/components/tasks/task_card_test (new)
- test/components/tasks/action_bar_test (new)

## Testable Behaviors
1. [ ] A user sees only the tasks assigned to them
2. [ ] Tasks are grouped under a category header
3. [ ] Each task shows: name, due date, category
4. [ ] The action bar renders the expected buttons (e.g. Complete, Flag, Attach, Notes)
5. [ ] A read-only user sees tasks but the action bar is hidden
6. [ ] Secondary details are collapsed by default, expandable on tap
7. [ ] All supported themes (e.g. light + dark) render correctly

## Architecture Constraints
- All data access goes through a repository/service interface
- A permission service gates the action bar by role
- Offline-capable: no blocking network calls in the happy path

## Not in This Sprint
- Task completion logic (just the UI in this sprint)
- Offline sync queue
- Print/export
```

---

## Running the Harness

All in one coding-agent session inside your IDE.

### Step 1: Write the Intent, Let the Harness Draft the Contract (You + Plan-Review)

1. Write your *intent* — a sentence or two on what you want.
2. Run the plan-review workflow (`workflows/plan-review.md`) to turn that intent into a sprint contract at `docs/sprints/[feature-slug].md`: scope challenge, testable behaviors with Verify steps, failure modes, and what's not in scope.
3. Review and approve the drafted contract. This is the one place your judgment shapes the loop; everything downstream runs against it. (See "The Front of the Loop" above.)

### Step 2: Generate (Prompt the Coding Agent)

Prompt:
```
Build the feature described in docs/sprints/[feature-slug].md.
Follow the project coding workflow. Write tests alongside code.
When done, write docs/sprints/[feature-slug]-BUILD_SUMMARY.md.
```

The coding agent will:
1. Read the project rules (e.g. an AGENTS.md / CLAUDE.md / project conventions doc)
2. Read the requirements doc (full requirements)
3. Read the sprint contract (specific scope)
4. Follow the mandatory coding workflow (Plan → Implement → Self-Review)
5. Build the feature + tests
6. Write BUILD_SUMMARY.md:
   ```markdown
   # Build Summary: [Feature]
   ## What was built
   - [file]: [what it does]
   ## Sprint contract coverage
   1. ✅ [behavior] — implemented in [file:line]
   2. ✅ [behavior] — tested in [test file]
   ## Known gaps
   - [anything not covered]
   ```

### Step 3: Evaluate (Prompt the Coding Agent — new context)

Start a **new agent session** (or clearly switch context) and prompt:
```
Evaluate the latest changes against the sprint contract at
docs/sprints/[feature-slug].md. Follow the evaluator criteria
in docs/harness.md. Output APPROVED or a numbered FIX LIST with
file:line references.
```

**Why a new session?** The GAN insight: a model that just generated code has self-evaluation bias. A fresh context with the evaluator prompt is more skeptical. Same model, different role.

The coding agent will:
1. Read the project rules + sprint contract + BUILD_SUMMARY.md
2. Run Pass 1-5 (automated checks + structural + behavioral + quality + contract verification)
3. Output: **APPROVED** or **FIX LIST** or **ESCALATE**

### Step 4: Fix (If Needed)

If the evaluator outputs a fix list, prompt (in the generate session or a new one):
```
Fix these issues from the evaluator:
[paste the fix list]
Update docs/sprints/[feature-slug]-BUILD_SUMMARY.md with fixes.
```

Then re-evaluate (Step 3). Max 3 iterations.

### Step 5: Risk Gate, then Merge

When the evaluator outputs APPROVED, the risk tier decides whether a human is needed before merge. This is the same risk tiering that sets evaluation depth, now applied to the human-in-the-loop decision: your attention is spent only where the risk warrants it.

- **Low risk (Tier 1-2)** — bug fixes, standard features within established patterns. The automated checks plus the evaluator pass are sufficient; it can merge without a deep human review.
- **High risk (Tier 3)** — architecture changes, new patterns, data migrations, anything other work will copy. The harness flags it for *your* review before merge: you check the diff for UX, product fit, and architectural consequence.

1. Risk gate classifies the change (see Evaluation Tiers).
2. High risk → you review the diff; low risk → proceed.
3. Merge to main; CI runs automatically.
4. Tag for deploy when ready.

---

## File Structure

The harness owns the `docs/sprints/` and (optionally) `docs/workflows/` conventions. Everything else is yours.

```
docs/
├── harness.md            ← this file
├── sprints/              ← sprint contracts + build summaries
│   ├── task-list.md
│   ├── task-list-BUILD_SUMMARY.md
│   └── ...
└── workflows/            ← evaluator reference (optional)
    ├── plan-review.md
    ├── code-review.md
    └── debug.md
```

---

## Token Efficiency

Tokens burn on context loading, not generation. The biggest lever is **not loading context you don't need**.

### Cost Per Tier

> The numbers below are **illustrative measurements from one project** (a single non-trivial "navigation" sprint), not universal constants. Measure your own; the *shape* — Tier 3 costs several times more than Tier 2 — is the durable lesson.

| Tier | Evaluate cost | Total context estimate | When |
|------|--------------|----------------------|------|
| **Tier 1** — Direct Build | 0 (no evaluator) | ~5-10K | Bug fixes |
| **Tier 2** — Self-Review | 0 (inline checks) | ~30-50K | Standard features |
| **Tier 3** — Full Harness | ~100K (subagent) | ~100-150K | Architecture changes |

In one measured Tier 3 sprint, the full run consumed ~140K+ tokens across explore + generate + evaluate subagent + fix. A Tier 2 self-review would have caught 3 of the 4 evaluator issues (formatting, a missing test file, a missing data row) at ~40K tokens — roughly a 3x savings.

The one issue Tier 2 might have missed required the evaluator to compare the contract's behavioral spec against the implementation line-by-line — exactly what a skeptical second pass is good at. That is the case for reserving the heavier tier.

### Rules for Usage Efficiency

1. **Use a code-intelligence/LSP tool before reading files.** A "symbols overview" call returns ~100 tokens vs ~2000 for reading the file. For discovery (what methods exist? who calls this?), start there. Only read full files when you need the implementation detail.
2. **Sprint contracts are self-contained.** Include everything the generator needs inline. Don't reference external docs — that triggers file reads.
3. **Don't spawn explore agents for known codebases.** If you've already read the architecture (this session or recent sessions), use targeted search calls instead. An explore agent reads 30+ files by design.
4. **Fix context is minimal.** The fix list is the entire context — no re-reading the project.
5. **3 iteration max.** If it's not right after 3 loops, the sprint contract needs work, not more iterations.
6. **Pre-built components reduce output tokens.** A shared component invoked in 1 line beats hand-building the same thing in 80.
7. **Default to Tier 2.** When the evaluator subagent confirms what was already correct ~90% of the time, reserve it for architecture changes where the ~10% matters most.

### Parallel Execution for Speed

Run multiple sprint contracts simultaneously on separate branches:

```bash
# Create branches
git checkout -b feat/task-list
git checkout main
git checkout -b feat/mode-selector
git checkout main
git checkout -b feat/project-tasks

# Run in parallel (each on its own branch)
git checkout feat/task-list    && ./scripts/harness.sh docs/sprints/task-list.md &
git checkout feat/mode-selector && ./scripts/harness.sh docs/sprints/mode-selector.md &
git checkout feat/project-tasks && ./scripts/harness.sh docs/sprints/project-tasks.md &
wait
```

Three features running simultaneously, each on its own branch. Merge when each is approved. (Per-feature cost depends on tier and stack — see the illustrative figures above.)

---

## When to Evolve the Harness

Per the [Anthropic article](https://www.anthropic.com/engineering/harness-design-long-running-apps): *"Every component encodes an assumption about what the model can't do on its own."*

Review the harness periodically:
- If the generator consistently passes Pass 2 (structural review) on first try → consider making Pass 2 informational instead of critical
- If the evaluator consistently finds the same issue → add it to your project rules doc so the generator avoids it
- If 3-iteration loops happen frequently → the sprint contracts need more detail, not more iterations
- If the evaluator rarely finds issues → increase the autonomy level (lighter tier) for that feature type

The harness should get lighter over time, not heavier. The goal is that the generator internalizes the quality bar and the evaluator becomes a safety net, not a gatekeeper.

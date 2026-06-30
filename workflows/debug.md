# Debug Workflow

> Structured 4-phase debugging process. Use when a bug is reported, a test fails unexpectedly, or behavior doesn't match expectations. Prevents ad-hoc thrashing by enforcing: reproduce → hypothesize → isolate → fix.
>
> This document is standalone. Any AI agent or human contributor can follow it without external tooling.

---

## Core Rule

**Do not skip phases.** Each phase narrows the search space for the next. If you catch yourself guessing or trying random fixes, stop and return to Phase 1. The most common debugging failure mode is jumping to Phase 4 from a hunch formed in Phase 2.

---

## Phase 1: Reproduce

**Goal:** Confirm the bug exists and establish a reliable reproduction before touching any code.

1. **Get the symptom.** What exactly is wrong? An exception with a stack trace, wrong UI state, missing data, a crash, a failed network operation, behavior that differs by environment or connectivity? Write it in one sentence.

2. **Reproduce it.** Run the failing test, trigger the flow, simulate the condition — whatever makes the bug visible. If you cannot reproduce it:
   - Ask for the platform/environment (OS, device, browser, runtime version)
   - Ask for the configuration in use (which feature flags, settings, or input data)
   - Ask whether the issue appears under specific conditions only (online vs. offline, first run vs. warm cache, specific user/role)
   - Do NOT proceed to Phase 2 without a reproduction

   **Interaction bugs ("can't tap/click X" / event not firing / wrong element receives the input):** the reproduction is a **failing test that performs the real interaction** and asserts the expected effect — NOT reading the component/element tree. **Reading code to reason about event routing or hit-testing is a hypothesis (Phase 2), not a reproduction.** Hit-test/overlay bugs are nearly impossible to reason out by inspection (e.g. a transparent layer silently absorbs clicks; an overlay eats a fall-through). Write the minimal reproduction first; once it fails, you can bisect layers in minutes instead of guessing for rounds. If the test framework warns that the interaction "would not hit the specified element," dump the element's geometry/bounds and the hit result to find the absorber. (See `lessons.md` if your project keeps one.)

3. **Establish the baseline.** What is the expected behavior? What actually happens? Note both explicitly.

4. **Check recency.** When did this last work?
   ```bash
   git log --oneline -10 -- <affected-file>
   git blame <affected-file>
   ```
   Look for recent changes to: the affected view/screen, the relevant data-access layer, the sync/background-job logic, or the relevant model.

**Output:**
```
BUG: [one-line description]
Expected: [what should happen]
Actual: [what happens instead]
Reproducible: yes / no / intermittent
Platform/environment: [OS / device / browser / all]
Configuration: [flags / settings / input data, if relevant]
Conditions: [online only / offline only / both / specific state]
Last known good: [commit or date if known]
```

**Do NOT proceed to Phase 2 until you can reliably trigger the bug.**

---

## Phase 2: Hypothesize

**Goal:** Form 2–3 specific hypotheses about what's causing the bug. Not vague ("something's wrong with the sync") — specific ("the write-queue call is persisting the record with a null owner id because the session context isn't initialized when called from a background worker").

For each hypothesis:
1. State the hypothesis in one sentence
2. Name the specific file(s) and function(s) you suspect
3. Describe one quick check that would confirm or eliminate it

**Prioritize hypotheses by:**
- What changed recently (git log from Phase 1)
- The simplest explanation: data issue > mapping bug > logic error > race condition > platform-specific behavior
- Proximity to the symptom: start at the error, work backward through the call chain (UI → service → data-access interface → adapter → backend/local store)

**Common hypothesis categories to consider:**

| Category | Common causes |
|----------|--------------|
| **Architecture/boundary violation** | Code reaching past an abstraction layer (calling the backend directly, bypassing the interface) |
| **Conditional branch** | Bug only in one state (online/offline, authenticated/anonymous, feature-flag on/off) — check that branch's logic |
| **Local store / cache mapping** | Data written but a field is missing, null, or the wrong type in the local schema |
| **Configuration-driven behavior** | Wrong config applied, element rendered when it shouldn't be, required element missing |
| **Adapter / serialization mapping** | Backend row → internal model translation dropping or misinterpreting a field (e.g. snake_case vs. camelCase) |
| **Concurrency / write conflict** | Last-write-wins or server-wins conflict resolution applied incorrectly |
| **Auth/session** | Token expired mid-operation, user context null in a background operation |
| **Platform difference** | Bug only on one OS/runtime — check platform-specific APIs, file path differences, permission flows |
| **State management** | View rebuilding with stale data, store not notifying listeners, state not reset between sessions |
| **Async resource pipeline** | Resource (file, upload, image) captured but not persisted locally before an async operation, queued but its local reference lost |

**Output:**
```
Hypothesis 1: [specific claim] → Check: [how to confirm/eliminate]
Hypothesis 2: [specific claim] → Check: [how to confirm/eliminate]
Hypothesis 3: [specific claim] → Check: [how to confirm/eliminate]
```

**Do NOT start fixing anything yet.**

---

## Phase 3: Isolate

**Goal:** Eliminate hypotheses until one remains.

For each hypothesis, run the check you described in Phase 2. Record: confirmed, eliminated, or inconclusive. If inconclusive, design a more targeted check.

**Techniques:**

**Binary search through the data flow.** Most apps move data through a predictable pipeline. Check at the midpoint:
```
View calls service method
       │
       ▼ ← Is the input correct here?
Service calls data-access interface
       │
       ▼ ← Is the data correct here?
Adapter calls backend / reads local store
       │
       ▼ ← Is the data correct here?
Data written to backend or queue
```
Add targeted, clearly-tagged debug logging at the boundaries (e.g. a `[DEBUG phase3]` prefix). Remove after.

**Minimal reproduction.** Strip away everything that isn't needed:
- Does the bug happen with hardcoded data instead of real backend data?
- Does the bug happen in a unit test for the adapter alone?
- Does the bug happen with 1 record instead of many?
- Does the bug happen when the adapter is mocked?

**Check assumptions about the actual data.** Read the actual stored record — don't assume what it contains. Inspect the backend row or local-store record directly, or add temporary logging to capture the raw response.

**Check platform-specific behavior:**
- Does the bug reproduce on one OS/runtime but not another?
- Does it reproduce on one form factor but not another? (Could be a layout constraint causing something not to render, not a data bug)
- Does it appear only in a release/optimized build, not a debug build? (Could be optimizations, stripped assertions, or removed logging)

**Check conditional state specifically:**
- Trigger the bug in the suspect state (e.g. offline / flag-on) → verify behavior
- Trigger the same flow in the opposite state → verify behavior
- If one works and the other doesn't: the bug is in that branch's logic in the adapter or service

**Check auth state:**
- Does the bug reproduce with a fresh login? (Rules out a stale token)
- Does the bug reproduce after the session has been idle long enough to expire? (Token expiry)

**Output:**
```
Hypothesis 1: ELIMINATED — [what the check showed]
Hypothesis 2: CONFIRMED — [evidence]
Hypothesis 3: ELIMINATED — [what the check showed]

Root cause: [specific file, function/method, and what it does wrong]
```

**If all hypotheses are eliminated:** Return to Phase 2 with new hypotheses informed by what you learned. Do NOT guess.

**If after two full rounds of Phase 2 + 3 you still have no confirmed hypothesis:** Escalate — see "When to Escalate" below.

---

## Phase 4a: Classify the Failure

**Before writing a single line of fix code**, classify the failure. This determines the right response — not every bug is a code change. This classification is the most valuable habit in the workflow: it stops you from coding a fix for a problem that lives in the requirements or the spec.

| Classification | Signal | Response |
|---------------|--------|----------|
| **Intent issue** | The feature works as coded but doesn't match what the user actually needs. The bug is in requirements, not implementation. | Stop. Go back to the product requirements / the issue / the spec doc. Re-plan the feature. Do not write code. |
| **Spec issue** | The plan or acceptance criteria were wrong or incomplete. The code faithfully implements a flawed spec (missing edge case, wrong assumption about behavior, incorrect configuration assumption). | Fix the spec first (update the plan, the issue, or the spec doc), then fix the code to match. Don't patch code around a bad spec. |
| **Code issue** | The plan was right, the spec is correct, the implementation has a bug. | Standard fix — proceed with Phase 4b below. |

Present the classification:
```
Failure classification: [INTENT / SPEC / CODE]
Evidence: [why this classification]
Recommended response: [what to do]
```

If **INTENT** or **SPEC**, ask before proceeding — the fix may be larger than a code change.

---

## Phase 4b: Fix

**Goal:** Fix the root cause, verify the fix, prevent regression.

1. **Fix the root cause.** Change the minimum code needed. Do not refactor adjacent code, clean up unrelated issues, or "improve" things while here. One bug, one fix, one commit.

2. **Verify the fix.** Re-run the reproduction from Phase 1 exactly. Does the expected behavior now occur? Test both branches if the bug was conditional (e.g. online and offline cases).

3. **Check for collateral damage.** Run the full test suite and the linter:
   ```bash
   {{TEST_CMD}}
   {{LINT_CMD}}
   ```
   If tests fail that weren't failing before, the fix has a side effect — investigate before proceeding.

4. **Add a regression test** if one doesn't already exist. The test should:
   - Fail without the fix
   - Pass with the fix
   - Live in the appropriate test directory for its layer (adapter, service, view, integration)
   - For conditional bugs: simulate the condition (e.g. mock the adapter into an offline state) and verify correct behavior

5. **Remove debug artifacts.** Delete all temporary debug logging and hardcoded values added during isolation.

6. **Apply a red-flag check on the fix.** Before committing, verify the fix does not:
   - Reach past an abstraction boundary (e.g. add backend calls outside adapter files)
   - Hardcode any IDs or environment-specific values
   - Break a supported branch (e.g. offline behavior)
   - Introduce untested branches
   - Skip the project's state-management or architectural pattern
   - Leave stray logging/print statements

**Output:**
```
Fix: [what was changed and why]
Files modified: [list]
Verified: [reproduction from Phase 1 now produces expected behavior]
Branch A (e.g. online): [pass / N/A]
Branch B (e.g. offline): [pass / N/A]
Tests: {{TEST_CMD}} [pass/fail count], new regression test added: yes/no
{{LINT_CMD}}: zero warnings: yes/no
```

---

## Example Debugging Scenarios

These are generic patterns. Adapt the layer names to your project's architecture.

### Bug: Feature works in one state but fails in another (e.g. online vs. offline)

Start at the adapter / boundary layer. A well-structured data-access layer should handle each supported state explicitly. Check:
- Is the alternate path actually implemented, or does it just rethrow the primary path's error?
- Is the write-queue / fallback mechanism being invoked in the alternate state?
- Is the local-store schema correct for this entity (all required fields present, correct types)?

### Bug: Data appears correct in the backend but wrong in the app

The bug is almost certainly in the adapter's mapping logic. Check:
- The map-from-row (deserialization) method in the relevant adapter
- Are all fields being mapped? Is any field null-coalesced incorrectly?
- Are field names correct? Backends often use a different casing convention than internal models.
- Is a required field being dropped silently (mapped to null instead of throwing)?

### Bug: A configuration-driven form/view shows the wrong elements

The bug is in the configuration-driven rendering. Check:
- What configuration is loaded for this context?
- Is the renderer receiving the correct config object?
- Is the element definition in the config correct for this case?
- Is there a hardcoded conditional somewhere overriding the config?

### Bug: An async resource (photo, file, upload) is missing or lost after a sync

Check the pipeline in order:
1. Is the resource written to local storage immediately after capture, before any async upload?
2. Is the local reference (path/id) stored alongside the record?
3. Is the read path mapping the local reference correctly while offline?
4. Is the upload target path correct and consistent with the reference stored on the record?
5. Is the upload marked complete in the queue only after successful server confirmation?

### Bug: App crashes on cold start or after returning from background

Check:
- Auth token — is it refreshed on resume?
- Local store — is the database opened before any read/write is attempted?
- Session context — are required context values available before any view that needs them renders?
- State management — is state restored correctly after the process is killed and relaunched?

### Bug: Behavior differs on one platform only

Common causes:
- File path format differences (separators, case sensitivity)
- Permission flows (camera, storage, location) differ significantly between platforms
- Keyboard/input and layout insets behave differently per platform
- Underlying library behavior differences (check the dependency's issue tracker for platform quirks)
- System APIs (theme detection, etc.) differ

Use platform simulators/emulators to isolate. Add a platform guard only as a last resort, after verifying the root cause is genuinely platform-specific.

### Bug: Data appears stale after a sync

Check:
- Is the UI reading from the local cache and not refreshing after a successful sync?
- Is the sync layer updating the local record after pulling from the backend?
- Is the state-management layer notifying listeners after the cache is updated?
- Is the conflict-resolution logic (last-write-wins, server-wins) applying correctly?

---

## Anti-Patterns — Stop If You're Doing These

- **Shotgun debugging:** Changing multiple things at once hoping one works. Go back to Phase 3.
- **Fixing the symptom, not the cause:** Adding a null check without understanding why the value is null. Go back to Phase 3.
- **Expanding scope:** "While I'm in here, let me also fix..." No. File a separate issue. Fix only the confirmed bug.
- **Skipping reproduction:** "I think I see the problem." Doesn't matter — prove it first. Go back to Phase 1.
- **Guessing after two failed attempts:** If your first two hypothesis rounds were wrong, stop and re-examine your assumptions. The bug is not where you think it is.
- **Fixing conditional bugs without a matching test:** If the bug was offline (or flag-gated, or role-specific), the regression test must simulate that condition. A test that only runs the default path doesn't prevent regression.

---

## When to Escalate

Ask the user before proceeding if:
- All hypotheses have been eliminated with no new leads
- The reproduction only fails intermittently (suggests a race condition or timing issue — concurrency between a background sync queue and foreground writes is a common source)
- The root cause is in a third-party package
- The bug appears only on a physical device, not a simulator, and you lack device access
- The fix would require a schema change or a change owned by another team/repo (a dependency you cannot satisfy from here)

Present what you've learned and exactly where you're stuck. Don't keep pushing in the wrong direction.

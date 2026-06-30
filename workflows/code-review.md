# Code Review Workflow

> Pre-landing PR review. Analyzes the branch diff against main for structural issues that automated tests don't catch: data-access layer violations, offline-breaking changes, backend leakage, safety issues, and test gaps.
>
> This document is standalone. Any AI agent or human reviewer can follow it without external tooling.
>
> Configure these placeholders for your stack before use:
> - `{{LINT_CMD}}` — static analysis / linter (e.g. `npm run lint`, `cargo clippy`, `flutter analyze`)
> - `{{TEST_CMD}}` — test runner (e.g. `npm test`, `pytest`, `go test ./...`)
> - `{{FORMAT_CMD}}` — formatter (e.g. `prettier --write`, `gofmt`, `cargo fmt`)

---

## Step 1: Check Branch

1. Run `git branch --show-current` to get the current branch.
2. If on `main`, output: **"Nothing to review — you're on main or have no changes against main."** and stop.
3. Run `git fetch origin main --quiet && git diff origin/main --stat` to check if there's a diff. If no diff, output the same message and stop.

---

## Step 2: Get the Diff

Fetch latest main to avoid false positives from a stale local reference:

```bash
git fetch origin main --quiet
git diff origin/main
```

Read the **full diff** before flagging anything. Do not flag issues already addressed elsewhere in the diff.

---

## Step 3: Two-Pass Review

Apply the checklist below in two passes:

1. **Pass 1 (CRITICAL):** the checks your project considers blocking — e.g. data-access layer violations, offline-breaking changes, auth & security
2. **Pass 2 (INFORMATIONAL):** structural issues, test gaps, style/conventions, dead code

---

## Output Format

```
Pre-Landing Review: N issues (X critical, Y informational)

CRITICAL (blocking merge):
- [file:line] Problem description
  Fix: suggested fix

Issues (non-blocking):
- [file:line] Problem description
  Fix: suggested fix
```

If no issues: `Pre-Landing Review: No issues found.`

Be terse. One line for the problem, one line for the fix. No preamble.

---

## Pass 1 — CRITICAL (Blocking Merge)

> The checks in this pass are **example structural checks — define your own for your stack.** They illustrate the kind of blocking invariants worth enforcing in a layered, offline-capable app: a data-access layering rule, an offline/caching guarantee, and auth/security basics. Replace them with whatever is genuinely merge-blocking for your project.

### Data-Access Layer Violations (example structural check — define your own for your stack)

These are the most important checks in the entire review. The data-access layering rule is the single most critical architectural rule in this example project.

- **Direct backend client calls outside adapter files.** Search for raw client calls (queries, RPC, auth, storage) in any file outside your designated adapter directory (e.g. `src/adapters/`). Every hit is a critical violation.
- **Backend-specific types in non-adapter code.** Search for backend client / response-wrapper types in your screens, components, services, and models directories. None of these should appear outside adapters.
- **Backend schema field names leaking into UI or services.** If a raw backend column name appears in a screen or service file, the adapter is not translating to the internal model correctly.
- **New data entity without a data-access interface.** If a new data type is introduced with adapter code but no corresponding abstract interface in your interface layer (e.g. `src/repositories/`), the pattern is broken.
- **Business logic in adapter files.** Adapters should only map data and call the backend. Conditionals, calculations, or business rules in an adapter file should live in a service instead.

### Offline-Breaking Changes (example structural check — define your own for your stack)

Applies if your project has an offline-first or caching guarantee.

- **New write path with no offline queue.** Any method that writes data to the backend must handle the offline case: write to a local queue, return optimistic success, flush when back online. A write that simply throws on network failure breaks offline-first.
- **New read path with no cache fallback.** Any method that reads from the backend must fall back to the local cache when the backend is unreachable. A read that simply throws on network failure breaks offline-first.
- **New feature that requires connectivity.** Define which flows must work fully offline after initial sync (e.g. the core data-capture loop, task completion, file capture and local storage, notes and annotations). Flag any change that makes these fail offline.
- **Files stored only in memory.** Captured files (photos, attachments) must be persisted to local storage immediately after capture. Async upload to remote storage is fine, but the local file must exist before any await.
- **Sync engine bypassed.** New sync logic that doesn't go through your central sync service will create inconsistent queue state. All sync operations should route through the existing sync engine.

### Auth & Security

- **Hardcoded IDs.** Search for hardcoded entity-ID literals (record IDs, tenant IDs, user IDs, etc.) in any source file. These must be derived from session context, not literals.
- **Secrets in source.** Any API key, client key, service credential, or token string literal in source code (not in a gitignored config/secrets file).
- **Auth token not refreshed.** Any new long-running operation (bulk sync, multi-step submit) should handle auth token expiry mid-operation. Failing silently after an expired token is a critical gap.
- **Secrets/config file committed.** Check the diff for any gitignored config or secrets file. It must remain gitignored. If it appears in the diff, stop immediately.

---

## Pass 2 — INFORMATIONAL (Non-Blocking)

### Config-Driven Form / Rendering Violations (example structural check — define your own for your stack)

- **Hardcoded variant checks in components or services.** Any `if (type == 'A')` or `switch (type)` for field visibility in a screen or service. All field visibility must be driven by config objects fed into your dynamic renderer.
- **New dynamically-configured field not in config.** If a new form field is introduced, it must be added to the config definition for the relevant variants — not rendered unconditionally.
- **Dynamic renderer bypassed.** A new screen that renders configured fields outside of the existing dynamic renderer. One form renderer, not many.

### Structural Issues

- **Conditional side effects with inconsistent branches.** A code path that branches on a condition but applies a side effect in only one branch — e.g., a save that attaches a file in the online path but silently skips it in the offline path.
- **Log messages that claim an action happened when it was conditionally skipped.** The log should reflect reality.
- **Magic numbers and strings.** Bare numeric literals (page sizes, timeout durations, thresholds) or string literals used across multiple files. These should be named constants in a dedicated constants file or the theme.
- **One public class/export per file violated.** Multiple public types in a single file (except for small helper types tightly coupled to the primary type).
- **Component exceeds ~150 lines.** Flag for extraction of sub-components.
- **Adapter exceeds its role.** Business logic found in an adapter file — move it to a service.

### Language / Framework Conventions (adapt this list to your stack)

- **Mutable binding used where an immutable one suffices.** Prefer immutable bindings (`const`/`final`/`readonly`); use mutable only when reassignment is needed.
- **Unsafe null-assertion / force-unwrap without explanatory comment.** Every force-unwrap needs a comment proving non-null. Otherwise it's a potential crash.
- **Ad-hoc `print`/`console.log` for logging.** Must use a structured logger (filterable by level).
- **Local component state used in a component that fetches data.** Should use the documented state management approach (per the decision log).
- **Model class without value-equality.** Hand-written equality and hashing are error-prone; prefer your language's idiomatic value-equality.
- **Cheap-rebuild construct missing.** For components that don't depend on runtime state, use the framework's immutable/`const` construct to reduce rebuilds.
- **Named parameters missing.** Any function with more than 2 parameters should use named parameters (where the language supports them).
- **No barrel export updated.** If a new public type was added to a directory that has a barrel/index file, it must be exported from it.

### Dead Code & Consistency

- **Variables assigned but never read.**
- **Imported package never used** — `{{LINT_CMD}}` should catch this, but flag it if visible in the diff.
- **Comments describing old behavior** after the code changed around them.
- **Stale ASCII diagrams in comments** near touched code — check whether any nearby diagrams are now inaccurate.

### Test Gaps

- **New component with no test.** Every new component must have a test. No exceptions.
- **New data-access method with no adapter test.** New methods on an adapter must have tests.
- **New service method with no unit test.** New business logic in a service must have tests.
- **New `if` branch with no test for the new path.** Both sides of every new conditional should be covered.
- **New offline path with no offline simulation test.** Any new online/offline branch must have a test that mocks the adapter to throw and verifies the offline fallback.
- **Negative paths asserted on type/status but not side effects.** A test that verifies a save returns an error is incomplete if it doesn't also verify no local write occurred, no queue entry was created, etc.
- **Security enforcement without an integration test.** Auth checks, permission checks, offline restrictions — all need integration tests verifying the enforcement path works end-to-end, not just unit tests verifying the check exists.

### Performance

- **N+1 data fetches in new list views.** A list that calls a data-access method per item (e.g., loading attachments for each item in a loop) is an N+1. Fetch in bulk or paginate.
- **Images without caching.** New network image loads without an image-caching mechanism.
- **Large lists without pagination.** New lists of variable-length backend data without pagination or virtual scroll.
- **Local-store queries on unindexed columns.** New queries filtering on a high-cardinality key or status field without a corresponding index migration.
- **Bulk operations outside transactions.** Syncing many records to the local store one at a time instead of in a transaction.

### Docs & Sync Consistency

- **Paired files modified independently.** If your project keeps two files in sync (e.g. mirrored agent-instruction files), a PR that modifies one but not the other must be flagged.
- **README not updated.** If the change adds new features, changes setup steps, or alters architecture — the README must reflect it.
- **Decision log not updated.** If the change implements a significant technical decision (state management choice, new dependency, architecture change), it must be added to the project's decision log.

---

## Red Flags — Instant CRITICAL Flag

> **Example structural checks — define your own for your stack.** Replace these rows with the search-for patterns that are genuinely instant-fail for your project; keep the "Pattern / Search For / Violation" shape.

| Pattern | Search For | Violation |
|---------|-----------|-----------|
| Direct backend client call | raw client call outside the adapter directory | Data-access layer broken |
| Backend type in UI | backend client type in a screen or component | Backend leakage |
| Hardcoded ID | entity-ID literal in any source file | Will break in production |
| Secret in source | client key / service credential / API key literal | Security |
| Secrets/config file in diff | gitignored config or secrets file | Credentials exposed |
| Variant hardcoded | `== 'A'` variant check in a screen or service | Config-driven rendering bypassed |
| File not persisted | captured file used before local save confirmed | Data loss if app crashes |
| Ad-hoc logging | `print(`/`console.log(` in any non-test file | Use structured logger |

---

## After Review: Critical Issue Protocol

- If CRITICAL issues found: present all findings, then for each critical issue individually: state the problem, recommended fix, and options (A: Fix now, B: Acknowledge and defer, C: False positive — skip). After all responses, summarize choices. If any A (fix now) chosen, apply the fix.
- If only non-critical issues found: output all findings. No further action needed unless user requests fixes.
- If no issues found: output `Pre-Landing Review: No issues found.`

---

## Important Rules

- **Read the full diff before commenting.** Do not flag issues already addressed elsewhere in the diff.
- **Read-only by default.** Only modify files if the user explicitly chooses "Fix now" on a critical issue. Never commit, push, or create PRs.
- **Be terse.** One line problem, one line fix. No preamble.
- **Only flag real problems.** Skip anything that is fine.

---

## Suppressions — Do NOT Flag These

- Redundancy that aids readability (e.g., an explicit null check before a value a value-equality helper would also handle)
- "Add a comment explaining why this threshold was chosen" — thresholds change, comments rot
- "This assertion could be tighter" when the assertion already covers the behavior
- Consistency-only changes that have no correctness impact
- Harmless no-ops
- Anything already addressed in the diff you're reviewing
- "This component could be extracted" when the component is under 150 lines and the extraction adds no reuse value

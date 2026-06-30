# Agent Development Harness

**Loop engineering for AI coding agents.** The unit of work isn't a prompt, it's a *loop*: **generate → evaluate → fix**, repeated until the change clears an explicit bar. You write a short *sprint contract*, the agent builds against it, a fresh-context evaluator checks it, and the loop iterates, with its depth scaled to the risk of the change.

> **Built on the Generator-Evaluator pattern from Anthropic's [_Harness design for long-running agents_](https://www.anthropic.com/engineering/harness-design-long-running-apps).** The architecture and the "separate the critic from the creator" (GAN-style) insight are theirs. This repo is my own concrete, language-agnostic implementation of it: the sprint-contract format, the tiered evaluation model, the evaluator passes, and the automation.

## Background

This is generalized from a harness I built and used to ship a real production app with coding agents. The stack-specific pieces have been abstracted out so it works for any language or framework; the methodology is exactly what I run.

---

## Loop engineering

The mindset this encodes: stop optimizing single prompts, start engineering the *loop*. The harness is that loop made explicit, instrumented, and tunable.

- **Design the loop** — generate → evaluate → fix, with the evaluator in a *fresh context* so it stays a skeptic instead of rubber-stamping its own work.
- **Bound the loop** — 3 iterations max. If it isn't converging, the sprint contract is underspecified; fix the contract, not the loop.
- **Scale loop depth to risk** — the three tiers below are really three loop depths: no loop (direct build), inline loop (self-review), full loop (separate evaluator).
- **Close the loop** — `unify` reconciles plan vs. actual and logs the decisions made along the way, so nothing dangles.
- **Evolve the loop** — review it periodically. As the model internalizes the bar, the loop should get *lighter*, not heavier.

## The core loop

```
Sprint Contract (you write)
       │
       ▼
   GENERATE ──→ code + BUILD_SUMMARY
       │
       ▼
   EVALUATE ──→ APPROVED  or  FIX LIST (file:line)
       │
   ┌───┴───┐
   │ pass? │── no ──→ FIX ──┐
   └───┬───┘                │
      yes                   └──→ back to GENERATE (max 3 iterations)
       │
       ▼
  you review → merge → CI
```

The key idea (from the Anthropic article): the same model is a better critic when asked *only* to criticize, in a fresh context, than when asked to generate and self-evaluate at once. So evaluation runs as a separate pass.

## Scale review to risk — 3 tiers

Don't pay for a full evaluator on a one-line fix. Default to the lightest tier that fits.

| Tier | When | Evaluation |
|------|------|-----------|
| **1 — Direct Build** | bug fix, ≤2 files, obvious scope | automated checks only |
| **2 — Self-Review** | standard feature, established patterns | agent self-evaluates inline |
| **3 — Full Harness** | architecture change, new patterns | separate skeptical evaluator (fresh context) |

## What's in here

```
docs/harness.md          # the full framework: sprint contracts, tiers, evaluator passes
workflows/
  plan-review.md         # pre-build: scope challenge, architecture, test coverage, failure modes
  code-review.md         # pre-merge: critical (blocks) + informational
  debug.md               # 4-phase debugging + Intent/Spec/Code failure classification
skills/unify/SKILL.md    # loop closure: plan vs. actual, decisions log, deferred tracking
scripts/
  harness.sh             # automated generate→evaluate→fix loop (one sprint)
  run-all-sprints.sh     # run multiple sprint contracts in parallel on branches
```

## Quick start

1. Set your stack's commands (the harness is language-agnostic):
   ```bash
   export LINT_CMD="<your linter, zero warnings>"   # e.g. eslint . / ruff check / flutter analyze
   export TEST_CMD="<your test runner>"
   export FORMAT_CMD="<your formatter --check>"
   ```
2. Write a sprint contract in `docs/sprints/<feature>.md` (template in `docs/harness.md`).
3. Run the loop:
   ```bash
   ./scripts/harness.sh docs/sprints/<feature>.md
   ```
   (Requires a coding-agent CLI; built around Claude Code's `claude` CLI — adapt to your agent.)

Or run it by hand: prompt your agent to **generate** against the contract, then in a **fresh context** prompt it to **evaluate** against `docs/harness.md` + `workflows/code-review.md`, then **fix** the list.

## Credits

The Generator-Evaluator harness pattern and the GAN-style critic insight come from Anthropic's [_Harness design for long-running agents_](https://www.anthropic.com/engineering/harness-design-long-running-apps). This repo is an independent implementation of that pattern.

## License

MIT — see [LICENSE](LICENSE).

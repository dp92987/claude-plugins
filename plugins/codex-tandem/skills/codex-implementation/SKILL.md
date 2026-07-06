---
name: codex-implementation
description: Delegate an implementation task to the OpenAI Codex CLI — Codex writes the code, Claude verifies it. Under the session routing policy this is the DEFAULT way code gets written — use it for any bounded implementation task (feature, fix, refactor with clear scope), not only when the user names Codex. Also use for explicit asks like "have codex implement this", "let codex fix it", "delegate this to codex". Skip it only for trivial edits (one-liners, typos, config tweaks) where a Codex round-trip costs more than it saves.
---

# Codex Implementation

Have OpenAI's Codex CLI implement a coding task in this repo, then verify its work before reporting back. Your role splits in two: first a *dispatcher* who writes Codex a precise, self-contained brief, then a *reviewer* who checks what came back. Do not implement the task yourself — under the routing policy Codex writes the code; your value is in the planning, the brief, and the verification.

The trivial-edit exception: one-liners, typo fixes, config tweaks, and small corrections you find while reviewing a Codex diff are yours to do directly — dispatching those wastes more time than it saves. When in doubt about whether a task is trivial, dispatch it.

## Prerequisites

Check once per session:

```bash
codex --version && codex login status
```

If either fails, tell the user — they need to install Codex or run `codex login` (it's interactive) — and offer to implement the task yourself instead. Don't just switch silently: the user asked for Codex specifically, so the substitution is their call.

## Step 1: Record the starting state

You need to attribute changes to Codex afterward, so snapshot before dispatching:

```bash
git rev-parse HEAD && git status --porcelain
git diff > <scratchpad>/codex-baseline.patch
```

If the tree is dirty, the baseline patch is what makes attribution exact later — `git status` alone records *which* files were dirty, not what was in them, so without the patch a Codex edit to a WIP file is indistinguishable from the WIP. Dirty beyond trivial WIP, or anything else that might touch this checkout during a 5–20 minute run (another Claude session, another terminal)? Don't dispatch into it — give Codex its own worktree (`git worktree add`) and dispatch there with `-C <worktree-path>`.

## Step 2: Write the brief

Codex gets exactly one prompt and no follow-up conversation, so everything it needs must be in the brief. A vague brief produces a plausible-looking wrong implementation. Include:

- **The task** — what to build/fix/change, with acceptance criteria.
- **Where** — relevant file paths and entry points you already know about. Codex can explore, but pointing it at the right files saves it from wandering.
- **Constraints** — project conventions that matter for this task (naming, error handling, layering), anything the user specified, and what *not* to touch. Codex reads AGENTS.md on its own — which points it at the user's learning-loop memory (`~/.claude/learning-loop-memory/preferences.md` and `examples.md`) — so don't paste those rules. Do name the task-relevant exemplar from `examples.md` when one fits ("follow the pattern in <repo>:<file>"): a concrete exemplar steers Codex better than the rule it illustrates.
- **Standing constraints** — always include these two: Codex must not commit, push, or modify anything outside the repo (its job is to leave changes in the working tree for review), and if the tree was dirty at the start, name those files and tell Codex to preserve them.
- **Verification** — how to check its own work (the test/build command, if the project has one), and to end with a short report: files changed, verification run and result, anything uncertain.

Do NOT include conversation history dumps or the full task backstory — distill to what changes the implementation.

Calibrate the brief's precision to taste-sensitivity, not just size. Codex executes mechanical work well but has weaker taste: pin down anything user-facing or design-heavy as already-made decisions in the brief — API shapes, endpoint and field names, response structures, error messages, copy — and leave genuinely mechanical details (plumbing, wiring, test scaffolding) to Codex's judgment.

Keep the task bounded: one coherent change per run. If the request bundles several substantial changes, split them into separate Codex runs dispatched sequentially (verify each before the next) — a sprawling brief produces a sprawling, unreviewable diff.

Structure the brief with XML tags — GPT-5-family models are trained on block-structured prompts, and stable tags keep a long brief unambiguous where prose sections blur together. Example brief:

```text
<task>
Add keyboard navigation to the command palette (src/palette/).
Start from src/palette/Palette.tsx and follow its existing handler patterns.
</task>

<acceptance_criteria>
- ArrowUp/ArrowDown move the highlight, Enter selects, Escape closes.
- Existing mouse behavior keeps working.
</acceptance_criteria>

<constraints>
- Do not commit, push, or modify anything outside the repo.
- Preserve the unrelated uncommitted changes in README.md.
- Do not touch the palette's data layer (src/palette/sources/).
</constraints>

<verification>
Run `npm test -- palette`.
</verification>

<report>
Files changed, verification run and result, anything uncertain.
</report>
```

## Step 3: Dispatch to Codex

Run with workspace-write sandbox (Codex edits repo files and runs commands, but can't touch the network or anything outside the workspace). Pass the brief via stdin heredoc to avoid quoting issues, capture the final message with `-o`, and run in the background — implementation runs commonly take 5–20 minutes:

```bash
codex exec -s workspace-write --color never \
  -o <scratchpad>/codex-impl.md \
  - <<'CODEX_BRIEF' > <scratchpad>/codex-impl-run.log 2>&1
<the brief>
CODEX_BRIEF
```

Keep the full run log — never pipe it through `tail`: the `session id: <uuid>` header is printed at the *top* of the run, and every follow-up in Step 4 must resume that exact session. Run with `run_in_background: true`, record the session id from the log as soon as the header appears, and wait. While waiting, prepare the verification: figure out the project's build/test commands if you don't know them yet.

If Codex needs network access for the task itself (e.g., installing a new dependency), it will fail inside the sandbox — do that step yourself before or after dispatch rather than escalating Codex's sandbox.

### Parallel runs

Never point two concurrent Codex runs at the same checkout — their edits collide. Give each run its own git worktree and dispatch with `-C <worktree-path>`. Inside a Workflow, wrap each dispatch in a thin low-effort agent (with `isolation: "worktree"`) that writes the brief, runs Codex, and returns the report — and label it with a `codex:` prefix, since the UI otherwise shows only the wrapper's model, not who did the actual work.

## Step 4: Verify

When Codex finishes, don't relay its summary on faith — its final message describes what it *believes* it did. Verify:

1. **Read the final message** from the `-o` file — Codex's own account, including anything it says it couldn't do.
2. **Read the diff** — `git status --porcelain` and `git diff` against the recorded starting state. Review it as you would a PR: correctness, unintended changes, files touched that shouldn't be.
3. **Build and test** — run the project's build/tests. If there's no test suite, at least compile/typecheck/lint whatever the project supports.

Then act on what you find:

- **Everything checks out** — proceed to Step 5. The independent review is part of the success path, not an extra for suspicious runs; skipping it on clean-looking diffs is exactly how rationalized shortcuts ship.
- **Trivial issues** (typo, missing import, formatting) — fix them yourself and say so.
- **Real problems** (wrong approach, failing tests, incomplete work) — send Codex a follow-up in the same session so it keeps its context, then re-verify:

```bash
codex exec resume <implementation-session-id> -c sandbox_mode="workspace-write" -o <out> "The tests fail with: <error>. Fix it."
```

Resume by the session id recorded in Step 3, never `--last`: after Step 5 the most recent session is the *reviewer's*, and any other Codex run in between (another terminal, a parallel task) steals `--last` too — the follow-up would land in a context that never wrote the code.

Cap this at 2 follow-up rounds. If Codex is still off track after that, take over and finish the implementation yourself — judge the output, not the delegation policy; completing it directly costs less than more loop rounds or shipping mediocre work. State plainly in the report that you took over and why.

## Step 5: Independent review

Once verification converges, get a second opinion on the final diff: run the codex-review skill against the Codex-authored changes. This isn't Codex re-reviewing its own work — a fresh review session has no memory of the implementing run's reasoning, so it can't rationalize that run's shortcuts. The two reviews are complementary: yours in Step 4 has conversation context and catches "this isn't what the brief meant"; the independent one has none and catches what the whole implementing session was blind to.

Review the *final* state — after your fixes and any resume rounds — or you're reviewing stale code. Triage the findings as codex-review prescribes: confirmed real problems re-enter the Step 4 fix loop (resuming the recorded *implementation* session id, not the review session); trivia you fix directly.

## Step 6: Report

Tell the user: what Codex changed (files + substance), what you verified (build/test results, actual output), what the independent review found and how each finding was resolved, any fixes you made yourself, and anything left open. Attribute honestly — distinguish "Codex did X" from "I fixed Y".

When the branch is about to become a PR, still offer the adversarial whole-branch codex-review — it's the only reviewer that sees the separately-reviewed changes composed together, and it sweeps up trivial edits that never got individual review.

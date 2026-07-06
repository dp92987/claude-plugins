---
name: codex-review
description: Get an independent code review from the OpenAI Codex CLI. Use whenever the user wants Codex's opinion on code — "codex review", "have codex review this", "get a second opinion from codex" — for uncommitted changes, a branch diff, or a specific commit. Under the session review policy, also use it without being asked as the independent-review step of every codex-implementation run, whenever substantial code Claude wrote directly is about to be considered done (trivial edits wait for the branch gate), and as the adversarial whole-branch gate before any PR ships.
---

# Codex Review

Run OpenAI's Codex CLI as an independent, non-interactive code reviewer and present its findings. The value of this skill is the *independence*: a fresh review session has no knowledge of this conversation or of the session that wrote the code, so it catches what the author context is blind to — that holds even for Codex-authored diffs, because independence comes from the fresh session, not just the model. Its three occasions under the review policy: the final diff of every codex-implementation run, substantial code Claude authored directly (including takeovers), and the whole branch as an adversarial pre-PR gate. Trivial Claude edits skip per-change review — the branch gate sweeps them up. And Codex's output is evidence, not authority: you still read the code.

## Prerequisites

Check once per session that Codex is available and authenticated:

```bash
codex --version && codex login status
```

If either fails, tell the user — they need to install Codex or run `codex login` themselves (it's interactive) — and offer to review the changes yourself instead. Don't substitute silently: the user asked for Codex's perspective, so that's their call.

## Step 1: Pick the review target

`codex exec review` has three targeting modes. Choose based on what the user asked and the state of the repo:

| Situation | Flag |
|---|---|
| Dirty working tree, or user says "my changes" | `--uncommitted` (staged + unstaged + untracked) |
| Feature branch, clean tree, or user says "this branch / my PR" | `--base <default-branch>` |
| User names a specific commit | `--commit <sha>` |

Check `git status --porcelain` and the default branch (`git symbolic-ref refs/remotes/origin/HEAD` or fall back to main/master) to decide. If both uncommitted changes and branch commits exist and the user was vague, review uncommitted first — that's usually the work in progress — and mention the branch diff is also reviewable.

## Step 2: Run the review

Reviews run read-only and typically take 2–10 minutes with a strong reasoning model, so run in the background and capture the final message to a file:

```bash
codex exec review --uncommitted \
  -o <scratchpad>/codex-review.md \
  2>&1 | tail -50
```

Run this with `run_in_background: true` and wait for completion. The `-o` file gets Codex's final review message; stdout carries progress events you can tail to check on it.

Codex reviews the diff cold — it has none of this conversation's context. When the change under review implements something discussed here (requirements, a bug being fixed, a design decision), pass that context as custom review instructions; it turns false positives ("why would anyone do X?") into real signal at the source.

The CLI rejects targeting flags combined with custom instructions (`codex exec review --uncommitted "focus on X"` errors out), so a custom-instruction review drops the flag and states the target in the prompt's first line instead:

```bash
codex exec review -o <out> - <<'EOF'
Review the uncommitted working-tree changes (staged, unstaged, and untracked).
Context: <one paragraph — what the change is supposed to do and any deliberate decisions>.
Pay extra attention to: <risky areas, or files you are unsure about>.
Also check conformance to the conventions in ~/.claude/learning-loop-memory/preferences.md.
For each finding give severity, file:line, the concrete failure mode, and a fix direction.
If there are no substantive findings, say so and name any residual test gaps.
EOF
```

(For a branch or commit target, replace the first line with "Review the changes on this branch against <base>" or "Review commit <sha>".) Use the bare flag form from Step 1 only when you genuinely have no context to add.

### Adversarial mode

For the pre-PR whole-branch gate, or when the user wants the design challenged rather than the diff checked ("pressure-test this", "should this ship?"), harden the instruction block into a challenge review — append:

```text
Review adversarially: find the strongest reasons this should not ship yet; do not validate it.
Question the chosen approach, its assumptions, and where it fails under real conditions.
Prioritize expensive, hard-to-detect failures: auth and trust boundaries, data loss or
corruption, rollback and partial-failure safety, races and ordering assumptions,
empty/null/timeout paths, migration and compatibility hazards.
Report only material findings you can defend from the code — no style notes, no speculation
without evidence. Prefer one strong finding over several weak ones. If the change looks safe,
say so directly.
```

The stance matters for the gate: an *adversarial* review that comes back approving is a meaningful ship signal, where a neutral review's silence is weak evidence.

The preferences line matters because the native review flow focuses on the diff and may not consult the user's global agent instructions the way a normal Codex run does — asking explicitly makes style conformance part of the review.

Don't override the model — the user's `~/.codex/config.toml` already sets their preferred model and reasoning effort. Only pass `-m` if the user explicitly names a model.

## Step 3: Present findings — with your own judgment

Read the `-o` output file. Then, before presenting, verify each finding against the actual code. Codex reviews the diff without conversation context, so some findings will be wrong or moot (e.g., flagging something the user deliberately chose, or misreading intent). Presenting raw unvetted findings wastes the user's time. If the review is too large to verify everything, verify the high-severity findings and clearly label the rest as unverified — never present a finding you didn't check as confirmed fact.

Present as:

1. **Verdict** — one line: overall assessment.
2. **Findings by severity** — for each: file:line, what Codex found, and your take (confirmed / disagree and why / not verified). Keep Codex's substance, don't launder its criticism.
3. **Offer to fix** — end by offering to fix the findings you agree are real. Don't fix anything until the user says so.

If Codex found nothing, say so plainly and name what it inspected (e.g., "uncommitted changes, 5 files") — a clean review is a useful result, not a failure.

## Iterating

To ask Codex a follow-up about its own review (e.g., "is finding 2 really exploitable?"), resume the same session so it keeps its context:

```bash
codex exec resume --last -o <out> "your follow-up question"
```

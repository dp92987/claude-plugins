---
name: learning-loop
description: Maintains a self-learning memory of the user's personal engineering style — code style, architecture decisions, naming, testing preferences, error handling, PR structure, refactoring habits, and things they reject in review — so AI coding agents produce PRs the way the user would write them. Use this skill whenever the user gives a session transcript path to learn from, or says things like "learn from this session", "extract my preferences", "what did you learn about my style", "review the learning loop inbox", "promote preferences", or "promote rules". This skill only MAINTAINS the style memory (extract candidates, curate, promote); it does NOT apply style during coding tasks — application happens via the AGENTS.md pointer to the memory files, independent of this skill.
---

# Learning Loop

Maintain the user's engineering-style memory in `~/.claude/learning-loop-memory/` (create the directory if it doesn't exist):

- `preferences.md` — approved rules, grouped by topic (style, architecture, naming, testing, error handling, PR structure, anti-patterns). Repo-specific rules carry a `repo:` prefix; general taste rules don't. Hard cap: 150 lines.
- `examples.md` — exemplar pointers ("when doing X, follow the pattern in `<repo>:<file/dir>`"). Prefer these over abstract rules — a real file teaches more than a sentence.
- `inbox.md` — pending candidates awaiting the user's approval, each with the triggering quote as an HTML comment for provenance.

All memory paths in this file are absolute under `~/.claude/learning-loop-memory/` — never create these files relative to the working directory.

This skill never applies style itself. Application happens unconditionally because the user's AGENTS.md points coding agents at `preferences.md` and `examples.md` before implementing. Do not build any "load preferences before coding" mode — that path must not depend on skill routing.

Rule quality standard: read `references/rule-format.md` (relative to this SKILL.md's directory) before writing any candidate rule.

## Setup (first run only)

Check that the user's global agents file (`~/.claude/AGENTS.md`, which `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` symlink to — verify the symlinks actually exist before relying on this topology) contains a pointer like:

> Before implementing, read `~/.claude/learning-loop-memory/preferences.md` and `examples.md` — my conventions and exemplar files live there.

If it's missing, add it (ask before creating any file from scratch, and ask before writing to a non-symlinked location).

## Mode 1: Extract

Input: a transcript path (Claude Code session JSONL), or "this session" (use the current conversation).

1. Review the conversation, the decisions made, and the final git diff if one exists.
2. Mine for correction signals: rejected diffs, requests the user rephrased after a failed attempt, messages like "no / not like this / actually", and places where the user manually changed code after an edit. Pre-filter transcripts with `scripts/find-corrections.sh <transcript.jsonl>` — the script lives next to this SKILL.md, so invoke it by absolute path (`<this skill's directory>/scripts/find-corrections.sh`), not relative to the working directory. Use it instead of reading the raw file — it extracts user messages that follow edits, keyword-flagged corrections, and edit/plan rejections.
3. Derive candidate rules: one sentence each, generalizable, positively phrased — point at an exemplar file rather than writing "don't". See `references/rule-format.md`.
4. Ignore task-specific details, one-off decisions, temporary project context, and anything that is a guess rather than an observed preference. A correction the user made once about *this* feature is noise; a correction that would apply to the next ten PRs is signal.
5. Dedupe against `preferences.md`, `examples.md`, and `inbox.md` before adding anything.
6. Interactive run: interview the user about ambiguous candidates only — max 5 questions — asking whether the rule is general or context-specific and how they would word it.
7. Non-interactive run (invoked headlessly from the SessionEnd hook): skip the interview; write all candidates to `~/.claude/learning-loop-memory/inbox.md`, marking ambiguous ones with a `QUESTION:` line for the next interactive run. Create `inbox.md` if it doesn't exist.
8. Write confirmed/candidate rules to `~/.claude/learning-loop-memory/inbox.md` only. Never touch `preferences.md` or `examples.md` in this mode.
9. End with a summary: what was learned, what looks worth saving, open questions.

Inbox entry format:

```markdown
- [ ] Storage methods return model types, not driver types like bson.Raw.
  <!-- from PR #23714 review, 2026-07-02: "lets add models like FlightStatusSubscriptionExport" -->
  QUESTION: general taste, or specific to the delta monorepo?
```

## Mode 2: Promote

Run on request. Suggest running it when `inbox.md` has 10+ items.

1. Read `~/.claude/learning-loop-memory/inbox.md`; resolve any `QUESTION:` items with the user first.
2. For each rule ask: can this become a golangci-lint or semgrep check instead? If yes, propose the lint/semgrep config, not a prose rule. Mechanical rules go to tooling; only judgment rules go to memory — a linter enforces forever at zero context cost.
3. Merge the remaining rules into `preferences.md` / `examples.md`: dedupe, consolidate overlaps, apply the repo-prefix convention, and flag conflicts with existing rules — ask the user rather than silently overwriting.
4. Size budget: `preferences.md` stays under 150 lines. Going past the cap requires merging rules or demoting the weakest. A section may graduate to its own file only when it exceeds ~50 lines (leave a pointer behind).
5. Show the user the full proposed diff and WAIT for explicit approval. Never modify `preferences.md`, `examples.md`, or AGENTS.md without it.
6. Clear promoted items from `inbox.md`.

## Hook

`hooks/hooks.json` registers a SessionEnd hook (`hooks/on-session-end.sh`) that invokes Mode 1 headlessly on the finished session's transcript with a cheap model (tools: Read, Bash, Edit, Write — Write is required to create `inbox.md` on first run). It ships disabled: it exits immediately unless `~/.claude/learning-loop-memory/.enabled` exists. See `README.md` for arming and safety details (recursion guard, minimum transcript size).

---
name: learning-loop
description: Use for "learn from this session", "extract my preferences", "review the learning loop inbox", "promote rules", "what did you learn about my style", or any session-transcript path to learn from. Extracts and curates the user's engineering-style memory; never applies it.
---

# Learning Loop

This skill maintains the user's engineering-style memory — code style, architecture decisions, naming, error handling, things rejected in review — so AI coding agents produce PRs the way the user would write them. It only maintains memory (extract candidates, curate, promote); it never applies style during coding tasks — application is file-based and independent of skill routing.

Memory sources live in `~/.claude/learning-loop-memory/` (create the directory if it doesn't exist):

- `preferences.md` — approved *universal* taste rules that apply to any code. Hard cap: 150 lines.
- `preferences-<stack>.md` — approved stack-specific rules (e.g. `preferences-go-backend.md` for Go/backend-service/OpenAPI conventions), each file carrying its own `paths:` YAML frontmatter that scopes where it applies. Repo-specific rules inside carry a `repo:` prefix. Cap: 150 lines per file.
- `examples.md` — exemplar pointers ("when doing X, follow the pattern in `<repo>:<file/dir>`"). Prefer these over abstract rules — a real file teaches more than a sentence.
- `inbox.md` — pending candidates awaiting the user's approval, each with the triggering quote as an HTML comment for provenance.
- `ledger.tsv` — processed-transcript ledger (path + bytes), maintained by the hook and sweep; not yours to edit.

All memory paths in this file are absolute under `~/.claude/learning-loop-memory/` — never create these files relative to the working directory.

Application happens through three compiled/file-based channels, kept in sync by `scripts/compile-channels.sh`:

1. `~/.claude/CLAUDE.md` inlines `preferences.md` and `examples.md` via `@` imports — universal taste, every Claude Code session (loaded at launch, re-read after compaction).
2. `~/.claude/rules/learning-loop-<stack>.md` — verbatim compiled copies of the stack files; Claude Code loads each only when the session touches files matching its `paths:` frontmatter, so Go rules stop riding into prose sessions and non-Go repos.
3. `~/.claude/AGENTS.md` — the prose pointer plus a marker-delimited compiled block with the *full* memory content, so Codex gets the rules inline rather than being asked to go read files (advisory pointers get skipped mid-task). `~/.codex/AGENTS.md` symlinks to it.

Do not build any "load preferences before coding" mode — that path must not depend on skill routing. Do not replace the imports with a SessionStart hook: hook output is capped at 10k characters and duplicates on resume — imports have neither problem.

Rule quality standard: read `references/rule-format.md` (relative to this SKILL.md's directory) before writing any candidate rule.

## Setup (every run — cheap, reconciles the application channels)

Verify the channels on each run — they live outside the plugin, so plugin updates can't rewrite them, and reconciling here is how changes propagate:

**1. `~/.claude/CLAUDE.md` (Claude Code, universal)** — a real file (not a symlink) whose canonical content inlines the universal memory via imports:

> My engineering conventions and exemplar files (learning-loop memory), inlined via imports:
>
> `@~/.claude/learning-loop-memory/preferences.md`
> `@~/.claude/learning-loop-memory/examples.md`

**2. `~/.claude/AGENTS.md` (Codex and other agents; `~/.codex/AGENTS.md` symlinks to it — verify the symlink exists)** — the canonical prose pointer, followed by the compiled block that `compile-channels.sh` maintains between `<!-- learning-loop:compiled -->` markers:

> Before implementing or reviewing code, read `~/.claude/learning-loop-memory/preferences.md` and `examples.md` — my conventions and exemplar files live there.

**3. Compiled artifacts** — `~/.claude/rules/learning-loop-<stack>.md` must match its `preferences-<stack>.md` source, and the AGENTS.md compiled block must reflect the current sources. If either drifted (compare content), run `scripts/compile-channels.sh` (next to this SKILL.md) — it is idempotent.

For the two user-owned files:

- **Missing entirely** — add it. Ask before creating a file from scratch, and ask before writing to an unexpected location or replacing a symlink.
- **Present and already matches** — do nothing (the common case; stay silent).
- **Present but differs from the canonical wording** (e.g. an older phrasing, or a stale memory path) — show the user the exact diff and offer to update it. Never rewrite it silently. Only touch the learning-loop lines/block; leave the rest of the file untouched.

## Mode 1: Extract

Input: a transcript path (Claude Code session JSONL), or "this session" (use the current conversation).

1. Review the conversation, the decisions made, and the final git diff if one exists.
2. Mine for correction signals: rejected diffs, requests the user rephrased after a failed attempt, messages like "no / not like this / actually", renames/removals the user asked for, and places where the user manually changed code after an edit. Distill transcripts with `scripts/find-corrections.sh <transcript.jsonl>` — the script lives next to this SKILL.md, so invoke it by absolute path (`<this skill's directory>/scripts/find-corrections.sh`), not relative to the working directory. Use it instead of reading the raw file — it emits every genuine user message (`[user]`) plus edit/plan rejections (`[rejection]`), with tool output and meta messages stripped. It deliberately does not judge which messages are corrections — that is your job; corrections often carry no correction keyword at all ("rename X to Y", "ive made some changes, update the tests"). When a message is ambiguous on its own ("undo that", "not like this"), don't read the whole raw transcript — grep the JSONL around that message for the edit or diff it reacted to; targeted context recovers the meaning at a fraction of the cost. One class of correction hides in tool output the distiller drops: PR review comments. When a `[user]` message references PR comments or review feedback ("address the PR comments", "fix what I flagged in the review"), grep the raw transcript for the fetched `gh` output and treat those comments as the user's own corrections — the user authored them on GitHub, and review comments are often the highest-quality style signal a session carries.
3. Derive candidate rules: one sentence each, generalizable, positively phrased — point at an exemplar file rather than writing "don't". See `references/rule-format.md`.
4. Ignore task-specific details, one-off decisions, temporary project context, and anything that is a guess rather than an observed preference. A correction the user made once about *this* feature is noise; a correction that would apply to the next ten PRs is signal.
5. Dedupe against `preferences.md`, `examples.md`, and `inbox.md` before adding anything.
6. Interactive run: interview the user about ambiguous candidates only, asking whether the rule is general or context-specific and how they would word it.
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
3. Route each remaining rule to its source file: universal taste → `preferences.md`; stack-specific → the matching `preferences-<stack>.md` (create a new stack file, with `paths:` frontmatter, only when a rule fits no existing one). Per-project *facts* (build commands, repo layout) are not style — leave those to Claude Code's auto memory; don't promote them.
4. While merging: dedupe, consolidate overlaps, apply the repo-prefix convention, and flag conflicts with existing rules — ask the user rather than silently overwriting.
5. Size budget: 150 lines per source file. Going past the cap requires merging rules or demoting the weakest. If a section graduates to a new file, it must be wired into a channel in the same change — `paths:` frontmatter + compile for stack files, or an `@` import in CLAUDE.md for universal ones. A bare prose pointer silently detaches the rules from every agent.
6. Show the user the full proposed diff and WAIT for explicit approval. Never modify the memory sources or the CLAUDE.md/AGENTS.md application files without it.
7. After approval: run `scripts/compile-channels.sh` to regenerate the rules files and the AGENTS.md block, then clear promoted items from `inbox.md`.

## Hook

`hooks/hooks.json` registers a SessionEnd hook (`hooks/on-session-end.sh`) that invokes Mode 1 headlessly on the finished session's transcript with sonnet, using the slash-form skill invocation (`/learning-loop:learning-loop ...` — the documented way to load a skill in a `claude -p` run). Edit/Write are path-scoped to `inbox.md` so the headless run can never touch `preferences.md` or `examples.md`, which every future session inlines. It runs by default; `touch ~/.claude/learning-loop-memory/.disabled` turns it off (it then exits silently). While active, every skipped or started extraction logs one line to `extract.log`, so "off" is distinguishable from "broken". See `README.md` for safety details (recursion guard, minimum transcript size).

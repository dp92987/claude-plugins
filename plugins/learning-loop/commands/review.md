---
description: Review the current change against the learnt style memory — report-only, every finding cites the rule it violates
argument-hint: "[base ref | path]  (default: uncommitted + branch diff vs master)"
---

Review the current code change for compliance with the learnt engineering-style
memory in `~/.claude/learning-loop-memory/`. This command has one narrow job:
check the change against the *approved* learnt rules. It is not a general code
review (bugs, security) — other tools own that. Report only; never fix anything
unless the user asks afterwards.

Arguments: `$ARGUMENTS` — optional. A git ref overrides the diff base; a path
restricts the review to that path. Empty means the default scope below.

## 1. Establish the scope

The review covers only what the change introduces — changed lines, not
pre-existing code around them.

1. Default base: `git merge-base origin/master HEAD` (fall back to `master`,
   then `main`, if `origin/master` doesn't exist). On the default branch itself,
   the base is `HEAD`.
2. The diff is `git diff <base>` (committed + uncommitted tracked changes) plus
   untracked files from `git status --porcelain`.
3. If the diff is empty, say so and stop.

## 2. Select the rule files

- Always: `~/.claude/learning-loop-memory/preferences.md` and `examples.md`.
- Each `~/.claude/learning-loop-memory/preferences-<stack>.md` whose `paths:`
  frontmatter globs match at least one changed file — the same scoping the
  rules channel uses. Skip stack files that match nothing.
- If no memory files exist yet, say the loop has learnt nothing to review
  against and stop.

## 3. Delegate to the reviewer

Spawn the `style-reviewer` subagent (Agent tool, subagent_type
`style-reviewer`) — an independent reviewer, because the session that wrote
the code reviews it poorly. Pass it:

- the working directory and the resolved diff base (plus the untracked-file
  list); it runs git itself rather than receiving a possibly huge diff inline
- the absolute paths of the selected rule files
- the path restriction from `$ARGUMENTS`, if any

If the Agent tool is unavailable (headless run), do the subagent's job
in-context following the same contract.

## 4. Report

Present the findings to the user:

- Each finding: `file:line`, what the change does, and the exact rule it
  violates — quoted, with its source file. A finding without a citable rule
  does not exist; drop anything the subagent returned without one.
- Exemplar divergences (code that should follow an `examples.md` pattern but
  doesn't) are findings too — cite the exemplar pointer.
- If nothing was found, say the change complies with the learnt rules and
  name which rule files were checked — silence is not a report.
- Do not edit any code. If the user asks to fix findings, that's a new
  instruction — proceed then.

## 5. Feed disagreements back

When the user disputes a finding because the *rule* is wrong ("that rule is
outdated", "too strict", "doesn't apply here"), append a curation candidate to
`~/.claude/learning-loop-memory/inbox.md` in the standard inbox format, quoting
the user's objection as the provenance comment. Rule edits themselves stay in
Mode 2 (Promote) with explicit approval — never edit `preferences*.md` or
`examples.md` from this command.

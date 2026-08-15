---
name: taste-review
description: >-
  Checks changed Go code against the user's personal taste rules — the style
  conventions no linter can judge, such as abstraction height, whether a
  comment earns its place, naming semantics and file structure. Runs before a
  pull request is opened, so the diff under review is already in the user's
  own style; also runs on explicit request against the working tree, a named
  branch or a commit range. Not for bug hunting, correctness or performance
  review; those are a different pass.
when_to_use: >-
  Use whenever the user asks to create, open, raise, draft or ship a pull
  request on a branch touching Go code — "создай PR", "запили PR", "оформи
  пулл-реквест", "open a PR", "ship it" — reviewing first and applying fixes
  before the PR is created. Also use on explicit style-check requests:
  "проверь стиль", "прогони taste-ревью", "соответствует ли это моим
  правилам", "check my style rules", "review the diff against my
  conventions".
---

# Style Guard: taste review

The two lint tiers of style-guard catch what a machine can decide. This skill
covers the rest: `$HOME/.claude/style-guard/taste.md` holds rules that need
judgment, and judgment needs a reader.

Why a separate pass rather than loading the rules while coding: rules carried
in the coding session compete for attention with the task, the code and the
tools, and adherence decays as they accumulate. Handed to a reviewer whose
only job is those rules, they stop competing — the rules *are* the task. The
same reason the reviewer gets a fresh context: an agent that just wrote the
code is a poor judge of whether it looks like someone else's.

**PR creation is the anchor.** It is the one unambiguous "this work is
finished" boundary, so that is where the pass runs by default: review the
branch, fix what it finds, then open the PR. Running per-edit would burn a
fan-out on code still being rewritten. Any other moment is the user's call.

A `PreToolUse` hook backs this up: `gh pr create` is blocked while any
changed Go file lacks a current stamp. So if a PR is attempted without this
pass having run, the agent is told to run it — and the stamp written in
Step 5 is what unblocks the PR.

## Modes

Everything below branches on how the skill was reached, so settle it first:

- **PR mode** — reached on the way to creating a pull request. Fixes are
  applied, and *every early exit below ends the review, not the PR*: say one
  line about why the review did nothing and carry on to creating the PR.
- **Review mode** — reached by an explicit request to look at code. Findings
  are reported and nothing is edited unless the user asks. An early exit ends
  the turn.

## Step 1 — Gather the input

Read `$HOME/.claude/style-guard/taste.md` (via Bash — the leading `~`/`$HOME`
needs expanding). Rules are the `##` headings under `#` theme headings;
ignore the preamble and anything inside fenced code blocks, which is format
documentation rather than rules. No rules → early exit: there is nothing to
check against, and a review without rules invents findings.

Then the diff — everything this branch introduces, committed or not, since by
PR time the work is usually already committed and `git diff HEAD` would come
back empty:

```
git fetch --quiet origin                       # без этого база устаревает
BASE=$(git merge-base HEAD origin/HEAD)        # или origin/<default>
git diff "$BASE" -- '*.go' > "$TMP/taste.patch"
git ls-files --others --exclude-standard -- '*.go'
```

- **Fetch first.** The base is only as fresh as the last fetch, and this user
  merges master into feature branches mid-work. A stale ref moves the base
  behind those merges and every colleague's commit joins "this branch's
  diff" — measured on a real branch: 32 files became 421.
- Resolve the default branch rather than assuming `master`:
  `git symbolic-ref --short refs/remotes/origin/HEAD`. If that fails, ask
  rather than guessing.
- On a **stacked branch** the base is the parent PR's branch, not the default
  one — `gh pr view --json baseRefName` when a PR exists, otherwise ask.
- **Sanity cap.** More than ~40 files or ~3000 added lines almost always
  means the base is wrong. Stop and confirm with the user before fanning out;
  in PR mode, never auto-fix a diff you haven't confirmed is really theirs.
- **Untracked files count as wholly added** — include them in full.
- **Exclude generated code** before anything else: drop files matching
  `^// Code generated .* DO NOT EDIT\.$` in their first lines, plus
  `vendor/**`. Findings there are pure noise, and in PR mode the skill would
  "fix" files the next `go generate` overwrites.

**Added lines only**, except where a rule declares otherwise (see Step 2).
Pre-existing violations in a touched file are not this change's business.

Empty Go diff → early exit.

### Skip what was already reviewed

`$HOME/.claude/style-guard/.reviewed` holds one line per file:

```
<sha256-of-file> <sha256-of-taste.md> <absolute-path>
```

Skip a file only when **both** hashes match. The taste.md hash is what keeps
coverage honest: without it, a rule added tomorrow would never be checked
against any file already stamped, and the pass would report "already
reviewed" while silently not reviewing.

Nothing left after filtering → early exit saying the changes were already
reviewed. That is a success; don't fan out to prove it.

Ignore the stamp when the user asks for a re-review or names a base, branch
or range — they asked for a fresh look.

## Step 2 — Fan out, one subagent per theme

The theme is the unit: group the rules by their `#` theme headings and spawn
one subagent per theme, all in a single message so they run concurrently. One
theme means one agent; a theme grown past ~8 rules gets split in two.

Splitting this way is the point of the design: handing one agent thirty rules
recreates the very problem this pass exists to avoid — it attends to the
first few and skims the rest. Per theme, each agent's instruction density
stays trivial and its attention undivided.

Give each subagent:

- its theme's rules, verbatim, including the `Don't flag` lines;
- the **path** to the patch file plus the list of changed files — not the
  diff inline. Inlining copies the whole diff into your own context once per
  theme; a 2400-line diff across five themes is six figures of tokens before
  a single reply arrives.
- permission to read the changed files in full when a rule needs whole-file
  context (structural rules — "one method per file", "consts at the top" —
  cannot be judged from added lines alone).

Spawn them read-only: reviewers must not edit. Parallel agents editing the
same files while you are about to fix them yourself corrupts the change.

Subagent contract:

- Report only violations of the rules you were given. Not bugs, not
  performance, not correctness, not rules you happen to believe in.
- One finding per line, exactly: `<rule-id> <file>:<line> — <what the rule
  requires>`. Reply with the single word `NONE` when there are none.
- **A finding you cannot tie to a specific rule id does not get reported.**
- When a case is genuinely ambiguous, or matches a `Don't flag` neighbor,
  stay silent. Missing one violation costs one instance; a false finding
  costs the user's trust in the whole pass.
- `NONE` is a normal, expected result. Do not go looking for something to
  justify the run.

## Step 3 — Consolidate

Drop findings citing no rule id or an id not in `taste.md`. When one rule
fires more than ~5 times in a file, report it once with the line list. Group
by file, ordered by file and line.

Consolidation is mechanical: a cited finding is not dropped because you
disagree with it.

## Step 4 — Act on the findings

**PR mode:** apply the fixes, then verify you didn't break the build —
`go build ./<changed-dirs>/...` on the touched packages — and repair or
revert anything that fails before continuing. A taste fix is still an edit.
Then hand off to the repo's PR workflow, telling it the fixes need committing
(and pushing, if the branch was already pushed — otherwise the PR opens from
a tip that lacks them). Deciding what goes into a commit is that workflow's
call, not this skill's.

**Review mode:** report and stop. Fix only if the user asks. A review request
is a request for information.

Report in the user's language. Always state the shape of the run, even when
clean — "проверено 23 правила в 5 темах по 6 файлам, нарушений нет" — because
an empty report is otherwise indistinguishable from a broken one. Then list
findings as rule id, `file:line`, what the rule requires.

## Step 5 — Stamp what is actually clean

Write `<file-sha256> <taste-sha256> <absolute-path>` for every reviewed file
that ended the pass **with no outstanding findings** — clean, or fixed. A
file whose findings the user hasn't addressed stays unstamped; stamping it
would mean the next pass skips it and the violations sail into the PR.

Replace any previous line for that path; absolute paths, since one stamp file
serves every repo and worktree. Do this after fixes, so the hash matches the
final content. Skip the stamp entirely when reviewing a branch or range that
isn't the working tree.

## Step 6 — Feed rejections back

When the user waves off a finding ("тут так и надо"), that is a defect in the
rule, not in the code: its wording is too broad or its `Don't flag` list is
missing a case. Append it to `$HOME/.claude/style-guard/.rejections` as
`<date> <rule-id> <file>:<line> <what the user said>`, and offer to hand it
to `/style-guard:add` — naming which part you'd change.

Persisting matters because the wave-off usually lands a turn later, after
this skill's text is out of play; a rule rejected five times across five
sessions otherwise accumulates no evidence at all, and a rule that keeps
producing waved-off findings eventually gets the whole pass ignored.

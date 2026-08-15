---
name: add
description: >-
  Makes a personal code-style rule stated in natural language stick by routing
  it to the tier that can hold it — an ast-grep rule checked on every edit, a
  golangci-lint rule checked over the diff when the rule needs type
  information, or a reviewed taste rule when no linter can judge it. Drafts
  the rule, proves it on a fixture, dry-runs it over the real repo, and
  installs it only once the user approves what the dry run showed. Also
  maintains the existing ruleset — listing, tuning and removing rules.
when_to_use: >-
  Use whenever the user states a code convention they want enforced
  permanently — "затверди правило", "сделай из этого правило линтера", "добавь
  правило стиля", "хочу чтобы всегда/никогда <паттерн в коде>", "harden this
  rule", "add a lint rule", "make sure I never see X again" — including right
  after they corrected generated code and want the correction to stick. Also
  use to list, tune, dry-run or remove rules already installed.
---

# Style Guard: add a rule

The user maintains a deterministic style layer in `~/.claude/style-guard/`,
enforced by two hooks that feed violations straight back to the coding agent:

- **ast-grep rules** (`rules/*.yml`) — a PostToolUse hook scans every edited
  Go file. Fast, syntax-only, immediate.
- **golangci-lint** (`golangci.yml`) — a Stop hook gates the end of the turn
  on the diff. Slower, type-aware, once per turn.
- **taste rules** (`taste.md`) — what no linter can judge. Checked by a
  review pass over the diff, not by a hook.

Everything the layer knows lives in `~/.claude/style-guard/`; the plugin
reads and writes nothing else.

This skill is the single front door for "make this stick": the user states a
convention in words, the skill decides which of the three destinations can
actually hold it, and writes it there. It never applies style itself during
coding — enforcement is the hooks' and the review pass's job.

Why the ceremony below matters: a rule that fires on legitimate code trains
the agent to argue with the linter, and a rule that misses real violations is
silent noise in a file. Every rule therefore gets validated against a fixture
AND dry-run over real code before it is installed, and the user explicitly
approves what they saw.

Paths are fixed: data dir `~/.claude/style-guard/` (`sgconfig.yml`,
`rules/*.yml`, `golangci.yml`, `taste.md`). Never create these relative to
the working directory.

Steps 2–5 below describe the ast-grep tier, which most machine-checkable
rules land in; the type-aware and taste tiers have their own sections further
down. Every tier ends the same way: the user sees what the rule will do and
approves before anything is written.

## Step 1 — Classify the stated rule

Restate the rule in one sentence and decide which of three kinds it is. Tell
the user the classification and why.

- **Lintable (structural)** — expressible as a syntax pattern: banned calls or
  imports, required/forbidden shapes of declarations, naming patterns by
  regex, file-structure conventions. → proceed to Step 2.
- **Type-aware** — needs type information syntax doesn't carry (e.g. "don't
  return interfaces": a named return type is syntactically indistinguishable
  from a struct). ast-grep can't check it. First check whether an existing
  golangci-lint linter covers the rule (`ireturn` for interface returns,
  `forbidigo` for call bans, `depguard` for import bans, `revive` rules) — if
  yes, implement through the golangci tier (see "Type-aware tier" below): a
  maintained type-aware linter beats a hand-rolled approximation. Otherwise
  offer the closest ast-grep approximation if a useful one exists (say what
  it will miss), or name ruleguard/go-analysis as the missing tier and stop —
  do not install a rule that pretends to check more than it does.
- **Taste** — judgment calls: abstraction height, whether a comment is
  warranted, semantic quality of names. No linter can check these; they are
  checked by a review pass over the diff before the PR — not during coding,
  and not by a hook. Say so plainly, then record the rule properly (see
  "Taste tier" below) — a stated rule that never got written down is the real
  failure mode here. Do not force an ast-grep rule onto a taste rule: a false
  mechanical proxy is worse than a reviewed one, because it fires on
  legitimate code and teaches the agent to ignore the linter.

## Step 2 — Pin down scope and exceptions

Ask only what is genuinely ambiguous, in one round:

- Known-legitimate exceptions? (constructors, mappers, generated code, tests —
  in this user's conventions `new*`/`map*` functions and `mappers/` packages
  are usually legitimate, `*_test.go` usually excluded)
- Scope: all Go code, or only certain paths? (rule-level `files:`/`ignores:`
  globs)
- Severity: `warning` by default; `error` only for absolute bans the user
  states as absolute.

## Step 3 — Draft and validate against a fixture

Read `references/writing-go-rules.md` (relative to this SKILL.md) before
writing the YAML — it carries the verified node-kind cheat sheet and the
pitfalls that were hit on real rules.

Work in a scratch dir, never draft directly in `~/.claude/style-guard/` —
and never write drafts, fixtures, or lint configs into the user's working
repo: personal rules live in the data dir, team-shared configs
(`.golangci.yml` and friends) are a team decision the skill doesn't make.

1. Write the rule YAML and a minimal `sgconfig.yml` next to it.
2. Write a fixture `.go` file containing every violation shape the rule must
   catch AND every nearby-legitimate shape it must not catch (the exceptions
   from Step 2, plus methods, local types, etc.).
3. Run `ast-grep scan -c sgconfig.yml --report-style short --color never
   fixture.go` and compare hit lines against expectations. Iterate until both
   directions are exact: all violations hit, no legitimate shape hits.

A rule that can't be made exact on its own fixture is not ready — refine or
reclassify.

## Step 4 — Dry-run over real code

Run the draft over the repo the user is working in (or a path they name):

```
ast-grep scan -c <scratch>/sgconfig.yml --report-style short --color never <repo-path>
```

Report to the user: total count, and 5–10 representative findings quoted with
file:line. Read a couple of the flagged sites and say which look like genuine
violations and which look like noise. Noise patterns usually fix with
rule-level `ignores:` globs, name-regex exclusions, or tightening the match
position — propose the refinement, apply, re-run, show the delta.

The dry-run is the real review: the fixture proves the rule means what it
says, the dry-run shows what it will actually do to the user's day.

## Step 5 — Install on explicit approval

Only after the user approves what the dry-run showed:

1. Copy the rule to `~/.claude/style-guard/rules/<id>.yml`.
2. If `~/.claude/style-guard/sgconfig.yml` doesn't exist yet (the hook
   normally creates it on first run), write it: `ruleDirs:` with one entry
   `rules`.
3. Confirm: the hook picks the rule up on the next edit — no restart, no
   registration step.

Existing violations in the repo are NOT the skill's business — the hook only
checks edited files, so old code surfaces gradually. If the user wants a
one-shot cleanup sweep, that's a separate task they ask for explicitly.

## Type-aware tier: personal golangci.yml

Enforcement differs from the ast-grep tier because golangci-lint is orders of
magnitude slower: it runs once per turn from a Stop hook (gate on finishing,
`--new-from-rev HEAD` limits findings to changed lines), not on every edit.
The hook only arms itself when `~/.claude/style-guard/golangci.yml` exists —
the file's presence is the tier's on-switch.

The same draft → validate → dry-run → approve cycle applies, adapted:

1. Config format is golangci-lint v2 (`version: "2"` required). Enable only
   the linters the user's rules need, with their `settings` — this is a
   personal rule layer, not a copy of any repo's CI config.
2. Validate on a fixture package: violations and legitimate neighbors, run
   `golangci-lint run -c <draft>` over it, exact in both directions. The
   binary resolves as `golangci-lint` on PATH or `go tool golangci-lint`
   in repos that declare it; run from the target repo so `go tool` works.
3. Dry-run over the user's repo the way the hook will see it:
   `golangci-lint run -c <draft> --new-from-rev HEAD ./<changed-dirs>/`.
   Report counts and samples like the ast-grep flow.
4. On approval, merge into `~/.claude/style-guard/golangci.yml` (create with
   `version: "2"` on first rule). One config carries all type-aware rules;
   removing a rule = removing its linter/settings block.

## Taste tier: reviewed rules

Taste rules live in `$HOME/.claude/style-guard/taste.md` (create it from
`${CLAUDE_PLUGIN_ROOT}/seed/taste.md` if missing — that file also carries the
canonical per-rule format). It is deliberately not loaded into coding sessions: it is
the input to `/style-guard:taste-review`, which checks a diff against it. So
the rule's reader is a reviewer looking at a diff, not an author writing
code — and every rule must be **decidable from the diff alone**.

Each rule carries these parts, all of them load-bearing:

- **id** — kebab-case, stable. Findings cite it, and tuning targets it.
- **Rule** — imperative and observable. "Return a bool for not-found, not a
  sentinel error" can be checked; "handle not-found cleanly" cannot.
- **Why** — the reason, so cases the wording didn't anticipate still resolve
  the right way instead of being waved through.
- **Violation / Correct** — a 3–10 line pair. The reviewer's job is pattern
  matching, and a rule shown next to its counter-example holds up measurably
  better than the sentence alone.
- **Don't flag** — the legitimate neighbors this rule must stay away from.
  The most valuable line of all: reviewers over-flag by default, and a stream
  of false findings discredits the whole pass faster than misses do.
- **Needs: full-file** — only for rules the review cannot judge from added
  lines: "one storage method per file", "consts at the top", "constructor
  right after its type", "a wrapper left with one field gets deleted". Ids
  are unique across the whole file, since findings cite the id alone.

Rules are Go-only, because the review filters the diff to `*.go`. A
convention about YAML or shell has no tier here — say so rather than writing
a rule that will never be checked.

Place the rule under the `# <theme>` heading it belongs to (comments, naming,
error handling, structure …), or propose a new theme. The review fans out one
subagent per theme, so a theme is the unit of attention — keep themes
coherent and roughly 5–8 rules each.

Draft the rule, show it to the user in full, and write it only after they
approve the wording. Where a rule is subtle, test it the way the review will:
ask a subagent to judge one real diff hunk against the draft, and see whether
it lands where you expected.

**Graduation.** A taste rule that later turns out to be structurally
checkable moves to the ast-grep or golangci tier — and its taste entry is
deleted in the same pass. Two copies of one rule drift, and the prose copy is
the one nobody updates.

## Rule format conventions (lint tiers)

- `id`: kebab-case, names the convention, not the mechanism
  (`no-free-functions-over-models`, not `check-qualified-type-param`).
- `message`: Russian, self-contained — states the convention and shows the
  correct form (`order.GetAdultPassengers(), а не getAdultPassengers(order)`),
  and names the allowed exceptions. The reader is the coding agent deciding
  how to fix; the message is its only context.
- `severity: warning` unless the user asked for an absolute ban.
- Comments inside the YAML only for non-obvious matching decisions, in
  Russian.

## Maintenance

- List: `ls ~/.claude/style-guard/rules/` with each rule's `message`, the
  enabled linters in `golangci.yml`, and the rules in `taste.md` — the three
  tiers together are the full ruleset.
- Tune: edit the installed rule, then repeat validation + dry-run before
  confirming — a tune is a new rule as far as validation goes.
- Remove: delete the rule file, drop the linter block from `golangci.yml`
  (removing the whole file disarms the type-aware tier entirely), or delete
  the prose line.
- Both hooks log skips and errors to `~/.claude/style-guard/scan.log` — check
  it first when the user says a hook "isn't firing".
- A taste rule the review keeps flagging wrongly comes back here for tuning:
  usually its `Don't flag` list is missing the case, which is a smaller and
  safer edit than weakening the rule itself.

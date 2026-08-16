# style-guard

Deterministic layer of my personal Go style: the rules that are
machine-checkable get out of prompt space ("prompts for taste, tools for
law") and become ast-grep rules that a PostToolUse hook runs on every edited
Go file. Violations land back in the agent's context in the same cycle, so
the agent fixes them while the file is hot — no review round-trip.

Rules no linter can judge — abstraction height, whether a comment earns its
place — go to `taste.md` and are checked by a review pass over the diff
instead of by a hook. They deliberately do not ride in the coding session's
context, where they would compete for attention with everything else and be
followed only sometimes.

Self-contained: everything the layer knows lives in `~/.claude/style-guard/`.

## Components

- **Edit hook** (`hooks/go-style-check.sh`, PostToolUse on `Edit|Write`): runs
  `ast-grep scan` with the personal rules against the edited `*.go` file.
  Non-empty findings → stderr + exit 2, which Claude Code shows to the agent.
  Silent no-op on non-Go files and on machines without `ast-grep`/`jq`
  (skips are logged to `~/.claude/style-guard/scan.log` when the data dir
  exists, so "off" is distinguishable from "broken").
- **Stop hook** (`hooks/go-style-check-stop.sh`): the finish gate, and the
  only place structural findings actually block — PostToolUse is advisory by
  design, so ast-grep is asked again here. It gates on the Go files this
  session edited, read out of the transcript rather than off working-tree
  state: a selection of `git diff HEAD` plus untracked swept in files the
  session never touched, and on a repo whose index a rebase had mangled it
  left hundreds of untracked `.go` blocking every turn. The cost is that a
  subagent's edits, which live in its own transcript, reach PostToolUse only.
  Then the type-aware tier:
  golangci-lint with the personal `~/.claude/style-guard/golangci.yml` over
  the changed packages (`--new-from-rev HEAD`), once per turn rather than per
  edit, since golangci is too slow for the edit loop. Armed only when that
  config exists; binary resolves from PATH or the repo's `go tool`. It
  decides on the linter's exit code, not on output being non-empty — a clean
  golangci run still prints `0 issues.` to stdout — and typecheck errors are
  treated as "gate could not run" rather than as findings.
- Both ast-grep passes share `hooks/scan-added-lines.sh`, which reports only
  lines the change added and skips `Code generated … DO NOT EDIT` files.
  Scanning whole files would have the agent "fixing" pre-existing violations
  it didn't write — and would make a turn on a legacy file impossible to end.
- **Skill** (`/style-guard:add`): the single front door for "make
  this stick". Classifies a rule stated in words (structural / type-aware /
  taste) and writes it to the tier that can hold it — for the lint tiers:
  draft, prove on a fixture, dry-run over the real repo with a findings
  report, and install only on explicit approval.
- **Skill** (`/style-guard:taste-review`): the taste tier's
  enforcement. Reads the lines the branch adds, fans out one subagent per
  rule theme (so no reviewer is handed more rules than it can attend to),
  and reports findings that cite a rule id — anything uncited is dropped.
  Anchored to PR creation: review the branch, fix the findings, then open the
  PR, so the diff in the review tab is already in the user's style. Also
  invocable by hand at any point; a per-file `.reviewed` stamp (keyed on the
  file *and* on `taste.md`, so a new rule re-opens every file) keeps repeat
  passes down to a few hashes.
- **PR gate** (`hooks/pr-gate.sh`, PreToolUse on `Bash`): blocks
  `gh pr create` while any changed Go file lacks a current stamp. The skill's
  own trigger is a description, i.e. probabilistic; this makes the one moment
  that matters deterministic. Inert until `taste.md` exists.

## Data

Everything lives outside the plugin in `~/.claude/style-guard/`
(`sgconfig.yml` + `rules/*.yml`, `golangci.yml`, `taste.md`) — plugin updates
must not touch accumulated rules. The edit hook bootstraps the dir on first
run on a machine (config from `seed/`, empty `rules/`); all three tiers start
empty and grow only through /style-guard:add, so an unused tier stays inert:
no `golangci.yml` disarms the Stop hook, no `taste.md` makes the review a
no-op. Opt-out for the hooks: `touch ~/.claude/style-guard/.disabled`.

## Requirements

- [ast-grep](https://ast-grep.github.io/) on PATH (pinned install, e.g.
  release binary; hook no-ops without it)
- `jq`

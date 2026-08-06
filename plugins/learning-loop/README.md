# learning-loop

Self-learning loop that captures my personal engineering style — code style,
architecture decisions, naming, testing, error handling, PR structure,
refactoring habits, review rejections — so AI coding agents produce PRs the
way I'd write them.

## How it works

- **This skill only maintains memory.** It extracts candidate rules from
  sessions (Mode 1) and promotes approved ones (Mode 2).
- **`/learning-loop:review` verifies compliance on demand.** The rules load
  into every session, but loading doesn't guarantee the model followed them.
  The command reviews the current change (uncommitted + branch diff vs master,
  introduced lines only) against the approved memory via an independent
  `style-reviewer` subagent. Report-only; every finding quotes the exact rule
  or exemplar it violates — a finding without a citable rule is dropped. When
  a finding exposes a bad *rule*, the objection goes to `inbox.md` as a
  curation candidate, so reviews feed the loop too.
- **Application is file-based and unconditional**, three compiled channels
  kept in sync by `scripts/compile-channels.sh`:
  - Claude Code, universal taste: `~/.claude/CLAUDE.md` inlines
    `preferences.md` and `examples.md` via `@` imports — loaded at launch,
    re-read after compaction. (Deliberately not a SessionStart hook: hook
    output is capped at 10k chars and duplicated on resume.)
  - Claude Code, stack-specific: `preferences-<stack>.md` sources are
    compiled into path-scoped `~/.claude/rules/learning-loop-<stack>.md`,
    which load only when the session touches matching files — Go rules
    stay out of prose sessions and non-Go repos.
  - Codex and other agents: `~/.claude/AGENTS.md` (which `~/.codex/AGENTS.md`
    symlinks to) carries the pointer plus a compiled block with the full
    memory content inline — Codex doesn't have to *choose* to read anything.
- **Coexistence with Claude Code auto memory** (on by default in recent
  versions): territory is split. Auto memory owns per-project *facts* (build
  commands, repo layout, project quirks); learning-loop owns cross-project
  *style*. Mode 2 refuses to promote project facts — they belong to auto
  memory — and style corrections captured there are treated as duplicates
  of what the inbox already tracks.

## Layout

Plugin (this folder — versioned, immutable once installed):

- `skills/learning-loop/SKILL.md` — modes and rules of engagement
- `skills/learning-loop/scripts/find-corrections.sh` — jq distiller over
  session JSONL: every genuine user message + edit/plan rejections, tool
  noise stripped (judging what's a correction is the model's job)
- `skills/learning-loop/scripts/compile-channels.sh` — regenerates the
  path-scoped rules files and the AGENTS.md compiled block from the sources
- `skills/learning-loop/scripts/sweep-transcripts.sh` — ledger-driven sweep
  over `~/.claude/projects/` catching sessions the hook missed (`/exit`,
  crashes, resumes); run it from cron/systemd (see below)
- `skills/learning-loop/references/rule-format.md` — what a good rule looks like
- `agents/learning-extractor.md` — sonnet subagent that interactive Mode 1
  delegates extraction to, so mining a transcript doesn't run on the main
  session's (possibly pricier) model; returns candidates, never writes files
- `commands/review.md` — the `/learning-loop:review` command: diff-scoped,
  report-only compliance review against the approved memory
- `agents/style-reviewer.md` — subagent the review command delegates to
  (model: inherit — review judgment should match the session); returns
  rule-citing findings, never writes files
- `hooks/` — SessionEnd hook for automatic extraction (on by default)
- `.claude-plugin/plugin.json` — plugin manifest

State (outside the plugin, in `~/.claude/learning-loop-memory/` — survives
plugin updates, synced between machines separately):

- `preferences.md` — approved universal taste (≤150 lines)
- `preferences-<stack>.md` — approved stack-specific rules with `paths:`
  frontmatter (e.g. `preferences-go-backend.md`); compiled into
  `~/.claude/rules/`
- `examples.md` — exemplar file pointers
- `inbox.md` — candidates awaiting approval
- `ledger.tsv` — processed-transcript ledger (path + bytes)
- `.disabled` — turns the SessionEnd hook and sweep off (absent by default = active)
- `model` — model for headless extraction runs, one line (absent = sonnet)
- `extract.log` — headless extraction output and skip reasons

## Installation

```
/plugin marketplace add dp92987/claude-plugins
/plugin install learning-loop@dp92987-plugins
```

Codex side: clone the marketplace repo and symlink the skill —
`ln -s <repo>/plugins/learning-loop/skills/learning-loop ~/.codex/skills/learning-loop`.
The memory files and the AGENTS.md pointer are shared; only the trigger
differs (Codex has no SessionEnd hook — use a cron sweep over
`~/.codex/sessions/`).

## The automatic hook

The hook is **on by default**: every session end spawns a background
`claude -p` (sonnet by default; Read/Bash plus Edit/Write path-scoped to
`inbox.md`) running Mode 1 non-interactively on the transcript. Turn it
off with:

```bash
touch ~/.claude/learning-loop-memory/.disabled
```

Re-enable with `rm ~/.claude/learning-loop-memory/.disabled`. Pick the
extraction model (used by both the hook and the sweep) with:

```bash
echo haiku > ~/.claude/learning-loop-memory/model   # haiku, opus, or a full model ID
```

Remove the file to go back to sonnet. Each extraction logs the model it
ran with, and a bad model name surfaces as a `claude` error in
`extract.log`.

The same file steers interactive "learn from this session" runs: Mode 1
delegates extraction to the bundled `learning-extractor` subagent (sonnet
by default), passing the file's value as the model override when it is an
alias (`haiku`/`sonnet`/`opus`); full model IDs apply to headless runs
only. The interview and inbox writes stay in the main session — the
subagent can't talk to the user and has no write access. Safeguards: a
`LEARNING_LOOP_ACTIVE` env guard prevents the headless run from re-triggering
itself, transcripts under 20KB are skipped, the ledger skips transcripts
already processed at their current size, and the path-scoped write
permissions mean the headless run can never modify `preferences.md` or
`examples.md`. Every skipped or started extraction logs one line to
`~/.claude/learning-loop-memory/extract.log`, so "off" is distinguishable
from "broken".

## The sweep (catching what the hook misses)

SessionEnd doesn't fire on `/exit`, crashes, or terminal kills, and resumed
sessions grow after their last extraction. `scripts/sweep-transcripts.sh`
covers all of that: it walks `~/.claude/projects/*/*.jsonl`, extracts any
transcript that is new or has grown since its ledger entry (skipping files
modified in the last 30 minutes — possibly a live session — and its own
extraction-run transcripts), capped per run (default 5). Schedule it daily,
e.g. a systemd user timer:

```ini
# ~/.config/systemd/user/learning-loop-sweep.service
[Unit]
Description=learning-loop transcript sweep
[Service]
Type=oneshot
ExecStart=<path-to-plugin>/skills/learning-loop/scripts/sweep-transcripts.sh 5

# ~/.config/systemd/user/learning-loop-sweep.timer
[Unit]
Description=Daily learning-loop transcript sweep
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload && systemctl --user enable --now learning-loop-sweep.timer
```

The hook only fires when the folder is loaded **as a plugin** (hooks.json uses
`${CLAUDE_PLUGIN_ROOT}`, so the folder is relocatable). Loaded as a plain
personal skill (`~/.claude/skills/learning-loop`), Modes 1–2 work but no hook
runs.

## Versioning and updates

The plugin lives in the `dp92987-plugins` marketplace repo. To ship a change:

1. Edit here, then bump `version` in both `.claude-plugin/plugin.json` and
   the repo-root `.claude-plugin/marketplace.json` — Claude Code uses the
   version field to detect updates.
2. `claude plugin validate .` from the repo root, commit, push.
3. On each machine: `/plugin` → update (or uninstall + install), then
   `/reload-plugins` — hook changes don't hot-reload.

Note: editing this folder does **not** affect the installed plugin — Claude
Code runs from a cached copy. Changes reach it only through the update flow
above.

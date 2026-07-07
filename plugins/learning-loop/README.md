# learning-loop

Self-learning loop that captures my personal engineering style — code style,
architecture decisions, naming, testing, error handling, PR structure,
refactoring habits, review rejections — so AI coding agents produce PRs the
way I'd write them.

## How it works

- **This skill only maintains memory.** It extracts candidate rules from
  sessions (Mode 1) and promotes approved ones (Mode 2).
- **Application is file-based and unconditional**, one channel per agent:
  - Claude Code: `~/.claude/CLAUDE.md` inlines `preferences.md` and
    `examples.md` via `@` imports — loaded in full at launch, re-read from
    disk after compaction, nothing for the model to skip. (Deliberately not
    a SessionStart hook: hook output is capped at 10k chars, lost after
    compaction, and duplicated on resume.)
  - Codex and other agents: `~/.claude/AGENTS.md` (which `~/.codex/AGENTS.md`
    symlinks to) tells them to read the same files before implementing or
    reviewing code. No skill routing involved either way.

## Layout

Plugin (this folder — versioned, immutable once installed):

- `skills/learning-loop/SKILL.md` — modes and rules of engagement
- `skills/learning-loop/scripts/find-corrections.sh` — jq distiller over
  session JSONL: every genuine user message + edit/plan rejections, tool
  noise stripped (judging what's a correction is the model's job)
- `skills/learning-loop/references/rule-format.md` — what a good rule looks like
- `hooks/` — SessionEnd hook for automatic extraction (on by default)
- `.claude-plugin/plugin.json` — plugin manifest

State (outside the plugin, in `~/.claude/learning-loop-memory/` — survives
plugin updates, synced between machines separately):

- `preferences.md` — approved rules (≤150 lines, repo-prefixed where specific)
- `examples.md` — exemplar file pointers
- `inbox.md` — candidates awaiting approval
- `.disabled` — turns the SessionEnd hook off (absent by default = hook active)
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
`claude -p` (sonnet; Read/Bash plus Edit/Write path-scoped to `inbox.md`)
running Mode 1 non-interactively on the transcript. Turn it off with:

```bash
touch ~/.claude/learning-loop-memory/.disabled
```

Re-enable with `rm ~/.claude/learning-loop-memory/.disabled`. Safeguards: a
`LEARNING_LOOP_ACTIVE` env guard prevents the headless run from re-triggering
itself, transcripts under 20KB are skipped, and the path-scoped write
permissions mean the headless run can never modify `preferences.md` or
`examples.md`. Every skipped or started extraction logs one line to
`~/.claude/learning-loop-memory/extract.log`, so "off" is distinguishable
from "broken".

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

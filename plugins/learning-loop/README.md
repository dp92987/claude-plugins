# learning-loop

Self-learning loop that captures my personal engineering style — code style,
architecture decisions, naming, testing, error handling, PR structure,
refactoring habits, review rejections — so AI coding agents produce PRs the
way I'd write them.

## How it works

- **This skill only maintains memory.** It extracts candidate rules from
  sessions (Mode 1) and promotes approved ones (Mode 2).
- **Application is unconditional**: `~/.claude/AGENTS.md` (symlinked from
  `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`) tells every coding agent to
  read `~/.claude/learning-loop-memory/preferences.md` and `examples.md`
  before implementing. No skill routing involved.

## Layout

Plugin (this folder — versioned, immutable once installed):

- `skills/learning-loop/SKILL.md` — modes and rules of engagement
- `skills/learning-loop/scripts/find-corrections.sh` — jq pre-filter over
  session JSONL for correction signals
- `skills/learning-loop/references/rule-format.md` — what a good rule looks like
- `hooks/` — SessionEnd hook for automatic extraction (disabled by default)
- `.claude-plugin/plugin.json` — plugin manifest

State (outside the plugin, in `~/.claude/learning-loop-memory/` — survives
plugin updates, synced between machines separately):

- `preferences.md` — approved rules (≤150 lines, repo-prefixed where specific)
- `examples.md` — exemplar file pointers
- `inbox.md` — candidates awaiting approval
- `.enabled` — arms the SessionEnd hook (absent by default)
- `extract.log` — headless extraction output

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

## Arming the automatic hook

The hook ships **disabled**: `hooks/on-session-end.sh` exits immediately unless
`~/.claude/learning-loop-memory/.enabled` exists. After manual testing:

```bash
mkdir -p ~/.claude/learning-loop-memory
touch ~/.claude/learning-loop-memory/.enabled
```

Disarm with `rm ~/.claude/learning-loop-memory/.enabled`. When armed, session
end spawns a background `claude -p` (haiku, tools limited to
Read/Bash/Edit/Write) running Mode 1 non-interactively on the transcript.
Safeguards: a `LEARNING_LOOP_ACTIVE` env guard prevents the headless run from
re-triggering itself, and transcripts under 20KB are skipped. Output lands in
`~/.claude/learning-loop-memory/extract.log`.

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

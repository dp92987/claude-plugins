# claude-plugins

Personal Claude Code plugin marketplace by dp92987.

## Install

Add the marketplace in Claude Code:

```
/plugin marketplace add dp92987/claude-plugins
```

Then install a plugin:

```
/plugin install <plugin>@dp92987-claude-plugins
```

## Plugins

### [codex-tandem](plugins/codex-tandem/)

Claude orchestrates, Codex codes. A SessionStart hook routes bounded implementation work to the OpenAI Codex CLI by default: Claude does requirements, research, planning, briefs, and verification; Codex writes the code. Cross-model review is built in — Claude reviews every Codex diff, and the `codex-review` skill (with an adversarial pre-PR mode) covers code Claude wrote directly. Requires an installed and authenticated `codex` CLI.

Skills: `codex-implementation`, `codex-review`.

### [learning-loop](plugins/learning-loop/)

Self-learning loop that captures personal engineering style — code style, architecture decisions, naming, testing preferences, things rejected in review — into memory files (`~/.claude/learning-loop-memory/`) that coding agents consume via an AGENTS.md pointer. Bundles a SessionEnd hook for automatic extraction from finished sessions.

Skills: `learning-loop`.

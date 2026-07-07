# codex-tandem

Claude orchestrates, Codex codes. This plugin routes coding work between Claude Code and the [OpenAI Codex CLI](https://github.com/openai/codex): Claude does requirements, research, planning, briefs, and verification; Codex writes the implementation.

## How it works

A **SessionStart hook** injects the routing policy into every session:

- Bounded implementation tasks (features, fixes, scoped refactors) go to Codex by default via the `codex-implementation` skill — the user doesn't have to ask.
- Trivial edits (one-liners, typos, config tweaks) stay with Claude; a Codex round-trip costs more than it saves.
- **Review rules** — Codex-written code gets two reviews: Claude's contextual diff review plus an independent fresh-session `codex-review` of the final diff. Substantial Claude-written code (including takeovers) gets a `codex-review` before it's done. Trivial Claude edits skip per-change review and are swept up by the adversarial whole-branch gate before a PR ships.
- **The PR gate is enforced** — a PreToolUse hook blocks `gh pr create` on branches with no recorded adversarial review (the review records a marker in `.git/`; ask to skip and Claude creates the marker explicitly). Fails open if `jq`/`git`/`codex` are missing.
- Bulk read-only work (large code audits, log analysis, data crunching) can be offloaded with `codex exec -s read-only` directly — no skill needed.
- **Escalation** — delegation is a default, not a limit: if Codex is still off track after two follow-up rounds, Claude takes over and finishes the work itself, saying so.

Disable the routing policy without uninstalling: `touch ~/.claude/.codex-routing-off`.

## Skills

- **codex-implementation** — Claude writes a self-contained brief (goal, acceptance criteria, constraints, verification), dispatches `codex exec -s workspace-write` in the background, then verifies the result (diff review + build/tests) and finishes with an independent `codex-review` of the final diff. Real problems go back to Codex via `codex exec resume <session-id>`, capped at 2 rounds; past the cap, Claude takes over.
- **codex-review** — runs `codex exec review` against uncommitted changes, a branch, or a commit, passing task context so Codex isn't reviewing cold; Claude vets the findings, labels confirmed vs unverified, and offers to fix the valid ones. An adversarial mode ("find the strongest reasons this should not ship") backs the pre-PR gate.

## Learning-loop integration

Codex picks up the user's engineering style automatically: `~/.codex/AGENTS.md` points to the learning-loop memory (`~/.claude/learning-loop-memory/preferences.md` and `examples.md`), which Codex reads natively. Briefs additionally name task-relevant exemplar files, and reviews explicitly check conformance against `preferences.md`.

## Requirements

- `codex` CLI installed and authenticated (`codex login`).
- Model and reasoning effort come from your `~/.codex/config.toml`; the skills don't override them.

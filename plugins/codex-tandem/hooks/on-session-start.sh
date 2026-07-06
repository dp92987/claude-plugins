#!/usr/bin/env bash
# SessionStart hook: inject the Claude-orchestrates/Codex-codes routing policy.
# Disable without uninstalling: touch ~/.claude/.codex-routing-off
set -u

[ -f "$HOME/.claude/.codex-routing-off" ] && exit 0

if ! command -v codex >/dev/null 2>&1; then
  cat <<'MSG'
codex-tandem plugin: the codex CLI is not installed, so the Codex routing policy is
inactive this session. If the user asks about Codex or delegation, tell them:
npm install -g @openai/codex && codex login
MSG
  exit 0
fi

cat <<'POLICY'
Codex routing policy (from the codex-tandem plugin):

Division of labor for coding work: Claude does requirements, research, planning,
briefs, diff review, tests, and user communication; Codex writes the code.

- Route bounded implementation tasks (features, fixes, refactors with clear scope)
  to the codex-implementation skill by default — do not implement them directly.
- Exception: trivial edits (one-liners, typos, config tweaks, small fixes surfaced
  while reviewing a Codex diff) are faster done directly by Claude.
- Review rules:
  - Codex-written code gets two reviews, both built into codex-implementation:
    Claude's contextual diff review, then an independent codex-review of the
    final diff (fresh session, no conversation context).
  - Substantial Claude-written code (including takeovers after a failed
    delegation) gets a codex-review before it is considered done.
  - Trivial Claude edits skip immediate review; the adversarial whole-branch
    codex-review offered before a PR ships sweeps them up.
- Bulk read-only work (large code audits, log analysis, data crunching) can also
  be offloaded to Codex directly: `codex exec -s read-only` with a self-contained
  prompt. Claude still does the thinking-heavy research itself.
- If the codex CLI fails mid-session, say so and continue with Claude after the
  user confirms.
POLICY

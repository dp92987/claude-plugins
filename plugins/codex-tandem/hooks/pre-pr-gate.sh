#!/usr/bin/env bash
# PreToolUse gate: block `gh pr create` until the adversarial whole-branch
# codex-review has run for this branch. The review records a marker file;
# absence of the marker means unreviewed. Fail open on any missing dependency —
# the gate must never break PR creation for unrelated reasons.
set -u

[ -f "$HOME/.claude/.codex-routing-off" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v codex >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
case "$CMD" in
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
GITDIR="$(git -C "${CWD:-.}" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
BRANCH="$(git -C "${CWD:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
MARKER="$GITDIR/codex-tandem-gate-$(printf '%s' "$BRANCH" | tr '/' '-')"
[ -f "$MARKER" ] && exit 0

cat >&2 <<MSG
codex-tandem gate: no adversarial branch review is recorded for '$BRANCH'.
Run the codex-review whole-branch adversarial review first — on completion it
records $MARKER and this gate opens. If the user explicitly wants to ship
without the review, create that marker file yourself and retry.
MSG
exit 2

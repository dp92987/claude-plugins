#!/usr/bin/env bash
# SessionEnd hook: headless learning-loop Mode 1 on the finished session's transcript.
# Ships disabled — arm with: touch ~/.claude/learning-loop-memory/.enabled
set -u

MEMORY_DIR="$HOME/.claude/learning-loop-memory"

# disabled by default (stays silent: absence of .enabled is user-checkable)
[ -f "$MEMORY_DIR/.enabled" ] || exit 0

# recursion guard: the headless run below ends its own session and would re-fire this hook
[ -n "${LEARNING_LOOP_ACTIVE:-}" ] && exit 0

# armed but skipped — log the reason so "off" is distinguishable from "broken"
skip() { echo "$(date -Is) skip: $1" >> "$MEMORY_DIR/extract.log"; exit 0; }

command -v jq >/dev/null 2>&1 || skip "jq not on PATH"
command -v claude >/dev/null 2>&1 || skip "claude not on PATH"

INPUT="$(cat)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"

# skip trivial sessions: transcript missing, empty, or under ~20KB
[ -n "$TRANSCRIPT" ] || skip "no transcript_path in hook input"
[ -f "$TRANSCRIPT" ] || skip "transcript missing: $TRANSCRIPT"
SIZE=$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)
[ "$SIZE" -ge 20000 ] || skip "transcript too small ($SIZE bytes): $TRANSCRIPT"

# slash-form invocation is the documented headless way to load a skill;
# a prose "use the skill" prompt may never load SKILL.md at all
PROMPT="/learning-loop:learning-loop Mode 1, non-interactive, on transcript: $TRANSCRIPT"

mkdir -p "$MEMORY_DIR"
echo "$(date -Is) extract: $TRANSCRIPT ($SIZE bytes)" >> "$MEMORY_DIR/extract.log"

# background so we don't delay Claude Code shutdown; log for debugging.
# Edit/Write are path-scoped to the inbox: Mode 1 must never be able to touch
# preferences.md/examples.md, which every future session inlines.
nohup env LEARNING_LOOP_ACTIVE=1 \
  claude -p "$PROMPT" \
  --model haiku \
  --allowedTools "Read,Bash,Edit(//$HOME/.claude/learning-loop-memory/inbox.md),Write(//$HOME/.claude/learning-loop-memory/inbox.md)" \
  >> "$MEMORY_DIR/extract.log" 2>&1 &

exit 0

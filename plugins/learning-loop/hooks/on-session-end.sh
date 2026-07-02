#!/usr/bin/env bash
# SessionEnd hook: headless learning-loop Mode 1 on the finished session's transcript.
# Ships disabled — arm with: touch ~/.claude/learning-loop-memory/.enabled
set -u

MEMORY_DIR="$HOME/.claude/learning-loop-memory"

# disabled by default
[ -f "$MEMORY_DIR/.enabled" ] || exit 0

# recursion guard: the headless run below ends its own session and would re-fire this hook
[ -n "${LEARNING_LOOP_ACTIVE:-}" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"

# skip trivial sessions: transcript missing, empty, or under ~20KB
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
SIZE=$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)
[ "$SIZE" -ge 20000 ] || exit 0

PROMPT="Use the learning-loop skill, Mode 1, non-interactive, on transcript: $TRANSCRIPT"

mkdir -p "$MEMORY_DIR"

# background so we don't delay Claude Code shutdown; log for debugging
nohup env LEARNING_LOOP_ACTIVE=1 \
  claude -p "$PROMPT" \
  --model haiku \
  --allowedTools "Read,Bash,Edit,Write" \
  >> "$MEMORY_DIR/extract.log" 2>&1 &

exit 0

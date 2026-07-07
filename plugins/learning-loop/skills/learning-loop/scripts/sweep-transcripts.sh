#!/usr/bin/env bash
# Sweep ~/.claude/projects/ for session transcripts the SessionEnd hook missed:
# /exit and crashes never fire the hook, and resumed sessions grow after their
# last extraction. The ledger (path<TAB>bytes) records what was processed;
# only new or grown transcripts are extracted. Run from cron/systemd — see
# README. Usage: sweep-transcripts.sh [max-extractions-per-run] (default 5).
set -u

MEMORY_DIR="$HOME/.claude/learning-loop-memory"
LEDGER="$MEMORY_DIR/ledger.tsv"
MAX="${1:-5}"

[ -f "$MEMORY_DIR/.disabled" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || exit 0
mkdir -p "$MEMORY_DIR"

log() { echo "$(date -Is) sweep: $1" >> "$MEMORY_DIR/extract.log"; }
ledger_get() { awk -F'\t' -v p="$1" '$1==p{s=$2} END{print s}' "$LEDGER" 2>/dev/null; }
ledger_put() { { grep -vF "$1	" "$LEDGER" 2>/dev/null; printf '%s\t%s\n' "$1" "$2"; } > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"; }

NOW="$(date +%s)"
COUNT=0
for T in "$HOME"/.claude/projects/*/*.jsonl; do
  [ -f "$T" ] || continue
  SIZE=$(wc -c < "$T" 2>/dev/null || echo 0)
  [ "$SIZE" -ge 20000 ] || continue

  REC="$(ledger_get "$T")"
  [ -n "$REC" ] && [ "$SIZE" -le "$REC" ] && continue

  # a transcript modified recently may belong to a live session — let it finish
  MTIME=$(stat -c %Y "$T" 2>/dev/null || echo 0)
  [ $((NOW - MTIME)) -lt 1800 ] && continue

  # never mine our own extraction runs — that would feed the loop to itself
  if head -c 200000 "$T" | grep -qF '/learning-loop:learning-loop Mode 1'; then
    ledger_put "$T" "$SIZE"
    continue
  fi

  # cap guard sits before dispatch so a cap of N means at most N extractions
  [ "$COUNT" -ge "$MAX" ] && { log "reached per-run cap ($MAX)"; break; }

  log "extract: $T ($SIZE bytes)"
  env LEARNING_LOOP_ACTIVE=1 \
    claude -p "/learning-loop:learning-loop Mode 1, non-interactive, on transcript: $T" \
    --model sonnet \
    --allowedTools "Read,Bash,Edit(//$HOME/.claude/learning-loop-memory/inbox.md),Write(//$HOME/.claude/learning-loop-memory/inbox.md)" \
    >> "$MEMORY_DIR/extract.log" 2>&1
  ledger_put "$T" "$SIZE"
  COUNT=$((COUNT + 1))
done
log "done: $COUNT extraction(s)"

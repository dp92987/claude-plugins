#!/usr/bin/env bash
# PostToolUse-hook (Edit|Write): ast-grep по изменённому Go-файлу.
# exit 2 не блокирует (tool уже отработал), но stderr показывается агенту —
# нарушение чинится в том же цикле, пока файл в контексте горячий.
# Выключение: touch ~/.claude/style-guard/.disabled
set -u

DATA_DIR="$HOME/.claude/style-guard"
# CLAUDE_PLUGIN_ROOT в окружении хука не гарантирован докой (были случаи, когда
# его нет) — под set -u это убило бы скрипт до единственного шага без логирования
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MAX_FINDINGS=50

[ -f "$DATA_DIR/.disabled" ] && exit 0

# armed but skipped — лог только при существующей директории данных,
# чтобы на машинах без style-guard hook оставался бесследным no-op
skip() { [ -d "$DATA_DIR" ] && echo "$(date -Is) skip: $1" >> "$DATA_DIR/scan.log"; exit 0; }

command -v jq >/dev/null 2>&1 || skip "jq not on PATH"
command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not on PATH"

FILE="$(jq -r '.tool_input.file_path // empty')"
case "$FILE" in
  *.go) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

# bootstrap: первый запуск на машине создаёт пустую директорию данных;
# правила появляются только через /style-guard:add
if [ ! -f "$DATA_DIR/sgconfig.yml" ]; then
  mkdir -p "$DATA_DIR/rules"
  cp "$PLUGIN_ROOT/seed/sgconfig.yml" "$DATA_DIR/sgconfig.yml" 2>>"$DATA_DIR/scan.log"
  [ -f "$DATA_DIR/sgconfig.yml" ] || skip "bootstrap failed: no seed at $PLUGIN_ROOT"
fi

# лог не растёт бесконечно: хук пишет в него на каждой правке
[ -f "$DATA_DIR/scan.log" ] && [ "$(wc -c < "$DATA_DIR/scan.log")" -gt 1000000 ] &&
  tail -c 200000 "$DATA_DIR/scan.log" > "$DATA_DIR/scan.log.tmp" &&
  mv "$DATA_DIR/scan.log.tmp" "$DATA_DIR/scan.log"

FINDINGS="$("$PLUGIN_ROOT/hooks/scan-added-lines.sh" "$DATA_DIR/sgconfig.yml" "$FILE" 2>>"$DATA_DIR/scan.log")"

[ -n "$FINDINGS" ] || exit 0

COUNT="$(printf '%s\n' "$FINDINGS" | wc -l)"
printf '%s\n' "$FINDINGS" | head -n "$MAX_FINDINGS" >&2
[ "$COUNT" -gt "$MAX_FINDINGS" ] && echo "… ещё $((COUNT - MAX_FINDINGS)) нарушений" >&2
exit 2

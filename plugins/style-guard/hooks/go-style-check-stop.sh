#!/usr/bin/env bash
# Stop-hook: golangci-lint по диффу изменённых Go-файлов с личным конфигом.
# Type-aware тир слишком медленный для запуска на каждый Edit, поэтому гейт
# один раз на завершение хода; --new-from-rev HEAD режет отчёт до изменённых
# строк, чтобы старые нарушения файла не блокировали ход.
# exit 2 блокирует завершение и возвращает нарушения агенту.
set -u

DATA_DIR="$HOME/.claude/style-guard"
CFG="$DATA_DIR/golangci.yml"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

[ -f "$DATA_DIR/.disabled" ] && exit 0
[ -d "$DATA_DIR" ] || exit 0

skip() { echo "$(date -Is) stop-skip: $1" >> "$DATA_DIR/scan.log"; exit 0; }

command -v jq >/dev/null 2>&1 || skip "jq not on PATH"

INPUT="$(cat)"
# ход уже продолжен этим же хуком — не блокировать повторно
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
[ -d "$CWD" ] || exit 0
cd "$CWD" || exit 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$TOP" || exit 0
git rev-parse HEAD >/dev/null 2>&1 || exit 0

CHANGED="$( { git diff --name-only HEAD -- '*.go'; git ls-files --others --exclude-standard -- '*.go'; } | sort -u )"
[ -n "$CHANGED" ] || exit 0

# ast-grep-тир: PostToolUse только совещательный (tool уже отработал), поэтому
# структурные находки переспрашиваются здесь — это единственное место, где они
# блокируют. Дёшево: доли секунды на файл
SG="$(printf '%s\n' "$CHANGED" | xargs -r -d '\n' "$PLUGIN_ROOT/hooks/scan-added-lines.sh" \
  "$DATA_DIR/sgconfig.yml" 2>>"$DATA_DIR/scan.log")"
if [ -n "$SG" ]; then
  printf '%s\n' "$SG" | head -n 50 >&2
  exit 2
fi

# type-aware тир: личный golangci-конфиг появляется только через
# /style-guard:add; без него тира нет
[ -f "$CFG" ] || exit 0

# golangci-lint: бинарь в PATH или объявленный в репо go tool
if command -v golangci-lint >/dev/null 2>&1; then
  GCL="golangci-lint"
elif go tool golangci-lint version >/dev/null 2>&1; then
  GCL="go tool golangci-lint"
else
  skip "golangci-lint not available (PATH or go tool)"
fi

# один запуск на все затронутые пакеты: отдельный вызов на директорию
# множит холодный старт линтера на число пакетов.
# -d '\n': пути с пробелами не должны разваливаться на несколько аргументов
DIRS="$(printf '%s\n' "$CHANGED" | xargs -r -d '\n' -n1 dirname | sort -u | sed 's|^|./|;s|$|/|')"
# shellcheck disable=SC2086 # $GCL и $DIRS должны разбиться на слова
OUT="$($GCL run -c "$CFG" --new-from-rev HEAD --color never $DIRS 2>>"$DATA_DIR/scan.log")"
RC=$?

# решение по коду возврата, а не по непустоте вывода: на чистом прогоне
# golangci печатает в stdout «0 issues.» — проверка на непустоту блокировала бы
# каждый ход. 1 = есть находки, 0 = чисто, остальное = линтер не отработал
case "$RC" in
  0) exit 0 ;;
  1) ;;
  *) skip "golangci-lint rc=$RC" ;;
esac

# typecheck-ошибки --new-from-rev не фильтрует: временно некомпилирующееся
# дерево вывалило бы стену ошибок о чужих файлах вместо стилевых находок
FINDINGS="$(printf '%s\n' "$OUT" | grep -v '(typecheck)$')"
case "$FINDINGS" in
  *:*) printf '%s\n' "$FINDINGS" >&2; exit 2 ;;
  *) skip "only typecheck errors, gate skipped" ;;
esac

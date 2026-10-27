#!/usr/bin/env bash
# PreToolUse-хук (Bash): не даёт закоммитить в ветке тикета код, который не прошёл
# автоматические проверки шага 5а или в котором проверяющий шага 5б нашёл
# невыполненный критерий. Порядок шагов задан в SKILL.md, но инструкцию модель
# может пропустить; хук — её детерминированный дублёр.
# exit 2 блокирует вызов инструмента и показывает stderr агенту.
set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' | tr '\n' ' ')"

# git с глобальными флагами перед подкомандой (git -C <путь> commit) тоже коммит
printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' || exit 0
case "$CMD" in *--help*) exit 0 ;; esac

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
[ -d "$CWD" ] || exit 0
cd "$CWD" || exit 0
git rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

BRANCH="$(git branch --show-current 2>/dev/null)"
KEY="$(printf '%s' "$BRANCH" | grep -oE '[A-Za-z][A-Za-z0-9]+-[0-9]+' | head -n 1 | tr '[:lower:]' '[:upper:]')"
[ -n "$KEY" ] || exit 0
ACC="$HOME/.cache/$KEY/acceptance.md"
# файла критериев нет — ветку ведёт не конвейер ticket-to-pr, охранять нечего
[ -f "$ACC" ] || exit 0

RESULT="$(awk '/^## Итог верификации/ { on = 1; next } /^## / { on = 0 } on' "$ACC")"
CHECKED="$(printf '%s\n' "$RESULT" | sed -nE 's/^проверено: ([0-9a-f]+).*/\1/p' | head -n 1)"

if [ -z "$CHECKED" ]; then
  cat >&2 <<EOF
ticket-to-pr: в $ACC нет строки «проверено:» — автоматические проверки шага 5а
для этого кода не прогонялись. Прогони шаг 5а (он запишет отпечаток через
scripts/tree-hash) и повтори коммит.
EOF
  exit 2
fi

NOW="$(bash "$(dirname "$0")/../scripts/tree-hash" 2>/dev/null)" || exit 0
if [ "$NOW" != "$CHECKED" ]; then
  cat >&2 <<EOF
ticket-to-pr: код менялся после последних автоматических проверок (шаг 5а).
Повтори шаг 5а, а шаг 5б — если правка задела код, которым доказан критерий,
и повтори коммит.
EOF
  exit 2
fi

FAILED="$(printf '%s\n' "$RESULT" | grep -E '^[0-9]+\. не выполнен' || true)"
if [ -n "$FAILED" ]; then
  cat >&2 <<EOF
ticket-to-pr: проверяющий шага 5б отметил невыполненные критерии:
$FAILED
Доделай и проверь заново; не сошлось за два круга — останов до коммита с отчётом.
EOF
  exit 2
fi

exit 0

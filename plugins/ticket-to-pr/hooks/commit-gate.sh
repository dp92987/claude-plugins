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

DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
[ -d "$DIR" ] || exit 0

ambiguous() {
  cat >&2 <<EOF
ticket-to-pr: не удалось однозначно определить, в каком репозитории идёт коммит
(путь в «cd» или «git -C» задан переменной или подстановкой). Закоммить
простой командой «git commit …» из ворктри тикета.
EOF
  exit 2
}

# каталог коммита — не всегда cwd сессии: «cd <путь> && git commit» и
# «git -C <путь> commit» коммитят другое дерево, и проверять надо его
resolve() {
  local p="$1"
  p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"
  case "$p" in *'$'*|*'`'*) ambiguous ;; esac
  case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) DIR="$p" ;; *) DIR="$DIR/$p" ;; esac
}
CD_PATH="$(printf '%s' "$CMD" | grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^;&|[:space:]]+' | tail -n 1 | sed -E 's/^[;&|[:space:]]*cd[[:space:]]+//')"
[ -n "$CD_PATH" ] && resolve "$CD_PATH"
C_PATH="$(printf '%s' "$CMD" | grep -oE '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit' | grep -oE -- '-C[[:space:]]+[^[:space:]]+' | tail -n 1 | sed -E 's/^-C[[:space:]]+//')"
[ -n "$C_PATH" ] && resolve "$C_PATH"

[ -d "$DIR" ] || exit 0
cd "$DIR" || exit 0
git rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

BRANCH="$(git branch --show-current 2>/dev/null)"
KEY="$(printf '%s' "$BRANCH" | grep -oE '[A-Za-z][A-Za-z0-9]+-[0-9]+' | head -n 1 | tr '[:lower:]' '[:upper:]')"
[ -n "$KEY" ] || exit 0
ACC="$HOME/.cache/$KEY/acceptance.md"
# файла критериев нет — ветку ведёт не конвейер ticket-to-pr, охранять нечего
[ -f "$ACC" ] || exit 0

RESULT="$(awk '/^## Итог верификации/ { on = 1; next } /^## / { on = 0 } on' "$ACC")"

# невыполненный критерий блокирует независимо от отпечатка: сбой хэширования
# не должен открывать дорогу коду, который проверяющий уже отверг
FAILED="$(printf '%s\n' "$RESULT" | grep -E '^[0-9]+\. не выполнен' || true)"
if [ -n "$FAILED" ]; then
  cat >&2 <<EOF
ticket-to-pr: проверяющий шага 5б отметил невыполненные критерии:
$FAILED
Доделай и проверь заново; не сошлось за два круга — останов до коммита с отчётом.
EOF
  exit 2
fi

CHECKED="$(printf '%s\n' "$RESULT" | sed -nE 's/^проверено: ([0-9a-f]+).*/\1/p' | head -n 1)"
if [ -z "$CHECKED" ]; then
  cat >&2 <<EOF
ticket-to-pr: в $ACC нет строки «проверено:» — автоматические проверки шага 5а
для этого кода не прогонялись. Прогони шаг 5а (он запишет отпечаток через
scripts/tree-hash) и повтори коммит.
EOF
  exit 2
fi

# коммит записывает индекс, а не рабочее дерево: сверяется именно он, иначе в
# коммит уйдёт старая версия файла, застейдженная до проверенной правки
if ! STAGED="$(git write-tree 2>&1)"; then
  cat >&2 <<EOF
ticket-to-pr: не удалось получить дерево индекса — проверить коммит нечем:
$STAGED
Разреши конфликты в индексе и повтори коммит.
EOF
  exit 2
fi
if [ "$STAGED" != "$CHECKED" ]; then
  cat >&2 <<EOF
ticket-to-pr: в индексе не то дерево, что прошло шаг 5а.
- Код менялся после проверок — повтори шаг 5а (и 5б, если правка задела код,
  которым доказан критерий).
- Иначе застейдж все проверенные изменения отдельной командой «git add …»,
  убери из ворктри посторонние файлы и коммить «git commit» без -a и без путей:
  флаги и пути меняют индекс уже после этой проверки.
EOF
  exit 2
fi

# незастейдженная правка отслеживаемого файла — непроверенный код, и «-a» или
# пути в команде добавят её в индекс уже после этой проверки
if ! git diff --quiet; then
  cat >&2 <<EOF
ticket-to-pr: в ворктри есть незастейдженные правки после шага 5а — они не
проверены. Повтори шаг 5а, застейдж изменения отдельной командой «git add …» и
коммить «git commit» без -a и без путей.
EOF
  exit 2
fi

exit 0

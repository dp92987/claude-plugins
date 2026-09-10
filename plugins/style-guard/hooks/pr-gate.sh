#!/usr/bin/env bash
# PreToolUse-hook (Bash): не даёт открыть PR (gh pr create, gh api …/pulls, GraphQL
# createPullRequest, curl к api.github.com), пока Go-изменения ветки не прошли
# taste-ревью. Триггер самого ревью — описание скилла, то есть вероятностный;
# это его детерминированный дублёр, и он опирается на тот же штамп .reviewed.
# exit 2 блокирует вызов инструмента и показывает stderr агенту.
set -u

DATA_DIR="$HOME/.claude/style-guard"
TASTE="$DATA_DIR/taste.md"
STAMP="$DATA_DIR/.reviewed"

[ -f "$DATA_DIR/.disabled" ] && exit 0
# taste-тир не используется — гейту нечего охранять
[ -f "$TASTE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v sha256sum >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
# многострочная команда с \-переносами схлопывается в одну строку, иначе grep
# не увидит флаг и путь, разнесённые по разным строкам
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' | tr '\n' ' ')"

# все способы открыть PR из shell, а не только gh pr create: gh api по умолчанию
# делает POST при любом -f/-F/--input, поэтому явного метода может и не быть
creates_pr() {
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+api([[:space:]]|$)' \
    && printf '%s' "$1" | grep -Eq '/pulls(["'"'"'[:space:]]|$)' \
    && printf '%s' "$1" | grep -Eq -- '(^|[[:space:]])(-X|--method)[[:space:]=]+[Pp][Oo][Ss][Tt]|(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|$)' \
    && return 0
  printf '%s' "$1" | grep -Eq 'createPullRequest' && return 0
  printf '%s' "$1" | grep -Eq 'api\.github\.com/repos/[^[:space:]"'"'"']+/pulls(["'"'"'[:space:]]|$)' \
    && printf '%s' "$1" | grep -Eq -- '(^|[[:space:]])(-X|--request)[[:space:]=]+[Pp][Oo][Ss][Tt]|(^|[[:space:]])(-d|--data|--data-raw|--data-binary|--json)([[:space:]=]|$)' \
    && return 0
  return 1
}
creates_pr "$CMD" || exit 0
case "$CMD" in *--help*) exit 0 ;; esac

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
[ -d "$CWD" ] || exit 0
cd "$CWD" || exit 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$TOP" || exit 0

DEFAULT_REF="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/master)"
BASE="$(git merge-base HEAD "$DEFAULT_REF" 2>/dev/null)" || exit 0
[ -n "$BASE" ] || exit 0

CHANGED="$( { git diff --name-only "$BASE" -- '*.go'; git ls-files --others --exclude-standard -- '*.go'; } | sort -u )"
[ -n "$CHANGED" ] || exit 0

TASTE_HASH="$(sha256sum "$TASTE" | cut -d' ' -f1)"
UNREVIEWED=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # сгенерированный код ревью не смотрит — не требовать штампа и здесь
  head -n 20 "$f" | grep -qE '^// Code generated .* DO NOT EDIT\.$' && continue
  abs="$TOP/$f"
  h="$(sha256sum "$f" | cut -d' ' -f1)"
  grep -qxF "$h $TASTE_HASH $abs" "$STAMP" 2>/dev/null || UNREVIEWED="$UNREVIEWED  $f
"
done <<< "$CHANGED"

[ -n "$UNREVIEWED" ] || exit 0

cat >&2 <<EOF
style-guard: эти Go-файлы ветки не проходили taste-ревью против текущего taste.md:
$UNREVIEWED
Запусти /style-guard:taste-review, поправь найденное и повтори создание PR.
EOF
exit 2

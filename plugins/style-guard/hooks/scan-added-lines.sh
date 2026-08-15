#!/usr/bin/env bash
# ast-grep по переданным Go-файлам, но только по строкам, добавленным
# относительно HEAD. Общий для обоих хуков: сканирование файла целиком
# заставляло бы агента чинить чужой код (и в Stop-гейте делало бы ход
# незавершаемым на легаси-файле).
# Использование: scan-added-lines.sh <sgconfig> <file>...
# stdout — находки, пусто = чисто.
set -u

CFG="$1"; shift
[ -f "$CFG" ] || exit 0
command -v ast-grep >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

for FILE in "$@"; do
  [ -f "$FILE" ] || continue
  case "$FILE" in *.go) ;; *) continue ;; esac
  # сгенерированный код правится генератором, а не агентом
  head -n 20 "$FILE" | grep -qE '^// Code generated .* DO NOT EDIT\.$' && continue

  # untracked и файлы вне git считаются новыми целиком
  ADDED=""
  if REPO="$(cd "$(dirname "$FILE")" && git rev-parse --show-toplevel 2>/dev/null)"; then
    REL="$(realpath --relative-to="$REPO" "$FILE" 2>/dev/null)"
    if [ -n "$REL" ] && git -C "$REPO" ls-files --error-unmatch -- "$REL" >/dev/null 2>&1; then
      ADDED="$(git -C "$REPO" diff -U0 HEAD -- "$REL" 2>/dev/null |
        awk '/^@@/ { split($3, h, ","); s = substr(h[1], 2); n = (h[2] == "" ? 1 : h[2]);
                     for (i = 0; i < n; i++) print s + i }')"
      [ -n "$ADDED" ] || continue
    fi
  fi

  # --json=stream: нужны номера строк для пересечения с ADDED (line 0-based)
  ast-grep scan -c "$CFG" --json=stream "$FILE" 2>/dev/null |
    jq -r '"\(.range.start.line + 1)\t\(.file):\(.range.start.line + 1): \(.ruleId): \(.message)"' |
    { if [ -n "$ADDED" ]; then
        awk -v added="$ADDED" 'BEGIN { n = split(added, arr, "\n"); for (i = 1; i <= n; i++) keep[arr[i]] = 1 }
                               { split($0, f, "\t"); if (f[1] in keep) print }'
      else cat; fi; } |
    cut -f2-
done

#!/usr/bin/env bash
# Строит песочницу с worktrees во всех состояниях, которые различает скилл.
# Нужна для тестов: прогонять их на реальных репозиториях нельзя, тесты удаляют.
#
#   ./make_fixture.sh /путь/к/песочнице
#
# Раскладка: ROOT/remotes/<repo>.git — bare-remote, ROOT/repos/<repo> — чекаут,
# ROOT/worktrees/<repo>/<ветка> — деревья.
set -euo pipefail

ROOT="${1:?укажи каталог песочницы}"
rm -rf "$ROOT"
mkdir -p "$ROOT"/{remotes,repos,worktrees}
ROOT="$(cd "$ROOT" && pwd)"

export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

new_repo() { # new_repo <имя> <дефолтная ветка>
  local name=$1 def=$2
  git init --quiet --bare --initial-branch="$def" "$ROOT/remotes/$name.git"
  git init --quiet --initial-branch="$def" "$ROOT/repos/$name"
  git -C "$ROOT/repos/$name" remote add origin "$ROOT/remotes/$name.git"
  echo "base" > "$ROOT/repos/$name/README.md"
  git -C "$ROOT/repos/$name" add -A
  git -C "$ROOT/repos/$name" commit --quiet -m "initial commit"
  git -C "$ROOT/repos/$name" push --quiet -u origin "$def"
  git -C "$ROOT/repos/$name" remote set-head origin "$def"
}

wt() { # wt <репо> <ветка>
  local name=$1 br=$2
  git -C "$ROOT/repos/$name" worktree add --quiet -b "$br" "$ROOT/worktrees/$name/$br"
  echo "$ROOT/worktrees/$name/$br"
}

commit_in() { # commit_in <путь> <файл> <текст> <сообщение>
  echo "$3" > "$1/$2"
  git -C "$1" add -A
  git -C "$1" commit --quiet -m "$4"
}

# ---------------------------------------------------------------- alpha (master)
new_repo alpha master
ALPHA="$ROOT/repos/alpha"

# merged-squash: три коммита, влитые в master одним. git cherry их не узнает.
P=$(wt alpha feature-squashed)
commit_in "$P" a.txt "one" "feat: часть один"
commit_in "$P" b.txt "two" "feat: часть два"
commit_in "$P" c.txt "three" "feat: часть три"
git -C "$ALPHA" merge --quiet --squash feature-squashed
git -C "$ALPHA" commit --quiet -m "feat: вся фича одним коммитом (#42)"
git -C "$ALPHA" push --quiet origin master

# pushed: чисто, есть на origin, в master ещё нет
P=$(wt alpha feature-pushed)
commit_in "$P" d.txt "four" "feat: готово к ревью"
git -C "$P" push --quiet -u origin feature-pushed

# local-only: единственная копия, нигде больше нет
P=$(wt alpha feature-local)
commit_in "$P" e.txt "five" "wip: только на этой машине"

# dirty: незакоммиченные правки поверх запушенного коммита
P=$(wt alpha feature-dirty)
commit_in "$P" f.txt "six" "feat: запушенная база"
git -C "$P" push --quiet -u origin feature-dirty
echo "недописанное" >> "$P/f.txt"
echo "новый файл" > "$P/scratch.txt"

# ------------------------------------------------------------------ beta (main)
# Дефолтная ветка main: проверяет, что master не подставляется наугад.
new_repo beta main
BETA="$ROOT/repos/beta"

# merged обычным мержем плюс игнорируемый файл — удаление сотрёт .env
P=$(wt beta fix-merged)
commit_in "$P" g.txt "seven" "fix: обычный мерж"
git -C "$BETA" merge --quiet --no-ff fix-merged -m "merge fix-merged"
git -C "$BETA" push --quiet origin main
printf '.env\n' > "$P/.gitignore"
git -C "$P" add -A && git -C "$P" commit --quiet -m "chore: игнор .env"
git -C "$BETA" merge --quiet --no-ff fix-merged -m "merge gitignore"
git -C "$BETA" push --quiet origin main
echo "SECRET=xxx" > "$P/.env"

# empty: ветка заведена, работы нет
wt beta fix-empty > /dev/null

echo "песочница готова: $ROOT"
echo "ожидаемые статусы:"
echo "  alpha/feature-squashed  merged (squash)"
echo "  alpha/feature-pushed    pushed"
echo "  alpha/feature-local     local-only"
echo "  alpha/feature-dirty     dirty"
echo "  beta/fix-merged         merged, есть игнорируемый .env"
echo "  beta/fix-empty          empty"

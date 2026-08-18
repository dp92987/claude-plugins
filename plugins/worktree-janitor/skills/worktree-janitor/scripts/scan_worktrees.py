#!/usr/bin/env python3
"""Собирает состояние всех git worktrees под указанным корнем.

Печатает текстовый отчёт, с --json — машинный. Ничего не меняет:
ни fetch, ни prune, ни remove. Читает только локальные ref'ы, поэтому
сообщает возраст последнего fetch — по нему видно, насколько свежи выводы.
"""

import argparse
import json
import os
import subprocess
import sys
import time

SKIP_DIRS = {
    "node_modules", "vendor", ".venv", "venv", "__pycache__",
    "target", "dist", "build", ".terraform", ".idea", ".gradle",
}

# Игнорируемые файлы, которые восстанавливаются сами и ничего не хранят.
# Список закрытый и намеренно узкий: всё, чего в нём нет, считается ценным.
# Ошибка в сторону «спросить» стоит одного вопроса, ошибка в другую сторону —
# стёртого .env, которого нет больше нигде.
NOISE_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini", ".localized"}
NOISE_DIRS = {
    ".idea", ".vscode", ".fleet", "__pycache__", "node_modules", "vendor",
    ".pytest_cache", ".mypy_cache", ".ruff_cache", ".gradle", ".tox",
    "target", "dist", "build", "coverage", ".next", ".turbo", ".venv", "venv",
}
NOISE_SUFFIXES = (".pyc", ".pyo", ".class", ".log", ".tmp", ".swp", ".swo",
                  ".orig", ".rej")


def is_noise(path):
    parts = path.rstrip("/").split("/")
    if any(seg in NOISE_DIRS for seg in parts):
        return True
    name = parts[-1]
    return name in NOISE_NAMES or name.endswith(NOISE_SUFFIXES)


def git(repo, *args, check=False):
    r = subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True, text=True,
    )
    if check and r.returncode != 0:
        return None
    return r


def out(repo, *args):
    """stdout команды или None, если команда упала."""
    r = git(repo, *args)
    return r.stdout.strip() if r.returncode == 0 else None


def find_repos(root):
    """Уникальные common-dir'ы всех репозиториев под root.

    Ключ — common-dir, а не путь: worktree и его главный чекаут делят один
    common-dir, поэтому дубликаты схлопываются сами.
    """
    found = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if ".git" not in dirnames and ".git" not in filenames:
            continue
        dirnames[:] = [d for d in dirnames if d != ".git"]
        common = out(dirpath, "rev-parse", "--path-format=absolute", "--git-common-dir")
        if not common:
            continue
        common = os.path.realpath(common)
        found.setdefault(common, dirpath)
    return found


def default_branch(repo):
    """Дефолтная ветка. master не гарантирован — часть репозиториев на main."""
    ref = out(repo, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if ref:
        return ref.replace("refs/remotes/", "", 1)
    for cand in ("origin/main", "origin/master", "main", "master"):
        if git(repo, "rev-parse", "--verify", "--quiet", cand).returncode == 0:
            return cand
    return None


def patch_id(repo, diff_args):
    """Стабильный patch-id набора изменений; None, если изменений нет."""
    p1 = subprocess.run(["git", "-C", repo, *diff_args], capture_output=True, text=True)
    if p1.returncode != 0 or not p1.stdout.strip():
        return None
    p2 = subprocess.run(
        ["git", "-C", repo, "patch-id", "--stable"],
        input=p1.stdout, capture_output=True, text=True,
    )
    line = p2.stdout.strip()
    return line.split()[0] if line else None


def squash_merged(repo, base, head, default):
    """True, если суммарный диф ветки лежит в дефолтной одним коммитом.

    git cherry сравнивает коммиты по одному и слепнет на squash-merge:
    после squash девять коммитов ветки не совпадут ни с чем. Здесь
    сравнивается patch-id всей ветки целиком с patch-id каждого коммита,
    добавленного в дефолтную ветку после точки ветвления.
    """
    branch_pid = patch_id(repo, ["diff", f"{base}", f"{head}"])
    if not branch_pid:
        return False
    revs = out(repo, "rev-list", f"{base}..{default}") or ""
    for rev in revs.split():
        if patch_id(repo, ["show", "--format=", rev]) == branch_pid:
            return True
    return False


def worktree_entries(repo):
    """Разбирает git worktree list --porcelain."""
    text = out(repo, "worktree", "list", "--porcelain") or ""
    entries, cur = [], {}
    for line in text.splitlines():
        if not line:
            if cur:
                entries.append(cur)
                cur = {}
            continue
        key, _, val = line.partition(" ")
        if key == "worktree":
            cur = {"path": val, "locked": False, "prunable": False, "detached": False}
        elif key == "HEAD":
            cur["head"] = val
        elif key == "branch":
            cur["branch"] = val.replace("refs/heads/", "", 1)
        elif key in ("locked", "prunable", "detached"):
            cur[key] = True
    if cur:
        entries.append(cur)
    return entries


def never_committed(repo, branch):
    """True, если ветку завели и на неё ни разу не коммитили.

    Единственная запись в reflog «branch: Created from ...» — точный признак.
    В свежих клонах reflog может отсутствовать, тогда признака нет.
    """
    if not branch:
        return False
    entries = (out(repo, "reflog", "show", "--format=%gs", branch) or "").splitlines()
    return len(entries) == 1 and entries[0].startswith("branch: Created from")


def classify(w):
    if w["dirty_tracked"] or w["untracked"]:
        return "dirty"
    if w["unique_commits"] == 0:
        if w["never_committed"] or (w["ahead_of_default"] == 0 and w["behind_default"] == 0):
            return "empty"
        return "merged"
    if w["upstream"] and w["ahead_of_upstream"] == 0:
        return "pushed"
    return "local-only"


def inspect(path, repo, default, main_path):
    w = {"path": path, "is_main": os.path.realpath(path) == os.path.realpath(main_path)}
    w["branch"] = None
    w["default_branch"] = default

    for entry in worktree_entries(repo):
        if os.path.realpath(entry["path"]) == os.path.realpath(path):
            w["branch"] = entry.get("branch")
            w["detached"] = entry.get("detached", False)
            w["locked"] = entry.get("locked", False)
            w["prunable"] = entry.get("prunable", False)
            break

    status = out(path, "status", "--porcelain") or ""
    lines = [l for l in status.splitlines() if l.strip()]
    w["dirty_tracked"] = len([l for l in lines if not l.startswith("??")])
    w["untracked"] = len([l for l in lines if l.startswith("??")])
    w["dirty_files"] = lines[:20]

    ignored = [l[3:] for l in (out(path, "status", "--porcelain", "--ignored") or "").splitlines()
               if l.startswith("!! ")]
    w["ignored"] = len(ignored)
    w["ignored_noise"] = len([p for p in ignored if is_noise(p)])
    w["ignored_review"] = [p for p in ignored if not is_noise(p)]

    # rev-parse без проверки кода возврата печатает саму строку HEAD@{upstream},
    # если upstream нет — отсюда обязательная проверка returncode.
    r = git(path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "HEAD@{upstream}")
    w["upstream"] = r.stdout.strip() if r.returncode == 0 else None
    w["ahead_of_upstream"] = w["behind_upstream"] = 0
    if w["upstream"]:
        counts = out(path, "rev-list", "--left-right", "--count", f"{w['upstream']}...HEAD")
        if counts:
            behind, ahead = counts.split()
            w["behind_upstream"], w["ahead_of_upstream"] = int(behind), int(ahead)

    w["last_commit"] = out(path, "log", "-1", "--format=%h %ad %s", "--date=short")
    w["never_committed"] = never_committed(path, w["branch"])

    w["unique_commits"] = 0
    w["ahead_of_default"] = w["behind_default"] = 0
    w["already_in_default"] = []
    w["squash_merged"] = False
    if default and not w["is_main"]:
        base = out(path, "merge-base", default, "HEAD")
        if base:
            w["merge_base"] = out(path, "log", "-1", "--format=%h %ad %s", "--date=short", base)
            w["ahead_of_default"] = int(out(path, "rev-list", "--count", f"{default}..HEAD") or 0)
            w["behind_default"] = int(out(path, "rev-list", "--count", f"HEAD..{default}") or 0)
            cherry = (out(path, "cherry", "-v", default, "HEAD") or "").splitlines()
            w["unique_commits"] = len([c for c in cherry if c.startswith("+")])
            w["already_in_default"] = [c[2:] for c in cherry if c.startswith("-")]
            w["commits"] = (out(path, "log", "--no-merges", "--format=%h %ad %s",
                               "--date=short", f"{default}..HEAD") or "").splitlines()
            if w["unique_commits"]:
                w["squash_merged"] = squash_merged(path, base, "HEAD", default)
                if w["squash_merged"]:
                    w["unique_commits"] = 0

    w["status"] = "main" if w["is_main"] else classify(w)
    return w


def scan(root):
    repos = []
    for common, sample in sorted(find_repos(root).items(), key=lambda kv: kv[1]):
        entries = worktree_entries(sample)
        if not entries:
            continue
        main_path = entries[0]["path"]
        default = default_branch(main_path)
        fetch_head = os.path.join(common, "FETCH_HEAD")
        repo = {
            "repo": main_path,
            "name": os.path.basename(main_path),
            "default_branch": default,
            "stash": len((out(main_path, "stash", "list") or "").splitlines()),
            "fetch_age_days": None,
            "worktrees": [],
        }
        if os.path.exists(fetch_head):
            repo["fetch_age_days"] = round((time.time() - os.path.getmtime(fetch_head)) / 86400, 1)
        for entry in entries:
            if not os.path.isdir(entry["path"]):
                continue
            repo["worktrees"].append(inspect(entry["path"], main_path, default, main_path))
        repos.append(repo)
    return repos


ORDER = ["dirty", "local-only", "pushed", "merged", "empty", "main"]
LABEL = {
    "dirty": "НЕЗАКОММИЧЕНО — удалять нельзя",
    "local-only": "ЕДИНСТВЕННАЯ КОПИЯ — не запушено и не в дефолтной ветке",
    "pushed": "ЗАПУШЕНО — работа есть на remote",
    "merged": "СЛИТО В ДЕФОЛТНУЮ ВЕТКУ",
    "empty": "ПУСТО — коммитов сверх дефолтной ветки нет",
    "main": "главный чекаут (не worktree)",
}


def report(repos):
    linked = [w for r in repos for w in r["worktrees"] if not w["is_main"]]
    print(f"Репозиториев: {len(repos)}. Связанных worktrees: {len(linked)}.\n")
    if not linked:
        print("Worktrees не найдены.")
        return
    for repo in repos:
        if not any(not w["is_main"] for w in repo["worktrees"]):
            continue
        age = repo["fetch_age_days"]
        age_txt = f"последний fetch {age} дн. назад" if age is not None else "fetch не выполнялся"
        print(f"=== {repo['name']}  ({repo['repo']})")
        print(f"    дефолтная ветка: {repo['default_branch']}, {age_txt}, stash в репозитории: {repo['stash']}")
        for w in sorted(repo["worktrees"], key=lambda x: ORDER.index(x["status"])):
            if w["is_main"]:
                continue
            print(f"  [{w['status']}] {w['path']}")
            print(f"      ветка: {w['branch'] or 'detached HEAD'}   {LABEL[w['status']]}")
            up = w["upstream"] or "нет"
            print(f"      upstream: {up}  ahead {w['ahead_of_upstream']} / behind {w['behind_upstream']}")
            print(f"      против {repo['default_branch']}: своих коммитов {w['unique_commits']}, "
                  f"всего сверх ветки {w['ahead_of_default']}, отстаёт на {w['behind_default']}")
            if w["squash_merged"]:
                print("      суммарный диф ветки найден в дефолтной ветке одним коммитом (squash-merge)")
            if w["dirty_tracked"] or w["untracked"]:
                print(f"      изменено файлов: {w['dirty_tracked']}, неотслеживаемых: {w['untracked']}")
                for line in w["dirty_files"]:
                    print(f"        {line}")
            if w["ignored_review"]:
                print(f"      ТРЕБУЮТ РЕШЕНИЯ перед удалением — {len(w['ignored_review'])} "
                      f"игнорируемых файлов, которых нет в git:")
                for p in w["ignored_review"][:20]:
                    print(f"        {p}")
            if w["ignored_noise"]:
                print(f"      игнорируемого мусора: {w['ignored_noise']} "
                      f"(.DS_Store, каталоги IDE и сборки — спрашивать не о чем)")
            if w.get("locked"):
                print("      worktree заблокирован (locked)")
            if w.get("prunable"):
                print("      запись помечена prunable")
            print(f"      последний коммит: {w['last_commit']}")
            print()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", nargs="?", default=".", help="каталог для обхода (по умолчанию текущий)")
    ap.add_argument("--json", action="store_true", help="машинный вывод")
    args = ap.parse_args()
    root = os.path.abspath(os.path.expanduser(args.root))
    if not os.path.isdir(root):
        sys.exit(f"нет такого каталога: {root}")
    repos = scan(root)
    if args.json:
        json.dump(repos, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        report(repos)


if __name__ == "__main__":
    main()

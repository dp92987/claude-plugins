"""Находит в команде Bash вызовы git commit и каталог, в котором каждый выполнится.

Вход: команда в stdin, cwd сессии первым аргументом. Выход — строка на коммит:
`DIR <каталог>`, `PATHS <каталог>|<причина>` (состав коммита задаёт не индекс) или
`AMBIG <причина>` (каталог не определить). Регулярки над строкой путали
порядок «cd» и коммита и не видели пути коммита, поэтому команда разбирается
токенизатором shell по простым командам в порядке выполнения.
"""
import os
import shlex
import sys

OPS = {";", "&&", "||", "|", "&", "(", ")", ";;", "|&"}
# короткие флаги commit, следом за которыми идёт значение (в том же токене или в следующем)
SHORT_WITH_VALUE = set("mFCctS")
# флаги, при которых в коммит уходит не индекс: всё отслеживаемое, только пути, интерактив
SHORT_RESHAPE = set("aoip")
LONG_WITH_VALUE = {
    "--message", "--file", "--reuse-message", "--reedit-message", "--fixup",
    "--squash", "--author", "--date", "--cleanup", "--template", "--trailer",
}
LONG_RESHAPE = {
    "--all", "--only", "--include", "--interactive", "--patch",
    "--pathspec-from-file", "--pathspec-file-nul",
}


def emit(kind, value):
    print(f"{kind} {value}")


def resolve(base, path):
    if "$" in path or "`" in path:
        return None
    if path == "~" or path.startswith("~/"):
        path = os.path.expanduser(path)
    return os.path.normpath(os.path.join(base, path))


def commit_reshape(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            return "пути после «--»"
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            if name in LONG_RESHAPE:
                return name
            if name in LONG_WITH_VALUE and "=" not in a:
                i += 1
        elif a.startswith("-") and len(a) > 1:
            for j, ch in enumerate(a[1:], 1):
                if ch in SHORT_RESHAPE:
                    return "-" + ch
                if ch in SHORT_WITH_VALUE:
                    if j == len(a) - 1:
                        i += 1
                    break
        else:
            return f"путь «{a}»"
        i += 1
    return None


def main():
    cwd = sys.argv[1]
    lex = shlex.shlex(sys.stdin.read(), posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        tokens = list(lex)
    except ValueError as e:
        emit("AMBIG", f"команду не разобрать: {e}")
        return

    commands, cur = [], []
    for t in tokens:
        if t in OPS:
            if cur:
                commands.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        commands.append(cur)

    here = cwd
    for cmd in commands:
        while cmd and "=" in cmd[0] and not cmd[0].startswith("-"):
            cmd = cmd[1:]
        if not cmd:
            continue
        if cmd[0] == "cd":
            target = cmd[1] if len(cmd) > 1 else "~"
            new = resolve(here, target) if target != "-" else None
            here = new if new else ""
            continue
        if os.path.basename(cmd[0]) != "git":
            continue
        d, i = here, 1
        while i < len(cmd) and cmd[i].startswith("-"):
            opt = cmd[i]
            if opt in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
                if opt == "-C" and i + 1 < len(cmd):
                    d = resolve(d, cmd[i + 1]) if d else None
                i += 2
            else:
                i += 1
        if i >= len(cmd) or cmd[i] != "commit":
            continue
        if not d:
            emit("AMBIG", "каталог коммита задан переменной или «cd -»")
            continue
        reason = commit_reshape(cmd[i + 1:])
        if reason:
            emit("PATHS", f"{d}|{reason}")
            continue
        emit("DIR", d)


main()

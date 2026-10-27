"""Находит в команде Bash вызовы git commit и каталог, в котором каждый выполнится.

Вход: команда в stdin, cwd сессии первым аргументом. Выход — строка на коммит:
`DIR <каталог>`, `PATHS <каталог>|<причина>` (состав коммита задаёт не индекс) или
`AMBIG <причина>` (каталог не определить). Регулярки над строкой путали
порядок «cd» и коммита и не видели пути коммита, поэтому команда разбирается
токенизатором shell по простым командам в порядке выполнения.

Разбор намеренно узкий: гейт страхует от забывчивой модели, а не от обхода.
`sh -c`, `eval`, `xargs`, алиасы и функции не разбираются — скилл и так требует
в ворктри простых команд.
"""
import os
import re
import shlex
import sys

SEPARATORS = {";", "&&", "||", "\n", ";;"}
# после «|» и «&» команда шла в подоболочке: её «cd» не переживает разделителя
DETACHED = {"|", "&", "|&"}
WRAPPERS = {"env", "command", "builtin", "time", "nice", "nohup", "exec", "timeout"}
# короткие флаги commit со значением в следующем токене, если не приклеено к флагу
SHORT_WITH_VALUE = set("mFCct")
# значение только приклеенное: -u[<mode>], -S[<keyid>]
SHORT_OPTIONAL_VALUE = set("uS")
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
REDIRECT = re.compile(r"^\d*(>>?|<<?<?|>\|)")
HEREDOC = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_][\w-]*)\2")


def emit(kind, value):
    print(f"{kind} {value}")


def strip_comments(text):
    """Убирает продолжения строк, комментарии и тела heredoc с учётом кавычек.

    shlex не знает ни что «#» открывает комментарий только в начале слова, ни
    что такое heredoc, а апостроф в комментарии или в тексте heredoc валит
    разбор всей команды.
    """
    text = text.replace("\\\n", " ")
    out, quote, i, heredocs = [], None, 0, []
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == "\\" and quote == '"' and i + 1 < len(text):
                out.append(text[i + 1])
                i += 1
            elif ch == quote:
                quote = None
        elif ch == "\\" and i + 1 < len(text):
            out.append(ch + text[i + 1])
            i += 1
        elif ch in "'\"":
            quote = ch
            out.append(ch)
        elif ch == "<" and not text.startswith("<<<", i) and HEREDOC.match(text, i):
            m = HEREDOC.match(text, i)
            heredocs.append((m.group(3), m.group(1) == "-"))
            out.append(m.group(0))
            i = m.end()
            continue
        elif ch == "\n" and heredocs:
            out.append("\n")
            i += 1
            for delim, strip_tabs in heredocs:
                while i < len(text):
                    j = text.find("\n", i)
                    line = text[i:j if j != -1 else len(text)]
                    i = j + 1 if j != -1 else len(text)
                    if (line.lstrip("\t") if strip_tabs else line) == delim:
                        break
            heredocs = []
            continue
        elif ch == "#" and (i == 0 or text[i - 1] in " \t\n;&|()"):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        else:
            out.append(ch)
        i += 1
    # «2>&1», «&>file» — не фоновый запуск: иначе «&» разорвёт команду
    return re.sub(r"\d*[<>]&(\d+|-)|&>>?", " >", "".join(out))


def resolve(base, path):
    if "$" in path or "`" in path:
        return None
    if path == "~" or path.startswith("~/"):
        path = os.path.expanduser(path)
    if not os.path.isabs(path) and not base:
        return None
    return os.path.normpath(os.path.join(base or "/", path))


def unwrap(cmd):
    """Снимает присваивания окружения и обёртки вида env, command, time."""
    while cmd:
        if "=" in cmd[0] and not cmd[0].startswith("-"):
            cmd = cmd[1:]
        elif os.path.basename(cmd[0]) in WRAPPERS:
            wrapper, cmd = os.path.basename(cmd[0]), cmd[1:]
            while cmd and (cmd[0].startswith("-") or (wrapper == "env" and "=" in cmd[0])):
                takes_value = wrapper in ("nice", "timeout") and cmd[0] in ("-n", "-s", "-k")
                cmd = cmd[2:] if takes_value else cmd[1:]
            if wrapper == "timeout" and cmd:
                cmd = cmd[1:]
        else:
            return cmd
    return cmd


def long_option(arg):
    name = arg.split("=", 1)[0]
    # git принимает однозначное сокращение длинного флага: «--on» — это «--only»
    known = LONG_RESHAPE | LONG_WITH_VALUE
    if name in known:
        return name
    matches = [o for o in known if o.startswith(name)]
    return matches[0] if len(matches) == 1 else (name if not matches else "--" + "|".join(matches))


def commit_reshape(args):
    args = list(args)
    i = 0
    while i < len(args):
        a = args[i]
        if REDIRECT.match(a):
            i += 1 if REDIRECT.sub("", a) else 2
            continue
        if a == "--":
            rest = [x for x in args[i + 1:] if not REDIRECT.match(x)]
            return f"пути после «--»: {' '.join(rest)}" if rest else None
        if a.startswith("--"):
            name = long_option(a)
            if any(n in LONG_RESHAPE for n in name.split("|")):
                return a.split("=", 1)[0]
            if name in LONG_WITH_VALUE and "=" not in a:
                i += 1
        elif a.startswith("-") and len(a) > 1:
            for j, ch in enumerate(a[1:], 1):
                if ch in SHORT_OPTIONAL_VALUE:
                    break
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


def commands(tokens):
    """Простые команды с разделителем после каждой."""
    cur = []
    for t in tokens:
        if t in SEPARATORS or t in DETACHED or t in ("(", ")"):
            if cur or t in ("(", ")"):
                yield cur, t
            cur = []
        else:
            cur.append(t)
    if cur:
        yield cur, "\n"


def main():
    cwd = sys.argv[1]
    lex = shlex.shlex(strip_comments(sys.stdin.read()), posix=True, punctuation_chars=";&|()\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        tokens = list(lex)
    except ValueError as e:
        emit("AMBIG", f"команду не разобрать: {e}")
        return

    here, scopes = cwd, []
    for cmd, sep in commands(tokens):
        cmd = unwrap(cmd)
        before = here
        if cmd and cmd[0] == "cd":
            target = cmd[1] if len(cmd) > 1 else "~"
            here = resolve(here, target) if target != "-" else None
        elif cmd and os.path.basename(cmd[0]) == "git":
            d, i = here, 1
            while i < len(cmd) and cmd[i].startswith("-"):
                opt = cmd[i]
                if opt in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
                    if opt == "-C" and i + 1 < len(cmd):
                        d = resolve(d, cmd[i + 1])
                    i += 2
                else:
                    i += 1
            if i < len(cmd) and cmd[i] == "commit":
                if not d:
                    emit("AMBIG", "каталог коммита задан переменной или «cd -»")
                else:
                    reason = commit_reshape(cmd[i + 1:])
                    emit("PATHS", f"{d}|{reason}") if reason else emit("DIR", d)
        if sep in DETACHED:
            here = before
        # «( … )» и «$( … )» — подоболочка: каталог внутри неё не выходит наружу
        if sep == "(":
            scopes.append(here)
        elif sep == ")" and scopes:
            here = scopes.pop()


main()

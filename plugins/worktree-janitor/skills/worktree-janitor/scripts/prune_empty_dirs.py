#!/usr/bin/env python3
"""Убирает каталоги, оставшиеся пустыми после удаления worktrees.

Пустым считается и каталог, в котором лежит только мусор — `.DS_Store`,
настройки IDE, артефакты сборки. Список мусора берётся из scan_worktrees.py,
чтобы правило про игнорируемые файлы жило в одном месте.

По умолчанию только показывает, что удалит. Удаляет с --apply.
"""

import argparse
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan_worktrees import is_noise  # noqa: E402


def is_checkout(path):
    """Рабочее дерево git: у репозитория .git — каталог, у worktree — файл."""
    return os.path.exists(os.path.join(path, ".git"))


def walk(path, root, apply, removed, kept):
    """Обходит снизу вверх и убирает пустые каталоги. Возвращает True, если
    каталог убран — родитель по этому признаку считает себя опустевшим.

    Внутрь рабочих деревьев не заходит совсем: снаружи чекаут с одним
    .DS_Store выглядит пустым, а внутри у него служебные каталоги .git,
    которые обязаны остаться.
    """
    if is_checkout(path):
        kept.append((path, "рабочее дерево git"))
        return False

    empty = True
    for entry in os.scandir(path):
        if entry.is_dir(follow_symlinks=False):
            if not walk(entry.path, root, apply, removed, kept):
                empty = False
        elif not is_noise(entry.name):
            empty = False

    if path == root or not empty:
        return False
    if apply:
        shutil.rmtree(path)
    removed.append(path)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", help="каталог для уборки (сам он не удаляется)")
    ap.add_argument("--apply", action="store_true", help="удалить, а не показать")
    args = ap.parse_args()
    root = os.path.abspath(os.path.expanduser(args.root))
    if not os.path.isdir(root):
        sys.exit(f"нет такого каталога: {root}")

    removed, kept = [], []
    walk(root, root, args.apply, removed, kept)
    print(f"{'удалено' if args.apply else 'будет удалено'}: {len(removed)}")
    for p in sorted(removed):
        print(f"  {p}")
    for p, why in sorted(kept):
        print(f"  пропущено ({why}): {p}")
    if removed and not args.apply:
        print("\nповтори с --apply, чтобы удалить")


if __name__ == "__main__":
    main()

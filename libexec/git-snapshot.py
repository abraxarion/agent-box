#!/usr/bin/env python3
"""Create an atomic ZIP snapshot of a repository's complete Git metadata."""

from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import zipfile


def git(repo: Path, *args: str, check: bool = True) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed")
    return proc.stdout.strip()


def resolve_git_path(repo: Path, raw: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        return path.resolve()
    return (repo / path).resolve()


def zipinfo_for(path: Path, arcname: str) -> zipfile.ZipInfo:
    st = path.lstat()
    info = zipfile.ZipInfo(arcname)
    info.create_system = 3
    info.external_attr = (st.st_mode & 0xFFFF) << 16
    info.date_time = dt.datetime.fromtimestamp(st.st_mtime).timetuple()[:6]
    return info


def add_symlink(zf: zipfile.ZipFile, path: Path, arcname: str) -> None:
    info = zipinfo_for(path, arcname)
    info.external_attr = ((stat.S_IFLNK | (path.lstat().st_mode & 0o777)) & 0xFFFF) << 16
    zf.writestr(info, os.readlink(path).encode())


def add_tree(zf: zipfile.ZipFile, root: Path, prefix: str) -> None:
    root = root.resolve()
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        rel_dir = current_path.relative_to(root)
        rel_prefix = Path(prefix) / rel_dir

        # Preserve empty directories and directory modes.
        dir_arc = rel_prefix.as_posix().rstrip("/") + "/"
        if dir_arc != "./":
            info = zipinfo_for(current_path, dir_arc)
            zf.writestr(info, b"")

        symlink_dirs: list[str] = []
        for name in dirs:
            child = current_path / name
            if child.is_symlink():
                add_symlink(zf, child, (rel_prefix / name).as_posix())
                symlink_dirs.append(name)
        for name in symlink_dirs:
            dirs.remove(name)

        for name in files:
            child = current_path / name
            arcname = (rel_prefix / name).as_posix()
            mode = child.lstat().st_mode
            if stat.S_ISLNK(mode):
                add_symlink(zf, child, arcname)
            elif stat.S_ISREG(mode):
                zf.write(child, arcname)
            else:
                # Git metadata should not normally contain devices/FIFOs/sockets.
                # Skip them rather than following or materializing special files.
                continue


def unique_final_path(repo: Path) -> Path:
    parent = repo.parent
    stamp = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    base = f"{repo.name}.git-save-{stamp}"
    candidate = parent / f"{base}.zip"
    index = 2
    while candidate.exists():
        candidate = parent / f"{base}-{index}.zip"
        index += 1
    return candidate


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: git-snapshot.py REPO", file=sys.stderr)
        return 2

    repo = Path(sys.argv[1]).expanduser().resolve()
    if not repo.is_dir():
        print(f"not a directory: {repo}", file=sys.stderr)
        return 2

    inside = git(repo, "rev-parse", "--is-inside-work-tree", check=False)
    bare = git(repo, "rev-parse", "--is-bare-repository", check=False)
    if inside != "true" and bare != "true":
        print("NO_GIT")
        return 0

    git_dir = Path(git(repo, "rev-parse", "--absolute-git-dir")).resolve()
    raw_common = git(repo, "rev-parse", "--git-common-dir")
    common_dir = resolve_git_path(repo, raw_common)

    dotgit = repo / ".git"
    if bare == "true":
        kind = "bare"
    elif dotgit.is_file():
        kind = "linked-worktree"
    else:
        kind = "standard"

    head = git(repo, "rev-parse", "HEAD", check=False)
    branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD", check=False)
    manifest = {
        "format": 1,
        "created_at": dt.datetime.now().astimezone().isoformat(),
        "repository": str(repo),
        "repository_kind": kind,
        "git_dir": str(git_dir),
        "git_common_dir": str(common_dir),
        "head": head or None,
        "branch": branch or None,
        "scope": "git-metadata-only",
    }

    final_path = unique_final_path(repo)
    temp_path = final_path.parent / f".{final_path.name}.tmp"

    try:
        with zipfile.ZipFile(
            temp_path,
            mode="x",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as zf:
            zf.writestr("manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            add_tree(zf, common_dir, "git-common")

            if dotgit.is_file():
                zf.write(dotgit, "worktree/gitfile")

            try:
                git_dir.relative_to(common_dir)
                git_dir_is_in_common = True
            except ValueError:
                git_dir_is_in_common = False
            if git_dir != common_dir and not git_dir_is_in_common:
                add_tree(zf, git_dir, "git-worktree")

        with temp_path.open("rb") as f:
            os.fsync(f.fileno())
        os.replace(temp_path, final_path)
        try:
            dir_fd = os.open(final_path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            pass
    except Exception:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass
        raise

    print(final_path)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"git-snapshot: {exc}", file=sys.stderr)
        raise SystemExit(1)

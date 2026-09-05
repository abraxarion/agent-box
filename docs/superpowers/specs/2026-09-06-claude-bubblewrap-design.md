# claude-bubblewrap Design

## Goal

Provide a lightweight Linux sandbox for Claude Code that reuses the host toolchain and exact absolute paths while making the host filesystem read-only, the selected repository read/write, and the user's HOME disposable copy-on-write.

## Platform and safety baseline

- Linux only.
- Bash 4.4+.
- Python 3.9+ for atomic Git ZIP snapshots.
- Git 2.x.
- Bubblewrap 0.12.0 or newer. Older versions are rejected because versions before 0.12.0 are affected by the 2026 sandbox-setup symlink traversal advisory GHSA-pxhw-h44j-8pfx.
- Claude Code is the default command. A shell mode is available for inspection.

## Filesystem model

The sandbox is assembled in this order:

1. `--ro-bind / /` exposes the host filesystem read-only at identical absolute paths.
2. `--overlay-src "$HOME" --tmp-overlay "$HOME"` creates an ephemeral writable view of the complete host HOME. Reads fall through to the host HOME; all writes go to Bubblewrap's invisible tmpfs and disappear on exit.
3. `--bind "$REPO" "$REPO"` punches the selected repository through as a real host read/write bind mount, overriding the HOME overlay when the repository lives under HOME.
4. `/run` is a private tmpfs mount. `/tmp` is a private tmpfs by default; `--disk-tmp` replaces it with a fresh mode-0700 host cache directory bind-mounted read/write at `/tmp` and removed on launcher exit. `/proc` and `/dev` are private mounts.
5. Bubblewrap unshares all supported namespaces. Networking is shared by default so Claude can reach its API; `--offline` keeps the isolated network namespace.

This is primarily write isolation, not confidentiality isolation: the read-only host root and the HOME lower layer can expose readable secrets.

## Git behavior

### Identity and configuration

Because HOME is a copy-on-write overlay of the real HOME, `.gitconfig`, `.config/git`, aliases, signing configuration, and other Git files are immediately available. Global config writes affect only the ephemeral HOME layer.

### Repository metadata backup

Before entering Bubblewrap, a host-side preflight snapshots Git metadata unless `--git-save-disabled` is supplied.

- Output: `<parent>/<repo-name>.git-save-YYYYMMDD-HHMMSS.zip`.
- Creation is atomic: write a hidden temporary ZIP in the same parent directory, fsync it, then `os.replace()` it to the final name.
- Backup failure is fatal.
- Normal repositories archive their complete Git common directory.
- Linked worktrees archive the complete common Git directory plus the worktree `.git` pointer file and record the worktree-specific Git directory in a manifest.
- The archive intentionally does not back up unstaged/untracked working-tree content.

### Push policy

Remote writes are denied by default while local Git commands remain usable.

Defense in depth:

1. Put a policy wrapper first in `PATH`.
2. Shadow the canonical Git executable with that wrapper and expose the original executable at a private sandbox path.
3. Shadow `git-send-pack` when it exists.
4. The wrapper rejects invocations containing the `push` or `send-pack` subcommands.

`--allow-git-push` disables those restrictions.

This is a strong guard against ordinary Git pushes, not a complete network egress firewall. With shared networking, arbitrary programs can still communicate with remote services. `--offline` is the hard network-denial mode.

## CLI

```text
claude-bubblewrap [OPTIONS] [REPO] [-- CLAUDE_ARGS...]

Options:
  --git-save-disabled  Do not create the pre-launch Git metadata ZIP.
  --allow-git-push     Do not install Git push guards.
  --offline            Do not share the host network namespace.
  --disk-tmp           Back sandbox /tmp with a private host disk directory.
  --shell              Start an interactive shell instead of Claude Code.
  --dry-run            Print the bwrap command after preflight and do not execute it.
  --no-git-save        Alias for --git-save-disabled.
  -h, --help
  --version
```

If REPO is omitted, the current working directory is used. REPO is canonicalized with `realpath` and must be a directory.

## Error handling

- Missing required executables are reported before sandbox launch.
- Bubblewrap version below 0.12.0 is fatal.
- Git snapshot errors are fatal unless saving is disabled.
- A non-Git directory is allowed; snapshot preflight reports that no Git metadata exists and proceeds.
- The launcher propagates Bubblewrap/Claude's exit code.

## Testing

Tests use only Bash, Python stdlib, and Git. They verify CLI parsing, standard and worktree ZIP snapshots, atomic naming, Git push blocking, version comparison, and generated Bubblewrap arguments. Tests do not require Bubblewrap to be installed; `--dry-run` and isolated helpers cover construction deterministically.

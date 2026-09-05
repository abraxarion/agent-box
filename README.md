# claude-bubblewrap

Run **Claude Code in your real Linux development environment without giving it normal write access to that environment**.

`claude-bubblewrap` uses Bubblewrap to keep the same binaries, libraries, absolute paths, Git configuration, Python virtual environments, Rust/Node/Homebrew installations, and other host tooling that you already use. The host filesystem is exposed read-only, your selected repository is mounted read/write, and your complete HOME is presented through a disposable tmpfs-backed copy-on-write overlay.

```text
HOST                                      SANDBOX

/                          ────────────►   /                     read-only
$HOME                      ────────────►   $HOME                 COW / disposable
$REPO                      ────────────►   $REPO                 read-write
/tmp                                      /tmp                  private tmpfs (default)
host cache session dir       ────────────► /tmp                  RW with --disk-tmp
/run                                      /run                  private tmpfs
/proc                                     /proc                 private
/dev                                      /dev                  private
```

## Why this exists

A traditional container changes paths and often requires rebuilding the development environment. That can be awkward for repositories containing path-sensitive environments such as:

```text
/home/user/github/project/.venv/bin/python
```

With `claude-bubblewrap`, that path remains exactly the same inside and outside the sandbox.

The repository's `.venv`, `node_modules`, Rust `target`, and other repo-local state remain usable because the repository itself is a real read/write bind mount.

## Key behavior

- `/` from the host is visible **read-only**.
- The selected repository is **read/write** at its original absolute path.
- The complete host `$HOME` is the lower layer of a **disposable writable overlay**.
- Your existing `~/.gitconfig`, `~/.config/git`, `~/.claude`, `~/.cargo`, `~/.npm`, etc. are immediately visible.
- Writes outside the selected repository go to ephemeral sandbox storage and disappear when the sandbox exits.
- `/tmp` and `/run` are private. `/tmp` is tmpfs by default; `--disk-tmp` uses a private host-backed session directory instead.
- PID/IPC/UTS/user/cgroup namespaces are isolated via `--unshare-all`.
- Networking is shared by default so Claude Code can reach its API.
- `--offline` removes external networking.
- Git metadata is ZIP-snapshotted on the host before launch by default.
- `git push` is blocked by default.

## Security requirement: Bubblewrap 0.12.0+

`claude-bubblewrap` intentionally refuses Bubblewrap older than **0.12.0**.

On August 26, 2026, Bubblewrap published high-severity advisory `GHSA-pxhw-h44j-8pfx` for versions before 0.12.0. The issue concerns symlink traversal during sandbox setup. The fix is in 0.12.0.

Advisory:

<https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx>

As of **2026-09-06**, Ubuntu 24.04's standard `bubblewrap` package is still 0.9.0, so `apt install bubblewrap` alone does not satisfy this project's security floor. Install Bubblewrap 0.12.0+ from a trusted updated package source or build/install the upstream release before using this launcher.

Check your environment:

```bash
./scripts/check-system.sh
```

## Requirements

- Linux
- Bash 4.4+
- Bubblewrap >= 0.12.0
- Git 2.x
- Python 3.9+
- `realpath`
- Claude Code, unless using `--shell`

No third-party Python packages are used.

## Install

Run directly from the checkout:

```bash
./claude-bubblewrap ~/github/my-project
```

Or install under `~/.local`:

```bash
./scripts/install.sh
```

Then make sure `~/.local/bin` is in `PATH` and use:

```bash
claude-bubblewrap ~/github/my-project
```

A different prefix can be selected with:

```bash
PREFIX=/opt/claude-bubblewrap ./scripts/install.sh
```

## Usage

```text
claude-bubblewrap [OPTIONS] [REPO] [-- CLAUDE_ARGS...]
```

If `REPO` is omitted, the current directory is used.

### Normal launch

```bash
claude-bubblewrap ~/github/my-project
```

### Pass arguments to Claude Code

```bash
claude-bubblewrap ~/github/my-project -- --model sonnet
```

### Inspect the sandbox with a shell

```bash
claude-bubblewrap --shell ~/github/my-project
```

### Print the generated Bubblewrap command

The Git preflight still runs, but Bubblewrap is not executed:

```bash
claude-bubblewrap --dry-run ~/github/my-project
```

### Disable the Git snapshot

```bash
claude-bubblewrap --git-save-disabled ~/github/my-project
```

Shorter alias:

```bash
claude-bubblewrap --no-git-save ~/github/my-project
```

### Allow Git pushes

Pushes are blocked by default. Explicitly opt in with:

```bash
claude-bubblewrap --allow-git-push ~/github/my-project
```

### No network

```bash
claude-bubblewrap --offline --shell ~/github/my-project
```

`--offline` is useful for inspection/testing. Claude Code normally requires network access unless your setup routes it to something available inside that isolated namespace.

### Disk-backed `/tmp`

By default, sandbox `/tmp` is a private tmpfs. For builds or tools that can use substantial temporary space, use:

```bash
claude-bubblewrap --disk-tmp ~/github/my-project
```

The launcher creates a private mode-0700 session directory below:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/claude-bubblewrap/tmp/
```

and bind-mounts only that session directory read/write at `/tmp` inside the sandbox. The host's real `/tmp` is never shared. The session directory is removed when the launcher exits, including when Bubblewrap/Claude exits with an error. Like any process cleanup, it cannot run after `SIGKILL`, a kernel crash, or sudden power loss; in those cases a stale session directory can remain in the cache tree.

## Private temporary storage

Default mode constructs `/tmp` with:

```bash
--tmpfs /tmp
```

`--disk-tmp` replaces that one mount with a private host-backed bind:

```bash
--bind "$SESSION_TMP" /tmp
```

This is useful for large compiles, archives, link steps, or other workloads where consuming RAM/swap through tmpfs is undesirable. In both modes, sandbox processes can write normally to `/tmp`, while unrelated files from the host's `/tmp` stay invisible.

## Disposable HOME

The core filesystem layering is:

```bash
--ro-bind / /
--overlay-src "$HOME"
--tmp-overlay "$HOME"
--bind "$REPO" "$REPO"
```

Bubblewrap's tmp overlay uses the real HOME as its read-only lower layer. Changes are written to an invisible tmpfs upper layer and are not persisted.

So inside the sandbox:

```bash
git config --global user.name
```

sees your normal Git name, and:

```bash
git config --global user.name "Temporary Name"
```

changes only the disposable sandbox HOME. The host `~/.gitconfig` is unchanged.

The same principle applies to tools that want to update files under `~/.cache`, `~/.npm`, `~/.cargo`, `~/.claude`, and similar locations.

This avoids a physical startup copy of the whole HOME, which could otherwise consume many gigabytes of RAM and startup time.

## Git metadata snapshots

Before Bubblewrap starts, `claude-bubblewrap` runs a host-side snapshot preflight.

For:

```text
/home/user/github/project/
```

the result is stored one level above the repository:

```text
/home/user/github/project.git-save-20260906-001530.zip
```

The ZIP is written to a hidden temporary file first and atomically renamed only after successful completion. Snapshot failure aborts the sandbox launch.

The archive contains:

```text
manifest.json
git-common/
    HEAD
    config
    index
    objects/
    refs/
    logs/
    ...
```

For a linked worktree it additionally contains:

```text
worktree/gitfile
```

and `manifest.json` records both the worktree-specific Git directory and the shared common Git directory.

### Important limitation

This is a **Git metadata backup**, not a complete working-directory backup.

It protects Git objects, refs, logs, index data, configuration, worktree metadata, etc. It does **not** preserve arbitrary untracked files or unstaged working-tree modifications that have never been stored in Git.

If you need protection for those too, use a full repository/worktree snapshot in addition to the `.git` ZIP.

## Git push blocking

By default `claude-bubblewrap` installs several guards:

1. A `git` policy wrapper is placed first in `PATH`.
2. The canonical Git executable path is shadowed by that wrapper.
3. The real Git binary is exposed only at a private sandbox path used by the wrapper.
4. `git-send-pack` is shadowed with a blocker when present.

Normal local Git operations remain available:

```bash
git status
git diff
git add .
git commit -m "change"
git branch
git rebase
git log
```

But:

```bash
git push
```

fails with a `claude-bubblewrap` policy message.

### This is not a general network firewall

When networking is shared, an adversarial process can potentially bypass Git-specific policy by implementing remote protocol operations itself or using another network-capable tool.

Therefore:

- default Git push blocking is a practical guard against Claude/normal tooling pushing accidentally;
- `--offline` is the strong option when **all** network egress must be impossible;
- selective network egress would require a separate network namespace + controlled proxy/firewall architecture.

See [SECURITY.md](SECURITY.md).

## What happens to the Git backup inside the sandbox?

The ZIP is created on the host before sandbox entry. If its parent directory is below `$HOME`, the HOME overlay means Claude can create an ephemeral replacement/whiteout at the same path, but it cannot modify the host copy through that overlay. The actual host ZIP survives when the sandbox exits.

## Development

Run all tests:

```bash
./tests/run.sh
```

Syntax checks:

```bash
bash -n claude-bubblewrap lib/*.sh libexec/git-policy libexec/git-send-pack-block scripts/*.sh tests/*.sh
python3 -m py_compile libexec/git-snapshot.py
```

The test suite does not need Bubblewrap installed; it verifies deterministic argument construction and uses real temporary Git repositories/worktrees for snapshot tests.

## Project layout

```text
claude-bubblewrap
├── claude-bubblewrap              # main launcher
├── lib/
│   ├── common.sh                  # diagnostics, dependencies, version checks
│   ├── cli.sh                     # CLI parsing
│   └── bwrap.sh                   # sandbox argument construction
├── libexec/
│   ├── git-snapshot.py            # atomic Git metadata ZIP
│   ├── git-policy                 # Git command policy wrapper
│   └── git-send-pack-block        # direct send-pack blocker
├── scripts/
│   ├── check-system.sh
│   └── install.sh
├── tests/
└── docs/superpowers/
```

## License

MIT. See [LICENSE](LICENSE).

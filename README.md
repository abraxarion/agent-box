# agent-box

`agent-box` runs **a coding agent (like Claude Code, Codex, Pi, etc.) inside a Bubblewrap sandbox while reusing your real Linux development environment and exact absolute paths**.

The host filesystem is visible read-only, one selected repository is bind-mounted read/write at its original path, and your complete `$HOME` is presented as a disposable copy-on-write view. This lets the coding agent use your existing Git identity, Python environments, Node/Rust/Homebrew installations, coding agent configuration, and other host tooling without giving normal write access to the rest of the host.

```text
HOST                                           SANDBOX

/                              ─────────────►  /                  read-only
$HOME                          ─────────────►  $HOME              disposable COW
$REPO                          ─────────────►  $REPO              read/write
host Git metadata snapshot     stays outside  sandbox lifecycle  host-side ZIP
/tmp                                           /tmp               private tmpfs (default)
private cache session dir      ─────────────►  /tmp               RW with --disk-tmp
/run                                           /run               private tmpfs
/proc                                          /proc              private procfs
/dev                                           /dev               private device view
```

## What this is for

A normal container often changes paths and requires rebuilding the development environment. That can be inconvenient when a repository already contains path-sensitive state such as:

```text
/home/user/github/project/.venv/bin/python
```

With `agent-box`, that path is still exactly:

```text
/home/user/github/project/.venv/bin/python
```

inside the sandbox. The repository's `.venv`, `node_modules`, Rust `target`, build directories, and other repo-local files remain directly usable because the repository itself is a real read/write bind mount.

## Default behavior

A normal invocation:

```bash
agent-box ~/github/my-project
```

performs this sequence:

1. Resolve the repository to its canonical absolute path.
2. Verify the host-side prerequisites needed for preflight.
3. Create an atomic ZIP snapshot of Git metadata in the repository's parent directory, if the target is a Git repository.
4. Verify Bubblewrap is at least version `0.12.0`.
5. Build the sandbox mount and namespace policy.
6. Launch your coding agent with the repository as the working directory.
7. Remove temporary host-side runtime-policy files and any `--disk-tmp` session directory when the launcher exits.

The resulting policy is:

- host `/`: **read-only**;
- selected repository: **read/write**;
- `$HOME`: **disposable writable copy-on-write overlay**;
- `/tmp`: **private writable tmpfs** by default;
- `/run`: **private writable tmpfs**;
- `/proc`: private procfs;
- `/dev`: private Bubblewrap device view;
- PID/IPC/UTS/user/cgroup namespaces: isolated through `--unshare-all`;
- network: shared by default so any coding agent can reach its API;
- Git metadata backup: enabled by default;
- `git push`: blocked by default.

> [!IMPORTANT]
> This is primarily a **host write-isolation sandbox**, not a confidentiality boundary. The host root is readable and the real HOME is the read-only lower layer of the HOME overlay, so sandboxed processes can read files and secrets that your Unix account can read. See [SECURITY.md](SECURITY.md).

## Security requirement: Bubblewrap 0.12.0+

`agent-box` refuses Bubblewrap versions older than **0.12.0**.

Bubblewrap versions before 0.12.0 are affected by `GHSA-pxhw-h44j-8pfx`, a high-severity sandbox-setup symlink traversal issue fixed in 0.12.0:

<https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx>

Check your environment before first use:

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
- Claude Code, optional and only needed using `--claude` to run Claude Code

No third-party Python packages are required.

## Installation

### Run from the checkout

```bash
./agent-box ~/github/my-project
```

### Install for the current user

```bash
./scripts/install.sh
```

The default installation layout is:

```text
~/.local/bin/agent-box                  symlink
~/.local/lib/agent-box/                 implementation
```

Make sure `~/.local/bin` is in `PATH`, then run:

```bash
agent-box ~/github/my-project
```

### Install to another prefix

```bash
PREFIX=/opt/agent-box ./scripts/install.sh
```

The launcher is installed under `$PREFIX/bin` and its libraries under `$PREFIX/lib/agent-box`.

## Command syntax

```text
agent-box [OPTIONS] [REPO]

agent-box --claude [OPTIONS] [REPO] [-- CLAUDE_ARGS...]
```

`REPO` is optional. If omitted, the current working directory is used.

When starting Claude Code with the `--claude` parameter then use the `--` separator before arguments that should be passed to Claude Code rather than interpreted by `agent-box`.

```bash
agent-box ~/github/my-project -- --model sonnet
```

When not starting with `--claude` then arguments after `--` are passed to the selected shell instead of Claude Code.

## Command-line parameters

| Parameter | Default | Effect |
|---|---|---|
| `REPO` | current directory | Repository/directory exposed read/write at the same absolute path. It is canonicalized with `realpath` and must exist as a directory. |
| `--git-save-disabled` | Git save enabled | Skip the pre-launch Git metadata ZIP. |
| `--no-git-save` | Git save enabled | Alias for `--git-save-disabled`. |
| `--allow-git-push` | push blocked | Do not install the Git push guards. Normal Git remote writes are then allowed according to your credentials/network access. |
| `--offline` | network shared | Keep Bubblewrap's isolated network namespace instead of adding `--share-net`. External network access is therefore unavailable through the normal host network. |
| `--disk-tmp` | private tmpfs `/tmp` | Use a private host-backed session directory for sandbox `/tmp`, useful for large builds that should not consume tmpfs RAM/swap. |
| `--claude` | launch Claude Code |  Start the agent-box interactivly with Claude Code |
| `--dry-run` | execute sandbox | Perform preflight, construct and print the Bubblewrap command, then stop before executing Bubblewrap. The Git snapshot still occurs unless disabled. |
| `-h`, `--help` | — | Print CLI help and exit. |
| `--version` | — | Print the installed `agent-box` version and exit. |
| `-- CLAUDE_ARGS...` | none | Pass all remaining arguments verbatim to Claude Code, or to the shell when `--claude` is not provided. |

## Environment variables

Set `$SHELL` (defaults to `/bin/bash` when `$SHELL` is unset) to launch inside the sandbox during start.


### Parameter interaction notes

- `--dry-run` does **not** execute Bubblewrap and therefore does not require Bubblewrap or Claude Code to be available for the final launch step. Host preflight requirements such as Git, Python and `realpath` still apply.
- `--offline` is stronger than the Git-specific push guard because it removes normal external network access entirely.
- `--allow-git-push` only disables the Git wrapper/shadowing policy. It does not change the filesystem sandbox.
- `--git-save-disabled` does not change Git access inside the sandbox; it only disables the host-side pre-launch snapshot.
- `--disk-tmp` adds one temporary host write location in the user cache in addition to the selected repository. That directory is private to the session and removed on normal launcher exit.

## Usage examples

### Start the sandbox interactively

Start in the current directory
```bash
agent-box
```

Start in a mounted repository

```bash
agent-box ~/github/my-project
```

### Start Claude Code in a repository

```bash
agent-box --claude ~/github/my-project
```

### Use the current directory

```bash
cd ~/github/my-project
agent-box --claude
```

### Forward Claude Code arguments

```bash
agent-box --claude ~/github/my-project -- --model sonnet
```

Everything after `--` is forwarded unchanged.

### Inspect the sandbox interactively

```bash
agent-box ~/github/my-project
```

Useful checks inside the shell include:

```bash
pwd
mount | head
git config --global user.name
git config --global user.email
touch /tmp/agent-box-test
```

### Inspect the generated Bubblewrap command

```bash
agent-box --dry-run ~/github/my-project
```

To avoid creating a Git snapshot during inspection:

```bash
agent-box --dry-run --no-git-save ~/github/my-project
```

### Disable the automatic Git metadata snapshot

```bash
agent-box --git-save-disabled ~/github/my-project
```

or:

```bash
agent-box --no-git-save ~/github/my-project
```

### Allow `git push`

```bash
agent-box --allow-git-push ~/github/my-project
```

Use this only when you intentionally want the sandboxed agent/process to be able to write to remote Git repositories.

### Disable external networking

```bash
agent-box --offline ~/github/my-project
```

A coding agent normally needs network access unless your setup reaches a model endpoint available from within the isolated namespace.

### Use disk-backed temporary storage

```bash
agent-box --disk-tmp ~/github/my-project
```

This is useful for large C/C++ links, Rust builds, archives, model/tool downloads, or other workloads that may put substantial data in `/tmp`.

## Mounting strategy

Mount order is intentional and is part of the sandbox contract:

```text
1. --ro-bind / /
2. --overlay-src "$HOME" --tmp-overlay "$HOME"
3. --bind "$REPO" "$REPO"
4. private /proc, /dev, /tmp, /run
5. Git-policy mounts when push blocking is enabled
```

The later repository bind **punches through** the HOME overlay. This matters when the repository lives below HOME:

```text
/home/user/                         disposable HOME COW
└── github/
    └── my-project/                real host RW bind
```

That is why repo-local environments keep both their exact paths and normal persistence while unrelated HOME writes remain ephemeral.

### Host root

The base mount is:

```bash
--ro-bind / /
```

Host binaries, libraries, system configuration and tools remain available at their normal paths, but ordinary filesystem writes through that view are denied.

### Disposable HOME

HOME is layered with:

```bash
--overlay-src "$HOME"
--tmp-overlay "$HOME"
```

The real HOME is the lower layer. Reads fall through to it; writes land in a temporary upper layer and disappear when the sandbox exits.

This means existing configuration is immediately available:

```text
~/.gitconfig
~/.config/git/
~/.claude/
~/.cargo/
~/.rustup/
~/.npm/
~/.local/
...
```

For example:

```bash
git config --global user.name
```

sees your normal identity, while:

```bash
git config --global user.name "Temporary Sandbox Name"
```

changes only the disposable sandbox HOME. Your host `~/.gitconfig` remains unchanged.

### Writable repository

The selected repository is mounted after HOME:

```bash
--bind "$REPO" "$REPO"
```

Therefore repository changes are real host changes and persist after the sandbox exits.

### Private `/tmp`

Default mode uses:

```bash
--tmpfs /tmp
```

The agent can write normally to `/tmp`, but the host's real `/tmp` is hidden and sandbox temporary data disappears with the sandbox.

With `--disk-tmp`, the launcher instead creates a mode-`0700` directory below:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/agent-box/tmp/
```

and mounts that session directory:

```bash
--bind "$SESSION_TMP" /tmp
```

The host's actual `/tmp` is still never shared. The session directory is removed on normal launcher exit, including non-zero Bubblewrap exits. Cleanup cannot run after `SIGKILL`, a kernel crash, or sudden power loss, so a stale cache directory can remain in those cases.

### Private `/run`

`/run` is replaced with a private tmpfs:

```bash
--tmpfs /run
```

This avoids exposing host runtime sockets such as D-Bus, Docker/Podman sockets, SSH-agent sockets and similar host-control channels that commonly live below `/run`.

## Git behavior

### Existing Git identity works automatically

Because the HOME overlay uses your real HOME as its lower layer, the sandbox sees your existing global Git configuration without asking for your name/email again.

Useful verification:

```bash
git config --list --show-origin
git config --global user.name
git config --global user.email
```

Repository-local `.git/config` remains part of the read/write repository mount for a standard repository.

> [!NOTE]
> A linked Git worktree is different: its `.git` is a pointer file and its worktree/common Git metadata normally lives outside the selected worktree directory. The current sandbox does not add separate RW binds for those external metadata directories, so Git operations that need to update linked-worktree metadata may fail read-only. The pre-launch snapshot helper understands linked worktrees, but writable linked-worktree Git metadata is not yet a sandbox feature.

### Automatic Git metadata ZIP

Before Bubblewrap starts, the host launcher snapshots Git metadata unless saving is disabled.

For:

```text
/home/user/github/project/
```

the archive is written to the parent directory with a timestamped name such as:

```text
/home/user/github/project.git-save-20260906-001530.zip
```

Creation is atomic: the snapshot helper writes a hidden temporary ZIP in the same directory, fsyncs it, and renames it to the final name only after successful completion. Snapshot failure aborts sandbox startup.

A standard repository archive contains:

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

Linked Git worktrees are detected. Their archive additionally preserves the worktree `.git` pointer file and records both the common and worktree-specific Git paths in `manifest.json`.

The snapshot is **Git metadata only**. It does not preserve arbitrary untracked files or unstaged working-tree content that has never been stored in Git.

### Git push is blocked by default

When push protection is active, `agent-box`:

1. creates temporary host-side copies of the Git policy executables;
2. mounts a policy wrapper first in sandbox `PATH`;
3. shadows the canonical Git executable with that wrapper;
4. exposes the real Git executable only at a private sandbox path used by the wrapper;
5. shadows a distinct `git-send-pack` helper when the platform provides one.

For a standard repository whose Git metadata is inside the selected RW repository, normal local operations remain available:

```bash
git status
git diff
git add .
git commit -m "change"
git branch
git checkout
git merge
git rebase
git log
```

But an ordinary:

```bash
git push
```

is rejected.

This is a guard against normal/accidental Git remote writes, **not a general firewall**. With shared networking, a deliberately hostile program could use other network tooling or implement a remote protocol itself. Use `--offline` when all normal network egress must be denied.

## What persists after exit?

| Location/state | Persists? | Why |
|---|---:|---|
| Files changed inside `$REPO` | Yes | Real host read/write bind mount. |
| Standard-repo `.git` metadata changes | Yes | `.git` is inside the RW repository bind. |
| Linked-worktree external Git metadata changes | Not necessarily | External worktree/common Git directories remain under the host RO view unless separately supported in a future mount policy. |
| `$HOME` config/cache changes outside repo | No | Written to the disposable HOME overlay. |
| Default `/tmp` contents | No | Private tmpfs. |
| `--disk-tmp` contents | Normally no | Host session directory is deleted by launcher cleanup. |
| `/run` contents | No | Private tmpfs. |
| Pre-launch Git ZIP | Yes | Created by the host before sandbox execution. |

## System check

Run:

```bash
./scripts/check-system.sh
```

It checks:

- Bash;
- Python 3;
- Git;
- `realpath`;
- Bubblewrap version >= 0.12.0;
- Claude Code availability (warning only because `--claude` can not run without it).

## Troubleshooting

### `Bubblewrap ... is too old`

Install Bubblewrap `0.12.0` or newer from a trusted source. The launcher intentionally refuses older releases.

### `required command not found: claude`

Install Claude Code before using `--claude`.
Or run interactive shell instead.

```bash
agent-box ~/github/my-project
```

### Git snapshot failure prevents startup

That is intentional. The backup is a default safety preflight. Fix the filesystem/Git error or explicitly opt out:

```bash
agent-box --no-git-save ~/github/my-project
```

### A build runs out of space in `/tmp`

Use disk-backed temporary storage:

```bash
agent-box --disk-tmp ~/github/my-project
```

### `git push` says it is disabled

That is the default policy. If the push is intentional, restart with:

```bash
agent-box --allow-git-push ~/github/my-project
```

### A stale `--disk-tmp` directory remains

This can happen after `SIGKILL`, machine failure, or another event that prevents the exit trap from running. Stale session directories live below:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/agent-box/tmp/
```

Inspect them before removing them manually.

## Development

The project intentionally uses a small dependency-free architecture: Bash for orchestration and Python stdlib only for robust ZIP creation.

Run the complete test suite:

```bash
./tests/run.sh
```

Run syntax checks:

```bash
bash -n agent-box lib/*.sh libexec/git-policy libexec/git-send-pack-block scripts/*.sh tests/*.sh
python3 -m py_compile libexec/git-snapshot.py
git diff --check
```

The tests do not require a real Bubblewrap sandbox for most coverage. They verify deterministic argument construction, Git policy behavior, launcher orchestration and real temporary Git repositories/worktrees.

For architecture and maintainer rules, see [AGENTS.md](AGENTS.md).

## Project layout

```text
agent-box/
├── agent-box                      # main launcher / lifecycle orchestration
├── lib/
│   ├── common.sh                  # diagnostics, dependency/version helpers
│   ├── cli.sh                     # CLI parsing and public help
│   └── bwrap.sh                   # mount policy, temp lifecycle, bwrap args
├── libexec/
│   ├── git-snapshot.py            # atomic Git metadata ZIP preflight
│   ├── git-policy                 # Git wrapper that rejects push/send-pack
│   └── git-send-pack-block        # direct send-pack blocker
├── scripts/
│   ├── check-system.sh            # environment readiness check
│   └── install.sh                 # prefix-based installer
├── tests/                         # Bash integration/unit-style tests
├── docs/superpowers/              # original design and implementation plan
├── AGENTS.md                      # architecture and contributor/agent contract
├── SECURITY.md                    # threat model and security limitations
├── LICENSE
└── README.md
```

## Security

Read [SECURITY.md](SECURITY.md) before treating the sandbox as a security boundary. In particular:

- the sandbox can read host-readable files;
- the selected repository is intentionally writable;
- default networking is shared;
- Git push blocking is Git-specific policy, not a general egress firewall;
- `--offline` is the available hard network-denial mode;
- `--disk-tmp` creates a narrowly scoped temporary host write exception.

## License

MIT. See [LICENSE](LICENSE).

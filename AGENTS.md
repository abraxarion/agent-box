# AGENTS.md

This file is the maintainer and coding-agent contract for **agent-box**. Read it before changing launcher behavior, mount order, Git policy, cleanup, or release metadata.

## Mission

`agent-box` provides a lightweight Linux sandbox for coding agents like Claude Code or Codex that:

- reuses the host's existing toolchain and exact absolute paths;
- exposes the host filesystem read-only;
- exposes exactly one selected repository read/write;
- presents the user's existing HOME as a disposable writable copy-on-write view;
- creates a host-side Git metadata recovery snapshot before launch by default;
- blocks ordinary Git pushes by default;
- keeps runtime sockets and temporary storage private;
- stays small, auditable, and dependency-light.

The project is primarily a **write-isolation layer**, not a confidentiality sandbox.

## Architectural invariants

Do not change these casually. Any change requires tests and corresponding README/SECURITY documentation.

1. **Exact paths are preserved.** The repository must appear at the same absolute path inside and outside the sandbox.
2. **Host root is read-only.** `--ro-bind / /` is the base filesystem policy.
3. **HOME writes are disposable.** The real HOME is a read-only lower layer; normal sandbox writes to HOME must not persist to the host.
4. **The selected repository is the intentional persistent RW exception.** It is bind-mounted after the HOME overlay so it punches through that overlay.
5. **Mount order is semantic.** Reordering root, HOME, repo, `/tmp`, `/run`, or Git-policy mounts can change security behavior.
6. **Host `/tmp` is never shared directly.** Sandbox `/tmp` is private tmpfs by default or a fresh private session directory with `--disk-tmp`.
7. **Host `/run` is hidden.** Do not expose the host `/run` tree by default; it contains powerful sockets and runtime channels.
8. **Git metadata backup is host-side and pre-launch by default.** Snapshot failure is fatal unless the user explicitly disables saving.
9. **Git push is blocked by default.** `--allow-git-push` is the explicit opt-in.
10. **Network is shared by default only because a coding agent needs it.** `--offline` must keep the isolated network namespace.
11. **Bubblewrap < 0.12.0 is rejected.** Do not lower this floor without a deliberate security review.
12. **No third-party Python dependency.** The snapshot helper must remain Python-stdlib-only unless the project explicitly changes this policy.
13. **The launcher propagates the sandboxed child's exit code.** Cleanup must not destroy or replace the real exit status.

## Runtime workflow

The main executable is `agent-box`. Its lifecycle is intentionally linear and easy to audit.

```text
CLI invocation
    │
    ▼
parse arguments                         lib/cli.sh
    │
    ▼
validate platform/basic host tools      agent-box + lib/common.sh
    │
    ▼
resolve canonical git executable
    │
    ▼
Git metadata snapshot (default)         libexec/git-snapshot.py
    │
    ├── non-Git directory → continue
    ├── success → continue
    └── failure → abort before sandbox
    │
    ▼
validate bwrap >= minimum               lib/common.sh
validate shell or claude
    │
    ▼
install EXIT cleanup trap               lib/bwrap.sh
    │
    ▼
prepare optional disk-backed /tmp       lib/bwrap.sh
prepare Git policy runtime copies       lib/bwrap.sh
    │
    ▼
construct Bubblewrap argv               lib/bwrap.sh
    │
    ├── --dry-run → print command, exit
    │
    ▼
execute bwrap
    │
    ▼
propagate child exit code
    │
    ▼
EXIT trap removes host temp state
```

### Why preflight happens outside Bubblewrap

The Git recovery archive is a host safety mechanism. It must be created before the writable repository is handed to a coding agent (like Claude Code). Do not move snapshot creation into the sandbox.

The temporary Git-policy files are also prepared on the host before launch and mounted read-only. This avoids relying on policy code stored inside the writable target repository.

## Mounting strategy

`cb_build_bwrap_args` in `lib/bwrap.sh` owns the filesystem policy. The important order is:

```text
1. host root RO
2. HOME disposable overlay
3. selected repo RW
4. private proc/dev/tmp/run
5. Git-policy overrides
6. namespaces/session/chdir/command
```

### Layer 1: host root read-only

```bash
--ro-bind / /
```

Purpose:

- reuse host binaries, libraries and toolchains;
- preserve absolute paths;
- deny ordinary persistent writes to the host filesystem.

This deliberately allows reads. Do not describe it as secret isolation.

### Layer 2: disposable HOME

```bash
--overlay-src "$HOME"
--tmp-overlay "$HOME"
```

The host HOME is the lower layer. Bubblewrap supplies temporary writable upper storage.

Consequences:

- existing `.gitconfig`, `.config/git`, `.claude`, `.cargo`, `.rustup`, `.npm`, `.local`, etc. are visible immediately;
- global config changes inside the sandbox are ephemeral;
- Git user name/email do not need to be re-entered;
- no eager copy of the entire HOME is required.

### Layer 3: repository read/write punch-through

```bash
--bind "$CB_REPO" "$CB_REPO"
```

This must follow the HOME overlay. For a repo inside HOME:

```text
$HOME/                              disposable overlay
└── github/
    └── project/                    real RW bind
```

Repository writes persist. Repo-local `.venv`, `node_modules`, `target`, and other path-sensitive content retain exact paths.

**Known linked-worktree limitation:** a linked worktree's `.git` is a pointer file and its actual worktree/common Git metadata usually lives outside `CB_REPO`. Those external paths remain under the host read-only root in the current architecture. The snapshot helper supports linked worktrees, but the sandbox does not currently punch their external Git metadata through RW. Do not claim full linked-worktree Git mutation support until explicit, narrowly scoped RW mounts and tests are added.

### Layer 4: private runtime filesystems

```bash
--proc /proc
--dev /dev
--tmpfs /run
```

Default `/tmp`:

```bash
--tmpfs /tmp
```

Disk-backed `/tmp`:

```bash
--bind "$CB_DISK_TMP_DIR" /tmp
```

`CB_DISK_TMP_DIR` is created below:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/agent-box/tmp/
```

with mode `0700`. Only the fresh per-session directory is exposed RW. The host's real `/tmp` must remain hidden.

`/run` stays private to hide host sockets such as D-Bus, Docker/Podman control sockets, SSH agents, and similar channels.

### Layer 5: Git policy mounts

When `CB_ALLOW_GIT_PUSH=0`, the launcher prepares immutable runtime copies of the Git wrappers and adds mounts that:

- place the policy `git` first in `PATH`;
- shadow the canonical `git` executable path;
- expose the real Git binary only as `/run/agent-box/real-git`;
- shadow `git-send-pack` only when it is a distinct executable.

Do not blindly mount a blocker over `git-send-pack`: on some Git installations it is a symlink or hardlink to the shared Git executable. Shadowing that target would break unrelated Git subcommands. The inode/symlink guard in `lib/bwrap.sh` exists for this reason.

### Namespace policy

The base namespace policy is:

```bash
--unshare-all
```

Normal mode adds:

```bash
--share-net
```

Offline mode omits `--share-net`.

The command also uses:

```bash
--die-with-parent
--new-session
--chdir "$CB_REPO"
```

Keep the distinction clear:

- normal mode: isolated namespaces except network is re-shared;
- `--offline`: network remains isolated.

## Git snapshot architecture

`libexec/git-snapshot.py` is responsible only for creating a recoverable Git metadata archive.

### Output location

For:

```text
/path/to/project/
```

write beside the repository:

```text
/path/to/project.git-save-YYYYMMDD-HHMMSS.zip
```

Name collisions in the same second get numeric suffixes.

### Repository kinds

The helper detects:

- standard repositories;
- linked worktrees (`.git` is a pointer file);
- bare repositories;
- non-Git directories.

Use Git plumbing (`rev-parse --absolute-git-dir`, `--git-common-dir`) rather than assuming `.git` is always a directory.

### Archive contents

The ZIP contains `manifest.json` plus the complete Git common directory under `git-common/`.

For linked worktrees it also preserves `worktree/gitfile`. If worktree-specific Git metadata is outside the common directory, it is archived under `git-worktree/`.

The helper preserves regular files, directories, Unix modes and symlinks where applicable. It skips unusual special filesystem objects rather than materializing them.

### Atomicity

The final archive must never look valid until complete:

1. choose the final timestamped path;
2. write a hidden `.tmp` archive in the same parent directory;
3. fsync the archive;
4. atomically `os.replace()` it to the final name;
5. best-effort fsync the parent directory.

On failure, remove the temporary archive and return non-zero. The launcher then aborts.

### Scope limitation

The archive is **Git metadata only**. It does not protect arbitrary untracked files or unstaged working-tree bytes. Do not imply otherwise in documentation or messages.

## Git push policy

`libexec/git-policy` rejects arguments containing the `push` or `send-pack` subcommands and otherwise execs the real Git binary supplied through:

```text
AGENT_BOX_REAL_GIT=/run/agent-box/real-git
```

`libexec/git-send-pack-block` is a secondary direct-helper blocker.

This is defense in depth against normal Git push paths, not a complete remote-write or network security boundary. An adversarial process with shared networking could use another client/protocol. Never document the default as equivalent to a firewall.

## `/tmp` lifecycle

### Default

Sandbox `/tmp` is tmpfs and disappears with Bubblewrap.

### `--disk-tmp`

`cb_prepare_disk_tmp`:

1. chooses `${XDG_CACHE_HOME:-$HOME/.cache}/agent-box/tmp`;
2. creates/ensures the base directory;
3. creates a fresh `agent-box-tmp.XXXXXX` session directory;
4. enforces mode `0700`;
5. stores its path in `CB_DISK_TMP_DIR`.

`cb_cleanup_disk_tmp` removes only that per-session directory.

The `EXIT` trap is the cleanup authority. Preserve cleanup on both success and non-zero child exit. `SIGKILL`, kernel failure or power loss cannot execute cleanup, so stale cache directories are an accepted documented limitation.

## Source layout and responsibilities

### `agent-box`

Owns top-level sequencing only:

- source libraries;
- parse args;
- perform preflight;
- prepare lifecycle cleanup;
- ask libraries to build policy;
- execute Bubblewrap;
- preserve child exit code.

Avoid accumulating mount-policy details here.

### `lib/common.sh`

Owns generic helpers:

- version constants;
- diagnostics (`cb_die`, `cb_warn`, `cb_info`);
- executable requirements;
- version comparison;
- Bubblewrap version parsing/checking;
- shell-safe command printing.

### `lib/cli.sh`

Owns the public CLI contract:

- help text;
- option parsing;
- default values;
- repository canonicalization;
- forwarding arguments after `--`.

Any new public flag must be added here, documented in README, and covered by `tests/test_cli.sh` plus behavior tests.

### `lib/bwrap.sh`

Owns sandbox construction and temporary host runtime state:

- Git policy preparation/cleanup;
- disk-backed `/tmp` preparation/cleanup;
- final `CB_BWRAP_ARGS` ordering.

Treat this file as security-sensitive.

### `libexec/git-snapshot.py`

Owns Git metadata backup only. Keep it independent from Bubblewrap argument construction and Claude-specific behavior.

### `libexec/git-policy`

Owns normal Git command filtering. It must pass normal local Git commands through to the real binary without altering their output/exit status.

### `libexec/git-send-pack-block`

Small hard blocker used only when it is safe to shadow a distinct send-pack helper.

### `scripts/check-system.sh`

Operator readiness check. Keep its minimum Bubblewrap version sourced from `lib/common.sh`, not duplicated independently.

### `scripts/install.sh`

Installs the launcher and runtime libraries under a configurable prefix. Preserve the relative runtime layout expected by the main launcher.

### `tests/`

Tests are executable Bash scripts using `tests/testlib.sh`. They intentionally use temporary real Git repositories/worktrees where useful and fake Bubblewrap executables for deterministic launcher tests.

## Development workflow

For behavior changes, use a test-first cycle.

1. Read the relevant source and existing test.
2. Add the smallest failing regression/feature test.
3. Run that test and verify the failure is for the intended missing behavior.
4. Implement the minimal change.
5. Run the focused test until green.
6. Run the full suite.
7. Run syntax/static checks.
8. Update README/SECURITY/AGENTS if the public contract, threat model, workflow, mounts, cleanup, or architecture changed.
9. Inspect `git diff --check` and `git status` before release/commit.

Do not weaken tests merely to make a change pass.

## Test map

| Test | Primary contract |
|---|---|
| `tests/test_cli.sh` | CLI help, parsing, defaults, Bubblewrap version comparison. |
| `tests/test_git_snapshot.sh` | standard repo/worktree snapshots, output location, atomic temp cleanup, non-Git handling. |
| `tests/test_git_policy.sh` | normal Git passthrough and push/send-pack rejection. |
| `tests/test_bwrap_args.sh` | mount ordering/content, namespace policy, Git shadowing, `/tmp` modes. |
| `tests/test_launcher.sh` | orchestration, snapshot defaults, bwrap version gate, child exit propagation, disk-tmp cleanup. |
| `tests/run.sh` | complete suite entrypoint. |

## Required verification before claiming completion

Run from the repository root:

```bash
./tests/run.sh
```

Then:

```bash
bash -n agent-box lib/*.sh libexec/git-policy libexec/git-send-pack-block scripts/*.sh tests/*.sh
python3 -m py_compile libexec/git-snapshot.py
git diff --check
```

For installer changes, also test an isolated prefix:

```bash
tmp="$(mktemp -d)"
PREFIX="$tmp/prefix" ./scripts/install.sh
"$tmp/prefix/bin/agent-box" --version
rm -rf "$tmp"
```

If the environment has a suitable Bubblewrap installation, `scripts/check-system.sh` is an additional operator-level verification. Unit/integration tests are designed not to require a real Bubblewrap sandbox for most coverage.

## Adding a CLI option

A new flag is incomplete unless all applicable items are done:

1. Add parsing/default state to `lib/cli.sh`.
2. Add the flag to `cb_usage`.
3. Add parsing assertions to `tests/test_cli.sh`.
4. Add behavior/argument assertions to `tests/test_bwrap_args.sh` or `tests/test_launcher.sh`.
5. Update the README parameter table and examples.
6. Update `SECURITY.md` if it changes isolation, persistence, credentials, network, Git, or host-write behavior.
7. Update this file if it changes the architecture or invariants.

## Changing mounts

Mount changes are security-sensitive. Before editing `cb_build_bwrap_args`, answer all of these:

- Is the source host path readable or writable?
- Does this create a new persistent host write location?
- Does a later mount override an earlier restriction?
- Does this expose host sockets, devices, credentials, or namespaces?
- Does the repo still punch through HOME at the same absolute path?
- Does the default remain safer than the opt-in mode?
- Is cleanup required for a new host-side temporary path?
- Are failure and non-zero child-exit paths tested?

Update `tests/test_bwrap_args.sh`, `tests/test_launcher.sh`, README and SECURITY for every material mount change.

## Known limitations

- **Linked Git worktrees:** backup is supported, but external worktree/common Git metadata is not automatically mounted RW. Working-tree file edits persist, while Git operations that must update external metadata can fail read-only.
- **Confidentiality:** host-readable secrets remain readable because `/` and HOME lower data are intentionally visible.
- **Selective egress:** there is no domain/port allowlist mode; networking is either shared or isolated with `--offline`.
- **Git remote-write enforcement:** the default guard blocks ordinary Git push paths but is not a general network firewall.
- **Crash cleanup:** `--disk-tmp` cleanup cannot run after `SIGKILL`, kernel crash, or sudden power loss.

## Security review triggers

Treat these as requiring explicit threat-model review:

- changing `--ro-bind / /`;
- changing HOME overlay semantics;
- adding any RW host bind other than the repository or private disk-tmp session;
- exposing anything from host `/run`;
- sharing SSH-agent, Docker/Podman, D-Bus, display-server, or similar sockets;
- changing network namespace behavior;
- changing Git push guards;
- lowering Bubblewrap minimum version;
- changing snapshot location/scope/atomicity;
- invoking repository-controlled code before the Git safety snapshot;
- changing cleanup semantics for host temporary directories.

## Documentation rules

Keep claims precise:

- Say **host write isolation**, not full machine isolation.
- Say **Git push guard**, not firewall.
- Say **Git metadata snapshot**, not full repository backup.
- Say HOME is **disposable COW**, not copied wholesale.
- Say `/tmp` is **private**, whether tmpfs or disk-backed.
- Explicitly mention persistent host write exceptions when adding them.

README is the operator/user contract. SECURITY is the threat-model contract. AGENTS is the maintainer/architecture contract. Keep them consistent with code and tests.

## Release workflow

Before tagging a release:

1. update `CB_VERSION` in `lib/common.sh`;
2. ensure `./agent-box --version` reports the intended version;
3. run the full verification commands above;
4. ensure the working tree contains only intended changes;
5. commit the release changes;
6. tag `v<version>`;
7. package the repository without unrelated build/cache artifacts;
8. extract the archive into a fresh directory and run the test suite there;
9. test `scripts/install.sh` from the extracted archive;
10. compute and publish the archive SHA-256.

Do not push or publish remotely from an automated coding session unless explicitly authorized.

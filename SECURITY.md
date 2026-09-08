# Security policy

## Reporting a vulnerability

Please report suspected vulnerabilities through a private [GitHub security advisory](https://github.com/abraxarion/agent-box/security/advisories/new).

Do not open a public issue with exploit details, secrets, private paths, or sensitive diagnostic output. Include:

- the affected agent-box and Bubblewrap versions;
- the Linux distribution and kernel version;
- the expected and observed isolation behavior;
- the smallest safe reproduction you can provide;
- any suggested mitigation.

Maintainers will acknowledge the report, assess its impact, and coordinate disclosure as promptly as the project's availability allows.

## Supported versions

| Version | Security updates |
|---|---|
| Latest 0.1.x release | Yes |
| Older releases | No |

Use the newest available agent-box release and Bubblewrap 0.12.0 or newer.

## Security model

`agent-box` is designed primarily to protect the host from unintended filesystem writes while allowing a coding agent to use the existing development environment.

### What the default sandbox protects

- The host filesystem is mounted read-only.
- One selected repository is the explicit host read/write exception.
- Writes elsewhere in HOME go to a disposable copy-on-write overlay.
- `/tmp` and `/run` are private.
- Host runtime sockets normally exposed below `/run` are hidden.
- PID, IPC, UTS, user, and cgroup namespaces are isolated.
- Git metadata is snapshotted before launch unless explicitly disabled.
- Ordinary Git push paths are blocked unless explicitly enabled.

### What it does not protect

#### Confidentiality

The host root is intentionally readable, and the real HOME is the lower layer of the disposable overlay. A sandboxed program can therefore read credentials and other files that the launching Unix account can read.

Do not treat agent-box as a secret-isolation boundary. Use a separate account, virtual machine, or purpose-built confidential-computing environment when code must not see host data.

#### Selective network egress

The default mode shares the network namespace so coding agents can reach their APIs. The Git push guard is not a firewall.

Use `--offline` when no normal external network access is acceptable. agent-box does not currently offer a domain or port allowlist.

#### Complete working-tree backup

The automatic ZIP stores Git metadata. It does not capture arbitrary untracked files or unstaged content that has never been stored in Git.

Git metadata can itself contain sensitive remote URLs, hooks, or configuration. Snapshot archives are created with mode `0600`; protect and delete them according to your local data-retention policy.

#### Malicious network clients

The Git policy prevents ordinary `git push` and `git send-pack` commands, including configured aliases that resolve to them. A hostile process with shared networking can invoke another Git executable, use another client, or implement a remote protocol itself.

## Bubblewrap minimum version

agent-box rejects Bubblewrap versions earlier than 0.12.0. Those releases are affected by [GHSA-pxhw-h44j-8pfx](https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx), a high-severity symlink traversal during sandbox setup. Bubblewrap 0.12.0 fixes the issue and removes support for setuid builds.

## Persistent host writes

The selected repository is always writable by design. With `--disk-tmp`, agent-box also creates a private mode-0700 session directory below the user's cache directory and mounts it at sandbox `/tmp`.

The repository bind is applied after the private runtime mounts so a project below `/tmp` remains accessible at its original path. Paths that are `/` or contain HOME, `/tmp`, `/run`, `/proc`, or `/dev` are rejected because rebinding one of those broad ancestors would undo a protection layer.

The disk-backed temporary directory is removed on normal launcher exit, including non-zero child exits. Cleanup cannot run after `SIGKILL`, a kernel crash, or sudden power loss, so stale session data can remain.

## Repository trust

The selected repository is writable by the sandbox. Build scripts, hooks, binaries, and dependencies inside it may therefore change during a session.

Git policy executables are copied beneath host `/tmp` before launch, independently of caller-controlled `TMPDIR`, and mounted read-only. Sandbox `/tmp` is replaced before the selected repository is rebound, so the source policy directory is unreachable through the writable repository.

## Linked worktrees

The snapshot helper recognizes linked worktrees and archives their common and worktree-specific Git metadata. The sandbox does not currently add read/write mounts for external linked-worktree metadata, so some Git operations may fail read-only even though working-tree file edits persist.

## Operational recommendations

- Review the repository and its startup hooks before launching an agent.
- Keep Bubblewrap and agent-box updated.
- Use `--offline` when API or package-network access is unnecessary.
- Keep the default Git snapshot and push guard enabled unless you have a specific reason not to.
- Review repository changes before committing, pushing, or executing generated code outside the sandbox.
- Remove stale disk-backed temporary directories only after confirming no agent-box session is using them.

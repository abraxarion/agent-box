# Security model

`agent-box` is designed primarily to protect the host from unintended filesystem writes while allowing an AI coding agent to work normally inside one selected repository.

## What the default sandbox protects

- The host filesystem is mounted read-only.
- The selected repository is the explicit host read/write exception.
- HOME writes go to a disposable tmpfs-backed overlay.
- `/tmp` and `/run` are private. `/tmp` is private tmpfs by default; `--disk-tmp` exposes only a per-session host cache directory at `/tmp`, never the host `/tmp` itself.
- Host runtime sockets normally exposed under `/run` are hidden.
- Process/IPC/UTS/user/cgroup namespaces are isolated.
- Git metadata is backed up before launch unless explicitly disabled.
- Ordinary Git push paths are blocked unless explicitly enabled.

## What it does not protect

### Confidentiality

The host root is intentionally readable, and HOME is intentionally used as the overlay lower layer. Therefore the sandbox may read secrets that your Unix account can read, including credentials stored in HOME or elsewhere.

Do not treat this configuration as a secret-isolation boundary.

### Selective network egress

The default mode shares the host network namespace so a coding agent can reach its API. Git-specific push guards are not equivalent to a firewall.

Use `--offline` when no network traffic is acceptable.

A future selective-egress mode should use an isolated network namespace with only a controlled proxy/firewall path exposed.

### Working-tree backup

The automatic ZIP archives Git metadata, not every working-tree byte. Untracked files and unstaged modifications are outside its scope.

## Bubblewrap minimum version

Versions before 0.12.0 are rejected because of:

- GHSA-pxhw-h44j-8pfx
- <https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx>

The advisory describes a sandbox-setup symlink traversal problem fixed in Bubblewrap 0.12.0.

## Git push guard threat model

The default push guard is defense in depth for normal Git execution:

- PATH wrapper;
- canonical Git executable shadowing;
- `git-send-pack` shadowing.

It is meant to prevent accidental or straightforward remote Git writes. It is not intended to defeat a hostile program that has unrestricted network access and deliberately implements a remote Git write protocol itself.

## Repository trust

The selected repository is writable by the sandbox. Build scripts, hooks, binaries, and dependencies inside it should therefore be treated as potentially mutable during the session.

The policy wrapper used for Git blocking is copied to a host temporary directory before sandbox launch and mounted read-only into the sandbox. This avoids relying on a policy file that might itself live inside the writable target repository.

## Disk-backed temporary storage

`--disk-tmp` deliberately creates one writable host directory below `${XDG_CACHE_HOME:-$HOME/.cache}/agent-box/tmp/` and bind-mounts that directory at sandbox `/tmp`. This is an additional host write exception alongside the selected repository, but it is restricted to a fresh mode-0700 session directory and is removed on normal launcher exit.

The cleanup trap cannot run after `SIGKILL`, a kernel crash, or sudden power loss. A stale session directory may therefore remain on disk after abnormal machine/process termination.

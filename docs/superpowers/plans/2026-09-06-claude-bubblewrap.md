# claude-bubblewrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a standalone `claude-bubblewrap` launcher that exposes the host read-only, overlays HOME with disposable tmpfs writes, bind-mounts one repository read/write, protects Git state, and launches Claude Code.

**Architecture:** A small Bash launcher sources focused libraries for CLI/preflight and Bubblewrap argument construction. A Python stdlib helper creates robust atomic Git ZIP snapshots. Git push policy is enforced with an immutable-at-launch wrapper copied into a host temporary runtime directory and mounted over Git entry points inside the sandbox.

**Tech Stack:** Bash 4.4+, Python 3.9+ stdlib, Git 2.x, Bubblewrap >= 0.12.0.

**Spec:** `docs/superpowers/specs/2026-09-06-claude-bubblewrap-design.md`

## Global Constraints

- Linux only.
- Preserve exact absolute repository paths.
- Host root is read-only; selected repo is read/write.
- Complete HOME uses a disposable tmpfs-backed overlay.
- Git metadata ZIP is on by default and fatal on backup failure.
- Git push is blocked by default.
- Bubblewrap older than 0.12.0 is rejected.
- No third-party Python packages.

---

### Task 1: CLI and preflight

**Files:**
- Create: `claude-bubblewrap`
- Create: `lib/common.sh`
- Create: `lib/cli.sh`
- Test: `tests/test_cli.sh`

**Interfaces:**
- Produces parsed globals `CB_REPO`, `CB_GIT_SAVE`, `CB_ALLOW_GIT_PUSH`, `CB_OFFLINE`, `CB_SHELL`, `CB_DRY_RUN`, `CB_CLAUDE_ARGS`.
- Produces `cb_require_command`, `cb_version_ge`, and `cb_check_bwrap_version`.

- [x] Write tests for help, defaults, option parsing, repo canonicalization, and semantic Bubblewrap version comparison.
- [x] Run them and confirm failure because launcher/libraries do not exist.
- [x] Implement the minimal CLI/preflight library and launcher wiring.
- [x] Re-run the tests until green.

### Task 2: Atomic Git metadata snapshots

**Files:**
- Create: `libexec/git-snapshot.py`
- Test: `tests/test_git_snapshot.sh`

**Interfaces:**
- `git-snapshot.py REPO` prints the final ZIP path, or `NO_GIT` for a non-Git directory.
- ZIP contains `manifest.json`, `git-common/`, and `worktree/gitfile` for linked worktrees.

- [x] Write tests for a normal repository, disabled launch path, linked worktree, archive naming, and absence of leftover temporary ZIPs.
- [x] Run and confirm failure because the snapshot helper does not exist.
- [x] Implement recursive ZIP creation with Unix metadata/symlink preservation, manifest generation, fsync, and atomic replace.
- [x] Re-run tests until green.

### Task 3: Git push policy

**Files:**
- Create: `libexec/git-policy`
- Create: `libexec/git-send-pack-block`
- Test: `tests/test_git_policy.sh`

**Interfaces:**
- `AGENT_BOX_REAL_GIT` points to the sandbox-private original Git binary.
- Policy wrapper rejects `push` and `send-pack`; otherwise execs the original Git.

- [x] Write tests proving status/log pass through and push/send-pack are rejected.
- [x] Run and confirm failure.
- [x] Implement both policy executables.
- [x] Re-run tests until green.

### Task 4: Bubblewrap construction and launch

**Files:**
- Create: `lib/bwrap.sh`
- Test: `tests/test_bwrap_args.sh`

**Interfaces:**
- `cb_build_bwrap_args` fills `CB_BWRAP_ARGS`.
- `cb_prepare_runtime_policy` creates immutable runtime copies for policy mounts.
- `cb_cleanup_runtime_policy` removes host temporary policy files after Bubblewrap exits.

- [x] Write tests for root RO bind, HOME tmp overlay, repo RW bind, private `/tmp`/`/run`, namespace isolation, default network sharing, offline mode, Git policy mounts, and allow-push mode.
- [x] Run and confirm failure.
- [x] Implement argument construction and runtime policy preparation.
- [x] Re-run tests until green.

### Task 5: End-to-end launcher, docs, and system check

**Files:**
- Modify: `claude-bubblewrap`
- Create: `scripts/check-system.sh`
- Create: `tests/test_launcher.sh`
- Create: `tests/run.sh`
- Create: `README.md`
- Create: `SECURITY.md`
- Create: `LICENSE`
- Create: `.gitignore`

**Interfaces:**
- Launcher performs snapshot preflight before Bubblewrap execution and propagates exit status.
- `scripts/check-system.sh` reports dependency/version readiness.

- [x] Write an end-to-end dry-run test proving snapshot-before-launch, skip flag, non-Git directory behavior, and Claude argument forwarding.
- [x] Run and confirm failure.
- [x] Complete launcher orchestration and system check.
- [x] Write installation, usage, recovery, and security documentation.
- [x] Run `tests/run.sh` and syntax checks.

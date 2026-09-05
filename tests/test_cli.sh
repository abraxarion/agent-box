#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/testlib.sh"

LAUNCHER="$TEST_ROOT/claude-bubblewrap"
COMMON="$TEST_ROOT/lib/common.sh"
CLI="$TEST_ROOT/lib/cli.sh"

help="$($LAUNCHER --help)"
assert_contains "$help" '--git-save-disabled' 'help exposes git save disable flag'
assert_contains "$help" '--allow-git-push' 'help exposes push opt-in'
assert_contains "$help" '--offline' 'help exposes offline mode'
assert_contains "$help" '--disk-tmp' 'help exposes disk-backed tmp mode'
pass 'help output'

# shellcheck disable=SC1090
source "$COMMON"
assert_eq yes "$(cb_version_ge 0.12.0 0.12.0 && echo yes || echo no)" 'equal versions accepted'
assert_eq yes "$(cb_version_ge 0.12.1 0.12.0 && echo yes || echo no)" 'newer versions accepted'
assert_eq no "$(cb_version_ge 0.11.2 0.12.0 && echo yes || echo no)" 'older versions rejected'
pass 'version comparison'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo"
# shellcheck disable=SC1090
source "$CLI"
cb_parse_args --git-save-disabled --allow-git-push --offline --disk-tmp --shell --dry-run "$work/repo" -- --model sonnet
assert_eq "$(realpath "$work/repo")" "$CB_REPO" 'repo canonicalized'
assert_eq 0 "$CB_GIT_SAVE" 'git save disabled'
assert_eq 1 "$CB_ALLOW_GIT_PUSH" 'push enabled when requested'
assert_eq 1 "$CB_OFFLINE" 'offline parsed'
assert_eq 1 "$CB_DISK_TMP" 'disk tmp parsed'
assert_eq 1 "$CB_SHELL" 'shell parsed'
assert_eq 1 "$CB_DRY_RUN" 'dry run parsed'
assert_eq '--model' "${CB_CLAUDE_ARGS[0]}" 'claude args forwarded'
assert_eq 'sonnet' "${CB_CLAUDE_ARGS[1]}" 'claude arg value forwarded'
pass 'argument parsing'

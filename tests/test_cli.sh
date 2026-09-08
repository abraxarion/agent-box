#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=testlib.sh
source "$(dirname "$0")/testlib.sh"

LAUNCHER="$TEST_ROOT/agent-box"
COMMON="$TEST_ROOT/lib/common.sh"
CLI="$TEST_ROOT/lib/cli.sh"

help="$($LAUNCHER --help)"
assert_contains "$help" '--git-save-disabled' 'help exposes git save disable flag'
assert_contains "$help" '--allow-git-push' 'help exposes push opt-in'
assert_contains "$help" '--offline' 'help exposes offline mode'
assert_contains "$help" '--disk-tmp' 'help exposes disk-backed tmp mode'
assert_contains "$help" 'interactive shell by default' 'help explains the default command'
assert_contains "$help" 'Start Claude Code instead of the default shell' 'help explains the Claude opt-in'
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
cb_parse_args --git-save-disabled --allow-git-push --offline --disk-tmp --claude --dry-run "$work/repo" -- --model sonnet
assert_eq "$(realpath "$work/repo")" "$CB_REPO" 'repo canonicalized'
assert_eq 0 "$CB_GIT_SAVE" 'git save disabled'
assert_eq 1 "$CB_ALLOW_GIT_PUSH" 'push enabled when requested'
assert_eq 1 "$CB_OFFLINE" 'offline parsed'
assert_eq 1 "$CB_DISK_TMP" 'disk tmp parsed'
assert_eq 1 "$CB_CLAUDE" 'claude parsed'
assert_eq 1 "$CB_DRY_RUN" 'dry run parsed'
assert_eq '--model' "${CB_COMMAND_ARGS[0]}" 'command args forwarded'
assert_eq 'sonnet' "${CB_COMMAND_ARGS[1]}" 'command arg value forwarded'
pass 'argument parsing'

set +e
error="$(cb_parse_args "$work/repo" "$work/repo" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'multiple repository paths must fail'
assert_contains "$error" 'put command arguments after --' 'path error explains generic argument forwarding'
pass 'multiple path error'

set +e
error="$(cb_parse_args /tmp 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'a protected mount root must not be accepted as the repository'
assert_contains "$error" 'contains protected path' 'broad path error explains the safety boundary'
pass 'protected mount root rejection'

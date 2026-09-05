#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/testlib.sh"
# shellcheck disable=SC1090
source "$TEST_ROOT/lib/common.sh"
# shellcheck disable=SC1090
source "$TEST_ROOT/lib/bwrap.sh"

work="$(mktemp -d)"
trap 'cb_cleanup_runtime_policy || true; rm -rf "$work"' EXIT
mkdir -p "$work/home/repo"
export HOME="$work/home"
export PATH="/usr/bin:/bin"
CB_REPO="$(realpath "$work/home/repo")"
CB_OFFLINE=0
CB_DISK_TMP=0
CB_DISK_TMP_DIR=""
CB_ALLOW_GIT_PUSH=0
CB_SHELL=0
CB_CLAUDE_ARGS=(--model sonnet)
CB_GIT_BIN="$(realpath "$(command -v git)")"
CB_GIT_EXEC_PATH="$(git --exec-path)"
cb_prepare_runtime_policy "$TEST_ROOT/libexec/git-policy" "$TEST_ROOT/libexec/git-send-pack-block"
cb_build_bwrap_args
joined="$(printf '%q ' "${CB_BWRAP_ARGS[@]}")"
assert_contains "$joined" '--ro-bind / /' 'root is read only'
assert_contains "$joined" "--overlay-src $HOME --tmp-overlay $HOME" 'home uses disposable overlay'
assert_contains "$joined" "--bind $CB_REPO $CB_REPO" 'repo is read write bind'
assert_contains "$joined" '--tmpfs /tmp' 'tmp is private'
assert_contains "$joined" '--tmpfs /run' 'run is private'
assert_contains "$joined" '--proc /proc' 'proc is private'
assert_contains "$joined" '--dev /dev' 'dev is private'
assert_contains "$joined" '--unshare-all --share-net' 'namespaces isolated with network shared'
assert_contains "$joined" '--die-with-parent --new-session' 'lifetime/session isolated'
assert_contains "$joined" "--chdir $CB_REPO" 'working directory is repo'
assert_contains "$joined" '/run/claude-bubblewrap/real-git' 'real git hidden behind wrapper'
assert_contains "$joined" "$CB_GIT_BIN" 'canonical git path shadowed'
# Some Git installations make git-send-pack a symlink/hardlink to the shared git
# executable. Shadowing its canonical target would break unrelated subcommands.
send_pack="$CB_GIT_EXEC_PATH/git-send-pack"
if [[ -e "$send_pack" ]]; then
  git_inode="$(stat -Lc '%d:%i' "$CB_GIT_BIN")"
  send_inode="$(stat -Lc '%d:%i' "$send_pack")"
  if [[ -L "$send_pack" || "$git_inode" == "$send_inode" ]]; then
    canonical_send="$(realpath "$send_pack")"
    assert_not_contains "$joined" "git-send-pack-block $canonical_send" 'shared git helper target must not be shadowed'
  fi
fi
pass 'default bwrap arguments'

CB_OFFLINE=1
cb_build_bwrap_args
joined="$(printf '%q ' "${CB_BWRAP_ARGS[@]}")"
assert_not_contains "$joined" '--share-net' 'offline mode does not share network'
pass 'offline bwrap arguments'

CB_OFFLINE=0
CB_ALLOW_GIT_PUSH=1
cb_build_bwrap_args
joined="$(printf '%q ' "${CB_BWRAP_ARGS[@]}")"
assert_not_contains "$joined" '/run/claude-bubblewrap/real-git' 'allow-push omits git shadow mounts'
pass 'allow push mode'

CB_ALLOW_GIT_PUSH=1
CB_DISK_TMP=1
export XDG_CACHE_HOME="$work/cache"
cb_prepare_disk_tmp
disk_tmp_dir="$CB_DISK_TMP_DIR"
assert_contains "$disk_tmp_dir" "$XDG_CACHE_HOME/claude-bubblewrap/tmp/claude-bubblewrap-tmp." 'disk tmp uses cache session path'
assert_eq 700 "$(stat -c '%a' "$disk_tmp_dir")" 'disk tmp session directory is private'
cb_build_bwrap_args
joined="$(printf '%q ' "${CB_BWRAP_ARGS[@]}")"
assert_contains "$joined" "--bind $disk_tmp_dir /tmp" 'disk tmp binds private host directory at /tmp'
assert_not_contains "$joined" '--tmpfs /tmp' 'disk tmp replaces tmpfs /tmp'
cb_cleanup_disk_tmp
[[ ! -e "$disk_tmp_dir" ]] || fail 'disk tmp session directory was not removed'
pass 'disk-backed tmp preparation, arguments, and cleanup'

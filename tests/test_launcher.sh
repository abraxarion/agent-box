#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=testlib.sh
source "$(dirname "$0")/testlib.sh"

LAUNCHER="$TEST_ROOT/agent-box"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
make_git_repo "$repo"

out="$($LAUNCHER --dry-run "$repo" -- --model sonnet 2>&1)"
assert_contains "$out" 'Git snapshot:' 'default launch creates snapshot'
assert_contains "$out" '--ro-bind / /' 'dry run prints bwrap command'
assert_contains "$out" '--model sonnet' 'claude args forwarded to command'
count="$(find "$work" -maxdepth 1 -name 'repo.git-save-*.zip' | wc -l)"
assert_eq 1 "$count" 'one snapshot created'
pass 'default dry-run orchestration'

rm -f "$work"/repo.git-save-*.zip
out="$($LAUNCHER --dry-run --git-save-disabled "$repo" 2>&1)"
count="$(find "$work" -maxdepth 1 -name 'repo.git-save-*.zip' | wc -l)"
assert_eq 0 "$count" 'disabled save creates no snapshot'
assert_contains "$out" 'Git snapshot: disabled' 'disabled save reported'
pass 'git save disable flag'

plain="$work/plain"
mkdir "$plain"
out="$($LAUNCHER --dry-run "$plain" 2>&1)"
assert_contains "$out" 'Git snapshot: not a Git repository' 'non-git directory accepted'
pass 'non-git launcher path'

fakebin="$work/fakebin"
mkdir -p "$fakebin"
cat > "$fakebin/claude" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fakebin/claude"
cat > "$work/fake-bwrap" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
  printf 'bubblewrap 0.12.0\n'
  exit 0
fi
printf '%s\n' "$@" > "$FAKE_BWRAP_LOG"
exit 37
SH
chmod +x "$work/fake-bwrap"
set +e
PATH="$fakebin:$PATH" FAKE_BWRAP_LOG="$work/bwrap.args" AGENT_BOX_BWRAP="$work/fake-bwrap" \
  "$LAUNCHER" --claude --git-save-disabled "$repo" -- --model sonnet >"$work/launch.out" 2>"$work/launch.err"
rc=$?
set -e
assert_eq 37 "$rc" 'launcher propagates bwrap child exit status'
assert_contains "$(cat "$work/bwrap.args")" 'claude' 'actual launch sends Claude command to bwrap'
assert_contains "$(cat "$work/bwrap.args")" 'sonnet' 'actual launch forwards Claude arguments'
pass 'actual launcher invocation and exit propagation'

cat > "$work/old-bwrap" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
  printf 'bubblewrap 0.11.2\n'
  exit 0
fi
printf 'unexpected-exec\n' >> "$FAKE_BWRAP_LOG"
exit 0
SH
chmod +x "$work/old-bwrap"
: > "$work/old.log"
set +e
PATH="$fakebin:$PATH" FAKE_BWRAP_LOG="$work/old.log" AGENT_BOX_BWRAP="$work/old-bwrap" \
  "$LAUNCHER" --git-save-disabled "$repo" >"$work/old.out" 2>"$work/old.err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'old Bubblewrap must be rejected'
assert_contains "$(cat "$work/old.err")" 'too old' 'old Bubblewrap rejection is explicit'
assert_eq '' "$(cat "$work/old.log")" 'old Bubblewrap is never used to launch sandbox'
pass 'Bubblewrap security floor enforced'


# --disk-tmp uses a private host-backed session directory and cleans it even
# when Bubblewrap exits non-zero.
rm -rf "$work/disk-cache"
set +e
PATH="$fakebin:$PATH" XDG_CACHE_HOME="$work/disk-cache" FAKE_BWRAP_LOG="$work/disk-bwrap.args" \
  AGENT_BOX_BWRAP="$work/fake-bwrap" \
  "$LAUNCHER" --git-save-disabled --disk-tmp "$repo" >"$work/disk.out" 2>"$work/disk.err"
rc=$?
set -e
assert_eq 37 "$rc" 'disk tmp launch preserves non-zero child exit status'
disk_args="$(cat "$work/disk-bwrap.args")"
assert_contains "$disk_args" "$work/disk-cache/agent-box/tmp/" 'disk tmp comes from private cache directory'
assert_contains "$disk_args" '/tmp' 'disk tmp is mounted at sandbox /tmp'
assert_no_match "$work/disk-cache/agent-box/tmp/agent-box-tmp.*"
pass 'disk tmp cleaned after failed sandbox'

# A zero-exit sandbox must clean the host-backed session directory as well.
cat > "$work/fake-bwrap-ok" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
  printf 'bubblewrap 0.12.0\n'
  exit 0
fi
printf '%s\n' "$@" > "$FAKE_BWRAP_LOG"
exit 0
SH
chmod +x "$work/fake-bwrap-ok"
rm -rf "$work/disk-cache-ok"
PATH="$fakebin:$PATH" XDG_CACHE_HOME="$work/disk-cache-ok" FAKE_BWRAP_LOG="$work/disk-ok.args" \
  AGENT_BOX_BWRAP="$work/fake-bwrap-ok" \
  "$LAUNCHER" --git-save-disabled --disk-tmp "$repo" >"$work/disk-ok.out" 2>"$work/disk-ok.err"
assert_no_match "$work/disk-cache-ok/agent-box/tmp/agent-box-tmp.*"
pass 'disk tmp cleaned after successful sandbox'

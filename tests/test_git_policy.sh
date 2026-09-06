#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/testlib.sh"

POLICY="$TEST_ROOT/libexec/git-policy"
BLOCK="$TEST_ROOT/libexec/git-send-pack-block"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/real-git" <<'SH'
#!/usr/bin/env bash
printf 'REAL_GIT:'
printf ' <%s>' "$@"
printf '\n'
SH
chmod +x "$work/real-git"

out="$(AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" status --short)"
assert_contains "$out" 'REAL_GIT: <status> <--short>' 'normal git passes through'
pass 'normal git passthrough'

set +e
AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" -C /tmp push origin main >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'git push must fail'
assert_contains "$(cat "$work/err")" 'git push is disabled' 'push emits policy message'
pass 'git push blocked'

set +e
AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" send-pack origin >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'git send-pack must fail'
pass 'git send-pack blocked'

set +e
"$BLOCK" origin >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'direct git-send-pack blocker must fail'
assert_contains "$(cat "$work/err")" 'git push is disabled' 'send-pack blocker emits policy message'
pass 'direct send-pack blocked'

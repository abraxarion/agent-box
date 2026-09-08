#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=testlib.sh
source "$(dirname "$0")/testlib.sh"

POLICY="$TEST_ROOT/libexec/git-policy"
BLOCK="$TEST_ROOT/libexec/git-send-pack-block"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/real-git" <<'SH'
#!/usr/bin/env bash
for ((index = 1; index < $#; index++)); do
  if [[ "${!index}" == "config" ]]; then
    next_index=$((index + 1))
    next_arg="${!next_index}"
    if [[ "$next_arg" == "--get" ]]; then
      exit 1
    fi
  fi
done
printf 'REAL_GIT:'
printf ' <%s>' "$@"
printf '\n'
SH
chmod +x "$work/real-git"

out="$(AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" status --short)"
assert_contains "$out" 'REAL_GIT: <status> <--short>' 'normal git passes through'
pass 'normal git passthrough'

out="$(AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" log -- push)"
assert_contains "$out" 'REAL_GIT: <log> <--> <push>' 'path named push passes through'
pass 'non-command push argument passthrough'

out="$(AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" --help push)"
assert_contains "$out" 'REAL_GIT: <--help> <push>' 'push help request passes through'
pass 'git push help passthrough'

set +e
AGENT_BOX_REAL_GIT="$work/real-git" "$POLICY" -C /tmp push origin main >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'git push must fail'
assert_contains "$(cat "$work/err")" 'git push is disabled' 'push emits policy message'
pass 'git push blocked'

alias_home="$work/alias-home"
alias_repo="$work/alias-repo"
alias_remote="$work/alias-remote.git"
mkdir -p "$alias_home"
make_git_repo "$alias_repo"
git init -q --bare "$alias_remote"

set +e
HOME="$alias_home" AGENT_BOX_REAL_GIT="$(command -v git)" \
  "$POLICY" -C "$alias_repo" push -v "$alias_remote" HEAD:refs/heads/verbose \
  >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'verbose git push must fail'
if git --git-dir="$alias_remote" show-ref --verify --quiet refs/heads/verbose; then
  fail 'verbose push updated the remote'
fi
assert_contains "$(cat "$work/err")" 'git push is disabled' 'verbose push emits policy message'
pass 'verbose git push blocked'

HOME="$alias_home" git config --global alias.publish push
set +e
HOME="$alias_home" AGENT_BOX_REAL_GIT="$(command -v git)" \
  "$POLICY" -C "$alias_repo" publish "$alias_remote" HEAD:refs/heads/main \
  >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'git alias resolving to push must fail'
if git --git-dir="$alias_remote" show-ref --verify --quiet refs/heads/main; then
  fail 'push alias updated the remote'
fi
assert_contains "$(cat "$work/err")" 'git push is disabled' 'push alias emits policy message'
pass 'git push alias blocked'

HOME="$alias_home" git config --global alias.optionpublish '-c color.ui=false push'
set +e
HOME="$alias_home" AGENT_BOX_REAL_GIT="$(command -v git)" \
  "$POLICY" -C "$alias_repo" optionpublish "$alias_remote" HEAD:refs/heads/option-alias \
  >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'git alias with global options resolving to push must fail'
if git --git-dir="$alias_remote" show-ref --verify --quiet refs/heads/option-alias; then
  fail 'push alias with global options updated the remote'
fi
assert_contains "$(cat "$work/err")" 'git push is disabled' 'option-prefixed push alias emits policy message'
pass 'git push alias with global options blocked'

for ((alias_index = 1; alias_index <= 16; alias_index++)); do
  HOME="$alias_home" git config --global "alias.chain$alias_index" "chain$((alias_index + 1))"
done
HOME="$alias_home" git config --global alias.chain17 push
set +e
HOME="$alias_home" AGENT_BOX_REAL_GIT="$(command -v git)" \
  "$POLICY" -C "$alias_repo" chain1 "$alias_remote" HEAD:refs/heads/long-alias-chain \
  >"$work/out" 2>"$work/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'long git alias chain resolving to push must fail'
if git --git-dir="$alias_remote" show-ref --verify --quiet refs/heads/long-alias-chain; then
  fail 'long push alias chain updated the remote'
fi
assert_contains "$(cat "$work/err")" 'git push is disabled' 'long push alias chain emits policy message'
pass 'long git push alias chain blocked'

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

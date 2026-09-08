#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=testlib.sh
source "$(dirname "$0")/testlib.sh"

SNAPSHOT="$TEST_ROOT/libexec/git-snapshot.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
make_git_repo "$repo"
archive="$(umask 0777; "$SNAPSHOT" "$repo")"
assert_file "$archive"
assert_eq 600 "$(stat -c '%a' "$archive")" 'archive is private despite caller umask'
assert_eq "$(dirname "$repo")" "$(dirname "$archive")" 'archive stored above repo'
assert_contains "$(basename "$archive")" 'repo.git-save-' 'timestamped archive name'
python3 - "$archive" <<'PY'
import json, sys, zipfile
p=sys.argv[1]
with zipfile.ZipFile(p) as z:
    names=set(z.namelist())
    assert 'manifest.json' in names
    assert 'git-common/HEAD' in names
    manifest=json.loads(z.read('manifest.json'))
    assert manifest['repository_kind'] == 'standard'
PY
assert_no_match "$work/.repo.git-save-*.tmp"
pass 'standard repository snapshot'

main="$work/main"
make_git_repo "$main"
wt="$work/feature"
git -C "$main" worktree add -q -b feature "$wt"
wt_archive="$($SNAPSHOT "$wt")"
python3 - "$wt_archive" <<'PY'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    names=set(z.namelist())
    assert 'worktree/gitfile' in names
    assert 'git-common/HEAD' in names
    manifest=json.loads(z.read('manifest.json'))
    assert manifest['repository_kind'] == 'linked-worktree'
    assert manifest['git_dir'] != manifest['git_common_dir']
PY
pass 'linked worktree snapshot'

plain="$work/plain"
mkdir "$plain"
out="$($SNAPSHOT "$plain")"
assert_eq NO_GIT "$out" 'non-git directory is reported'
pass 'non-git directory'

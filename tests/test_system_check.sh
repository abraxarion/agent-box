#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=testlib.sh
source "$(dirname "$0")/testlib.sh"

CHECK="$TEST_ROOT/scripts/check-system.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fakebin="$work/bin"
mkdir -p "$fakebin"

cat > "$fakebin/bash" <<'SH'
#!/usr/bin/env sh
printf 'GNU bash, version %s(1)-release\n' "${FAKE_BASH_VERSION:-5.2.0}"
SH
cat > "$fakebin/python3" <<'SH'
#!/usr/bin/env sh
printf 'Python %s\n' "${FAKE_PYTHON_VERSION:-3.11.0}"
SH
cat > "$fakebin/git" <<'SH'
#!/usr/bin/env sh
printf 'git version %s\n' "${FAKE_GIT_VERSION:-2.40.0}"
SH
cat > "$fakebin/bwrap" <<'SH'
#!/usr/bin/env sh
printf 'bubblewrap 0.12.0\n'
SH
chmod +x "$fakebin/"*

run_check() {
  PATH="$fakebin:/usr/bin:/bin" /bin/bash "$CHECK" 2>&1
}

set +e
out="$(FAKE_PYTHON_VERSION=3.8.18 run_check)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'Python below 3.9 must fail the system check'
assert_contains "$out" 'python3      FAIL 3.8.18 (need >= 3.9)' 'old Python failure is explicit'
pass 'Python minimum version enforced'

set +e
out="$(FAKE_BASH_VERSION=4.3.0 run_check)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'Bash below 4.4 must fail the system check'
assert_contains "$out" 'bash         FAIL 4.3.0 (need >= 4.4)' 'old Bash failure is explicit'
pass 'Bash minimum version enforced'

set +e
out="$(FAKE_GIT_VERSION=1.9.5 run_check)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail 'Git below 2.0 must fail the system check'
assert_contains "$out" 'git          FAIL 1.9.5 (need >= 2.0)' 'old Git failure is explicit'
pass 'Git minimum version enforced'

space_fakebin="$work/bin with spaces"
mkdir -p "$space_fakebin"
cp -a "$fakebin/." "$space_fakebin/"
set +e
out="$(PATH="$space_fakebin:/usr/bin:/bin" /bin/bash "$CHECK" 2>&1)"
rc=$?
set -e
[[ $rc -eq 0 ]] || fail 'system check must support a Bubblewrap executable path containing spaces'
assert_contains "$out" 'bwrap        OK  0.12.0' 'spaced Bubblewrap path is invoked intact'
pass 'Bubblewrap executable path quoting'

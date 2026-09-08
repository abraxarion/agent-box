#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=testlib.sh
source "$(dirname "$0")/testlib.sh"

assert_file "$TEST_ROOT/assets/agent-box-icon.png"
assert_file "$TEST_ROOT/CONTRIBUTING.md"
assert_file "$TEST_ROOT/CODE_OF_CONDUCT.md"
assert_file "$TEST_ROOT/CHANGELOG.md"
assert_file "$TEST_ROOT/.github/workflows/ci.yml"
assert_file "$TEST_ROOT/.github/ISSUE_TEMPLATE/bug_report.yml"
assert_file "$TEST_ROOT/.github/ISSUE_TEMPLATE/feature_request.yml"
assert_file "$TEST_ROOT/.github/pull_request_template.md"

readme="$(cat "$TEST_ROOT/README.md")"
assert_contains "$readme" 'assets/agent-box-icon.png' 'README embeds the project icon'
assert_contains "$readme" 'https://github.com/abraxarion/agent-box' 'README uses the public repository URL'

[[ ! -e "$TEST_ROOT/.claude" ]] || fail 'public package must not include local Claude tooling'
[[ ! -e "$TEST_ROOT/.ignore" ]] || fail 'public package must not include local search-tool configuration'
[[ ! -e "$TEST_ROOT/docs/superpowers" ]] || fail 'public package must not include internal planning documents'
if find "$TEST_ROOT" -type d -name __pycache__ -print -quit | grep -q .; then
  fail 'public package must not include Python bytecode caches'
fi

if grep -R -nE 'claude-bubblewrap|agent-bubblewrap' \
  "$TEST_ROOT/README.md" "$TEST_ROOT/SECURITY.md" "$TEST_ROOT/AGENTS.md" \
  "$TEST_ROOT/agent-box" "$TEST_ROOT/lib" "$TEST_ROOT/libexec" "$TEST_ROOT/scripts"; then
  fail 'public-facing files contain obsolete project names'
fi

pass 'public repository presentation and hygiene'

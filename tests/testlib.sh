#!/usr/bin/env bash
set -euo pipefail
# Values and helpers in this file are consumed by scripts that source it.
# shellcheck disable=SC2034

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS_COUNT=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_eq() {
  local expected="$1" actual="$2" message="${3:-values differ}"
  [[ "$actual" == "$expected" ]] || fail "$message (expected=$expected actual=$actual)"
}

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-missing text}"
  [[ "$haystack" == *"$needle"* ]] || fail "$message (needle=$needle)"
}

assert_not_contains() {
  local haystack="$1" needle="$2" message="${3:-unexpected text}"
  [[ "$haystack" != *"$needle"* ]] || fail "$message (needle=$needle)"
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_no_match() {
  local pattern="$1"
  compgen -G "$pattern" >/dev/null && fail "unexpected match: $pattern"
  return 0
}

make_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.name Test
  git -C "$dir" config user.email test@example.invalid
  printf 'hello\n' > "$dir/file.txt"
  git -C "$dir" add file.txt
  git -C "$dir" commit -q -m initial
}

#!/usr/bin/env bash
# shellcheck shell=bash
# Version state is consumed by scripts that source this file.
# shellcheck disable=SC2034

CB_VERSION="0.1.2"
CB_MIN_BASH_VERSION="4.4"
CB_MIN_GIT_VERSION="2.0"
CB_MIN_PYTHON_VERSION="3.9"
CB_MIN_BWRAP_VERSION="0.12.0"

cb_die() {
  printf 'agent-box: ERROR: %s\n' "$*" >&2
  exit 1
}

cb_warn() {
  printf 'agent-box: WARNING: %s\n' "$*" >&2
}

cb_info() {
  printf 'agent-box: %s\n' "$*" >&2
}

cb_require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || cb_die "required command not found: $name"
}

cb_version_ge() {
  local actual="$1" required="$2" first
  first="$(printf '%s\n%s\n' "$required" "$actual" | LC_ALL=C sort -V | head -n1)"
  [[ "$first" == "$required" ]]
}

cb_bwrap_version() {
  local bwrap_bin="$1" out version
  out="$("$bwrap_bin" --version 2>/dev/null)" || return 1
  version="$(printf '%s\n' "$out" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  [[ -n "$version" ]] || return 1
  printf '%s\n' "$version"
}

cb_check_bwrap_version() {
  local bwrap_bin="$1" actual
  actual="$(cb_bwrap_version "$bwrap_bin")" || cb_die "unable to determine Bubblewrap version from: $bwrap_bin --version"
  if ! cb_version_ge "$actual" "$CB_MIN_BWRAP_VERSION"; then
    cb_die "Bubblewrap $actual is too old; version $CB_MIN_BWRAP_VERSION or newer is required (GHSA-pxhw-h44j-8pfx affects older versions)"
  fi
}

cb_print_command() {
  printf '%q ' "$@"
  printf '\n'
}

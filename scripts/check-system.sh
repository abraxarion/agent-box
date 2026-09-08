#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

status=0
printf 'agent-box system check\n\n'

check_versioned_command() {
  local name="$1" required="$2" output actual
  if ! command -v "$name" >/dev/null 2>&1; then
    printf '%-12s FAIL missing (need >= %s)\n' "$name" "$required"
    status=1
    return
  fi

  case "$name" in
    bash) output="$(bash --version | head -n1)" ;;
    python3) output="$(python3 --version 2>&1)" ;;
    git) output="$(git --version)" ;;
  esac
  actual="$(printf '%s\n' "$output" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1)"
  if [[ -n "$actual" ]] && cb_version_ge "$actual" "$required"; then
    printf '%-12s OK  %s\n' "$name" "$actual"
  else
    printf '%-12s FAIL %s (need >= %s)\n' "$name" "${actual:-unknown}" "$required"
    status=1
  fi
}

check_versioned_command bash "$CB_MIN_BASH_VERSION"
check_versioned_command python3 "$CB_MIN_PYTHON_VERSION"
check_versioned_command git "$CB_MIN_GIT_VERSION"

if command -v realpath >/dev/null 2>&1; then
  printf '%-12s OK  %s\n' realpath "$(command -v realpath)"
else
  printf '%-12s FAIL missing\n' realpath
  status=1
fi

if command -v bwrap >/dev/null 2>&1; then
  version="$(cb_bwrap_version "$(command -v bwrap)" || true)"
  if [[ -n "$version" ]] && cb_version_ge "$version" "$CB_MIN_BWRAP_VERSION"; then
    printf '%-12s OK  %s\n' bwrap "$version"
  else
    printf '%-12s FAIL %s (need >= %s)\n' bwrap "${version:-unknown}" "$CB_MIN_BWRAP_VERSION"
    status=1
  fi
else
  printf '%-12s FAIL missing (need >= %s)\n' bwrap "$CB_MIN_BWRAP_VERSION"
  status=1
fi

if command -v claude >/dev/null 2>&1; then
  printf '%-12s OK  %s\n' claude "$(command -v claude)"
else
  printf '%-12s WARN not found (only required with --claude)\n' claude
fi

exit "$status"

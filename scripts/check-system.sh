#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

status=0
printf 'claude-bubblewrap system check\n\n'

for cmd in bash python3 git realpath; do
  if command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in
      bash) printf '%-12s OK  %s\n' bash "$(bash --version | head -n1)" ;;
      python3) printf '%-12s OK  %s\n' python3 "$(python3 --version 2>&1)" ;;
      git) printf '%-12s OK  %s\n' git "$(git --version)" ;;
      realpath) printf '%-12s OK  %s\n' realpath "$(command -v realpath)" ;;
    esac
  else
    printf '%-12s FAIL missing\n' "$cmd"
    status=1
  fi
done

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
  printf '%-12s WARN not found (only required outside interactive shell mode)\n' claude
fi

exit "$status"

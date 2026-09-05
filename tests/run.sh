#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for t in "$ROOT"/tests/test_*.sh; do
  [[ "$(basename "$t")" == testlib.sh ]] && continue
  printf '\n== %s ==\n' "$(basename "$t")"
  "$t"
done
printf '\nAll tests passed.\n'

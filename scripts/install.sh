#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
LIBDIR="$PREFIX/lib/agent-box"
BINDIR="$PREFIX/bin"

mkdir -p "$LIBDIR" "$BINDIR"
rm -rf -- "${LIBDIR:?}/lib" "${LIBDIR:?}/libexec"
cp -- "$ROOT/agent-box" "$LIBDIR/agent-box"
cp -R -- "$ROOT/lib" "$LIBDIR/lib"
cp -R -- "$ROOT/libexec" "$LIBDIR/libexec"
chmod +x -- "$LIBDIR/agent-box" "$LIBDIR/libexec/"*
ln -sfn -- "$LIBDIR/agent-box" "$BINDIR/agent-box"
printf 'Installed agent-box to %s\n' "$BINDIR/agent-box"
printf 'Ensure %s is in PATH.\n' "$BINDIR"

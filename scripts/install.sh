#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
LIBDIR="$PREFIX/lib/claude-bubblewrap"
BINDIR="$PREFIX/bin"

mkdir -p "$LIBDIR" "$BINDIR"
rm -rf "$LIBDIR/lib" "$LIBDIR/libexec"
cp "$ROOT/claude-bubblewrap" "$LIBDIR/claude-bubblewrap"
cp -R "$ROOT/lib" "$LIBDIR/lib"
cp -R "$ROOT/libexec" "$LIBDIR/libexec"
chmod +x "$LIBDIR/claude-bubblewrap" "$LIBDIR/libexec/"*
ln -sfn "$LIBDIR/claude-bubblewrap" "$BINDIR/claude-bubblewrap"
printf 'Installed claude-bubblewrap to %s\n' "$BINDIR/claude-bubblewrap"
printf 'Ensure %s is in PATH.\n' "$BINDIR"

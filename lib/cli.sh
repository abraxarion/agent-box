#!/usr/bin/env bash
# shellcheck shell=bash

cb_usage() {
  cat <<'USAGE'
Usage:
  claude-bubblewrap [OPTIONS] [REPO] [-- CLAUDE_ARGS...]

Run Claude Code in a Bubblewrap sandbox with the host filesystem read-only,
a disposable writable HOME overlay, and one repository bind-mounted read/write.

Options:
  --git-save-disabled  Do not create the pre-launch Git metadata ZIP.
  --no-git-save        Alias for --git-save-disabled.
  --allow-git-push     Disable the default Git push guards.
  --offline            Keep Bubblewrap's isolated network namespace.
  --disk-tmp           Back sandbox /tmp with a private host disk directory.
  --shell              Start $SHELL (or /bin/bash) instead of Claude Code.
  --dry-run            Run preflight, print the bwrap command, and stop.
  -h, --help           Show this help.
  --version            Show claude-bubblewrap version.

If REPO is omitted, the current directory is used.
USAGE
}

cb_parse_args() {
  CB_REPO=""
  CB_GIT_SAVE=1
  CB_ALLOW_GIT_PUSH=0
  CB_OFFLINE=0
  CB_DISK_TMP=0
  CB_SHELL=0
  CB_DRY_RUN=0
  CB_CLAUDE_ARGS=()

  local parsing=1 arg
  while (($#)); do
    arg="$1"
    shift

    if (( ! parsing )); then
      CB_CLAUDE_ARGS+=("$arg")
      continue
    fi

    case "$arg" in
      --)
        parsing=0
        ;;
      --git-save-disabled|--no-git-save)
        CB_GIT_SAVE=0
        ;;
      --allow-git-push)
        CB_ALLOW_GIT_PUSH=1
        ;;
      --offline)
        CB_OFFLINE=1
        ;;
      --disk-tmp)
        CB_DISK_TMP=1
        ;;
      --shell)
        CB_SHELL=1
        ;;
      --dry-run)
        CB_DRY_RUN=1
        ;;
      -h|--help)
        cb_usage
        exit 0
        ;;
      --version)
        printf 'claude-bubblewrap %s\n' "$CB_VERSION"
        exit 0
        ;;
      -* )
        cb_die "unknown option: $arg"
        ;;
      *)
        if [[ -n "$CB_REPO" ]]; then
          cb_die "multiple repository paths supplied; put Claude arguments after --"
        fi
        CB_REPO="$arg"
        ;;
    esac
  done

  [[ -n "$CB_REPO" ]] || CB_REPO="$PWD"
  [[ -d "$CB_REPO" ]] || cb_die "repository directory does not exist: $CB_REPO"
  CB_REPO="$(realpath "$CB_REPO")"
}

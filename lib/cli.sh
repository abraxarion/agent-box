#!/usr/bin/env bash
# shellcheck shell=bash
# State set here is consumed by the launcher after this file is sourced.
# shellcheck disable=SC2034

cb_usage() {
  cat <<'USAGE'
Usage:
  agent-box [OPTIONS] [REPO] [-- COMMAND_ARGS...]

Run an interactive shell by default inside a Bubblewrap sandbox with the host
filesystem read-only, a disposable writable HOME overlay, and one repository
bind-mounted read/write.

Options:
  --git-save-disabled  Do not create the pre-launch Git metadata ZIP.
  --no-git-save        Alias for --git-save-disabled.
  --allow-git-push     Disable the default Git push guards.
  --offline            Keep Bubblewrap's isolated network namespace.
  --disk-tmp           Back sandbox /tmp with a private host disk directory.
  --claude             Start Claude Code instead of the default shell.
  --dry-run            Run preflight, print the bwrap command, and stop.
  -h, --help           Show this help.
  --version            Show agent-box version.

If REPO is omitted, the current directory is used.
Arguments after -- are forwarded to the selected shell or Claude Code.
USAGE
}

cb_validate_repo_scope() {
  local repo="$1" home_path protected_path
  [[ "$repo" != / ]] ||
    cb_die "repository path is too broad: / contains protected system paths; select a project subdirectory"

  [[ -n "${HOME:-}" ]] || cb_die "HOME is required"
  home_path="$(realpath "$HOME")"
  for protected_path in "$home_path" /tmp /run /proc /dev; do
    case "$protected_path/" in
      "$repo/"*)
        cb_die "repository path is too broad: $repo contains protected path $protected_path; select a project subdirectory"
        ;;
    esac
  done
}

cb_parse_args() {
  CB_REPO=""
  CB_GIT_SAVE=1
  CB_ALLOW_GIT_PUSH=0
  CB_OFFLINE=0
  CB_DISK_TMP=0
  CB_CLAUDE=0
  CB_DRY_RUN=0
  CB_COMMAND_ARGS=()

  local parsing=1 arg
  while (($#)); do
    arg="$1"
    shift

    if (( ! parsing )); then
      CB_COMMAND_ARGS+=("$arg")
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
      --claude)
        CB_CLAUDE=1
        ;;
      --dry-run)
        CB_DRY_RUN=1
        ;;
      -h|--help)
        cb_usage
        exit 0
        ;;
      --version)
        printf 'agent-box %s\n' "$CB_VERSION"
        exit 0
        ;;
      -* )
        cb_die "unknown option: $arg"
        ;;
      *)
        if [[ -n "$CB_REPO" ]]; then
          cb_die "multiple repository paths supplied; put command arguments after --"
        fi
        CB_REPO="$arg"
        ;;
    esac
  done

  [[ -n "$CB_REPO" ]] || CB_REPO="$PWD"
  [[ -d "$CB_REPO" ]] || cb_die "repository directory does not exist: $CB_REPO"
  CB_REPO="$(realpath "$CB_REPO")"
  cb_validate_repo_scope "$CB_REPO"
}

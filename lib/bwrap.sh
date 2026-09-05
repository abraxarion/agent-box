#!/usr/bin/env bash
# shellcheck shell=bash

CB_RUNTIME_POLICY_DIR=""
CB_BWRAP_ARGS=()

cb_prepare_runtime_policy() {
  local policy_src="$1" send_pack_src="$2"
  if (( CB_ALLOW_GIT_PUSH )); then
    return 0
  fi

  CB_RUNTIME_POLICY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-bubblewrap-policy.XXXXXX")"
  cp -- "$policy_src" "$CB_RUNTIME_POLICY_DIR/git-policy"
  cp -- "$send_pack_src" "$CB_RUNTIME_POLICY_DIR/git-send-pack-block"
  chmod 0555 "$CB_RUNTIME_POLICY_DIR/git-policy" "$CB_RUNTIME_POLICY_DIR/git-send-pack-block"
}

cb_cleanup_runtime_policy() {
  if [[ -n "${CB_RUNTIME_POLICY_DIR:-}" && -d "$CB_RUNTIME_POLICY_DIR" ]]; then
    chmod -R u+w "$CB_RUNTIME_POLICY_DIR" 2>/dev/null || true
    rm -rf -- "$CB_RUNTIME_POLICY_DIR"
  fi
  CB_RUNTIME_POLICY_DIR=""
}

cb_build_bwrap_args() {
  CB_BWRAP_ARGS=(
    --ro-bind / /
    --overlay-src "$HOME"
    --tmp-overlay "$HOME"
    --bind "$CB_REPO" "$CB_REPO"
    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --tmpfs /run
  )

  if (( ! CB_ALLOW_GIT_PUSH )); then
    [[ -n "$CB_RUNTIME_POLICY_DIR" ]] || cb_die "runtime Git policy was not prepared"
    CB_BWRAP_ARGS+=(
      --dir /run/claude-bubblewrap
      --dir /run/claude-bubblewrap/bin
      --ro-bind "$CB_GIT_BIN" /run/claude-bubblewrap/real-git
      --ro-bind "$CB_RUNTIME_POLICY_DIR/git-policy" /run/claude-bubblewrap/bin/git
      --ro-bind "$CB_RUNTIME_POLICY_DIR/git-policy" "$CB_GIT_BIN"
      --setenv CLAUDE_BUBBLEWRAP_REAL_GIT /run/claude-bubblewrap/real-git
      --setenv PATH "/run/claude-bubblewrap/bin:${PATH:-/usr/local/bin:/usr/bin:/bin}"
    )

    local send_pack="$CB_GIT_EXEC_PATH/git-send-pack"
    if [[ -e "$send_pack" ]]; then
      local git_inode send_pack_inode
      git_inode="$(stat -Lc '%d:%i' "$CB_GIT_BIN" 2>/dev/null || true)"
      send_pack_inode="$(stat -Lc '%d:%i' "$send_pack" 2>/dev/null || true)"
      # Many Git packages implement git-send-pack as a symlink/hardlink to the
      # shared git executable. Mounting a blocker on that target would also
      # break unrelated Git subcommands, so only shadow a distinct helper.
      if [[ ! -L "$send_pack" && -n "$git_inode" && -n "$send_pack_inode" && "$git_inode" != "$send_pack_inode" ]]; then
        CB_BWRAP_ARGS+=(--ro-bind "$CB_RUNTIME_POLICY_DIR/git-send-pack-block" "$send_pack")
      fi
    fi
  fi

  CB_BWRAP_ARGS+=(--unshare-all)
  if (( ! CB_OFFLINE )); then
    CB_BWRAP_ARGS+=(--share-net)
  fi
  CB_BWRAP_ARGS+=(
    --die-with-parent
    --new-session
    --chdir "$CB_REPO"
    --
  )

  if (( CB_SHELL )); then
    CB_BWRAP_ARGS+=("${SHELL:-/bin/bash}")
    CB_BWRAP_ARGS+=("${CB_CLAUDE_ARGS[@]}")
  else
    CB_BWRAP_ARGS+=(claude)
    CB_BWRAP_ARGS+=("${CB_CLAUDE_ARGS[@]}")
  fi
}

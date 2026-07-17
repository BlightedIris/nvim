#!/usr/bin/env bash
#
# nvim-bootstrap.sh — sync native-package plugins + LSP servers, no plugin manager.
#
#   ./nvim-bootstrap.sh            # everything
#   ./nvim-bootstrap.sh plugins    # plugins only
#   ./nvim-bootstrap.sh lsp        # LSP servers only
#   ./nvim-bootstrap.sh status     # show pinned vs installed
#
# Idempotent: safe to re-run. Records resolved SHAs to pack.lock.

set -euo pipefail

NVIM_CFG="${NVIM_CFG:-$HOME/.config/nvim}"
OPT_DIR="${OPT_DIR:-$HOME/.local/opt}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
LOCKFILE="$NVIM_CFG/pack.lock"

# nvim-treesitter's default branch is now `main` (the rewrite, different API).
# `master` is the legacy branch most configs/guides still assume. Pick deliberately.
TS_BRANCH="${TS_BRANCH:-master}"

# blink.cmp: MUST be an exact tag, see notes at the bottom of this file.
BLINK_TAG="${BLINK_TAG:-v1.10.2}"

# ---------------------------------------------------------------- plugin sets
# format: owner/repo | target-dirname | ref (branch, tag, or empty = default branch)

BASICS=(
  "saghen/blink.cmp|blink-cmp|${BLINK_TAG}"
  "akinsho/bufferline.nvim|bufferline|"
  "nvim-lualine/lualine.nvim|lualine-nvim|"
  "rktjmp/lush.nvim|lush-nvim|"
  "neovim/nvim-lspconfig|nvim-lspconfig|"
  "nvim-treesitter/nvim-treesitter|nvim-treesitter|${TS_BRANCH}"
  "nvim-tree/nvim-web-devicons|nvim-web-devicons|"
  "nvim-lua/plenary.nvim|plenary-nvim|"
  "folke/todo-comments.nvim|todo-comments-nvim|"
)

THEMES=(
  "rebelot/kanagawa.nvim|kanagawa.nvim|"
  "savq/melange-nvim|melange-nvim|"
  "aktersnurra/no-clown-fiesta.nvim|no-clown-fiesta.nvim|"
)

# NOTE: saghen/frizbee is deliberately NOT here. See notes at the bottom.

# ---------------------------------------------------------------- LSP servers
# Each entry installs a single static binary from a GitHub release.
# No npm, no pip, no cargo, no Mason. Add rows as you add languages.
#
# format: repo | binary-name | asset-template | strip-v-prefix
#   asset-template placeholders: {ver} {os} {arch}
LSP_RELEASES=(
  "LuaLS/lua-language-server|lua-language-server|lua-language-server-{ver}-{os}-{arch}.tar.gz|no"
)

# ---------------------------------------------------------------------- utils
c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'
c_green=$'\033[1;32m'; c_dim=$'\033[2m'; c_off=$'\033[0m'

log()  { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$c_green" "$c_off" "$*"; }
skip() { printf '%s   ·%s %s\n' "$c_dim" "$c_off" "$*"; }
warn() { printf '%s  !!%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s  xx%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

detect_platform() {
  case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=x64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) die "unsupported arch: $(uname -m)" ;;
  esac
}

# newest semver-ish tag, without hitting the rate-limited REST API.
# NB: no `| head`, that SIGPIPEs git and trips `pipefail`.
latest_tag() {
  local out
  out="$(git ls-remote --tags --refs --sort='-v:refname' "https://github.com/$1.git")" || return 1
  printf '%s\n' "$out" | sed -n '1s;.*refs/tags/;;p'
}

# --------------------------------------------------------------------- plugins
sync_repo() {
  local slug="$1" dir="$2" ref="$3" name
  name="$(basename "$dir")"

  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --quiet --tags --prune origin
  elif [[ -e "$dir" ]]; then
    die "$dir exists but is not a git repo — move it aside first"
  else
    git clone --quiet "https://github.com/$slug.git" "$dir"
  fi

  if [[ -n "$ref" ]]; then
    if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$ref"; then
      # branch: track it and fast-forward
      git -C "$dir" checkout --quiet -B "$ref" "origin/$ref"
    elif git -C "$dir" rev-parse --quiet --verify "refs/tags/$ref^{commit}" >/dev/null; then
      # tag: detach onto it. blink.cmp's downloader needs `git describe
      # --tags --exact-match` to succeed, which a detached tag satisfies.
      git -C "$dir" checkout --quiet --detach "refs/tags/$ref"
    else
      die "$name: no such ref '$ref'"
    fi
  else
    local head
    head="$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    head="${head#origin/}"
    [[ -n "$head" ]] && git -C "$dir" checkout --quiet -B "$head" "origin/$head"
  fi

  local sha
  sha="$(git -C "$dir" rev-parse --short HEAD)"
  printf '%s\t%s\t%s\n' "$slug" "${ref:-<default>}" "$(git -C "$dir" rev-parse HEAD)" >> "$LOCKFILE.tmp"
  ok "$(printf '%-24s' "$name") ${ref:-default}@$sha"
}

sync_group() {
  local group="$1"; shift
  local target="$NVIM_CFG/pack/$group/start"
  mkdir -p "$target"
  log "pack/$group/start"
  local entry slug dir ref
  for entry in "$@"; do
    IFS='|' read -r slug dir ref <<< "$entry"
    sync_repo "$slug" "$target/$dir" "$ref"
  done
}

do_plugins() {
  need git; need nvim
  mkdir -p "$NVIM_CFG"
  : > "$LOCKFILE.tmp"
  sync_group basics "${BASICS[@]}"
  sync_group themes "${THEMES[@]}"
  mv "$LOCKFILE.tmp" "$LOCKFILE"

  # Nvim does NOT generate helptags for manually installed packages.
  log "generating helptags"
  nvim --headless -c 'silent! helptags ALL' -c 'quit' 2>/dev/null && ok "helptags"

  if [[ "$TS_BRANCH" == "master" ]]; then
    log "compiling treesitter parsers (this is slow)"
    nvim --headless -c 'silent! TSUpdateSync' -c 'quit' 2>/dev/null \
      && ok "parsers" || warn "TSUpdateSync failed — run :TSUpdate inside nvim"
  else
    warn "treesitter on '$TS_BRANCH': install parsers with :TSInstall <lang> yourself"
  fi
}

# ------------------------------------------------------------------------ lsp
install_release() {
  local repo="$1" bin="$2" tmpl="$3" strip_v="$4"
  local ver asset url dest tmp

  ver="$(latest_tag "$repo")" || die "$bin: could not resolve latest tag"
  [[ -z "$ver" ]] && die "$bin: no tags found"
  [[ "$strip_v" == "yes" ]] && ver="${ver#v}"

  dest="$OPT_DIR/$bin"
  if [[ -f "$dest/.version" ]] && [[ "$(cat "$dest/.version")" == "$ver" ]]; then
    skip "$(printf '%-24s' "$bin") $ver (current)"
    return
  fi

  asset="${tmpl//\{ver\}/$ver}"; asset="${asset//\{os\}/$OS}"; asset="${asset//\{arch\}/$ARCH}"
  url="https://github.com/$repo/releases/download/$ver/$asset"

  tmp="$(mktemp -d)"

  if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/$asset" "$url"; then
    rm -rf "$tmp"; die "$bin: download failed — $url"
  fi

  rm -rf "$dest"; mkdir -p "$dest"
  case "$asset" in
    *.tar.gz|*.tgz) tar -xzf "$tmp/$asset" -C "$dest" ;;
    *.zip)          unzip -qo "$tmp/$asset" -d "$dest" ;;
    *)              install -m755 "$tmp/$asset" "$dest/$bin" ;;
  esac

  # some archives nest everything one level deep
  local inner
  inner="$(find "$dest" -maxdepth 1 -mindepth 1 -type d)"
  if [[ "$(find "$dest" -maxdepth 1 -mindepth 1 | wc -l)" -eq 1 ]] && [[ -d "$inner" ]]; then
    mv "$inner"/* "$inner"/.[!.]* "$dest/" 2>/dev/null || true
    rmdir "$inner" 2>/dev/null || true
  fi

  local real found
  found="$(find "$dest" -maxdepth 2 -type f -name "$bin")"
  real="$(printf '%s\n' "$found" | sed -n '1p')"
  [[ -z "$real" ]] && die "$bin: binary not found in extracted archive"
  chmod +x "$real"

  mkdir -p "$BIN_DIR"
  ln -sf "$real" "$BIN_DIR/$bin"
  echo "$ver" > "$dest/.version"
  rm -rf "$tmp"
  ok "$(printf '%-24s' "$bin") $ver"
}

do_lsp() {
  need curl; need git; need tar
  detect_platform
  log "lsp servers ($OS/$ARCH) -> $OPT_DIR, linked into $BIN_DIR"
  local entry repo bin tmpl strip_v
  for entry in "${LSP_RELEASES[@]}"; do
    IFS='|' read -r repo bin tmpl strip_v <<< "$entry"
    install_release "$repo" "$bin" "$tmpl" "$strip_v"
  done

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on \$PATH — nvim will not find these servers" ;;
  esac
}

# --------------------------------------------------------------------- status
do_status() {
  [[ -f "$LOCKFILE" ]] || die "no lockfile yet — run './nvim-bootstrap.sh plugins' first"
  awk -F'\t' '{ printf "%-38s %-12s %s\n", $1, $2, substr($3,1,10) }' "$LOCKFILE"
}

# ----------------------------------------------------------------------- main
case "${1:-all}" in
  all)     do_plugins; do_lsp ;;
  plugins) do_plugins ;;
  lsp)     do_lsp ;;
  status)  do_status ;;
  *)       die "usage: $0 [all|plugins|lsp|status]" ;;
esac

log "done"

# ---------------------------------------------------------------------- notes
#
# blink.cmp — pinned to a tag on purpose, two independent reasons:
#   1. Its prebuilt-binary downloader runs `git describe --tags --exact-match`.
#      Off a tag it refuses to download and silently degrades to the slower Lua
#      fuzzy matcher (default is `prefer_rust_with_warning`).
#   2. The default branch is now V2, which requires saghen/blink.lib as a
#      SEPARATE plugin and dropped the downloader entirely — V2 wants
#      `cargo build --release`. Cloning the default branch gets you neither.
#   Bump BLINK_TAG deliberately; re-run; it re-downloads the matching binary.
#
# frizbee — omitted. It is a plain Rust crate (no lua/, no plugin/, no doc/),
#   consumed by blink.cmp via Cargo.toml (`frizbee = "0.9.0"`) from crates.io at
#   build time. In pack/*/start/ it is inert. Delete the clone.
#
# nvim-treesitter — TS_BRANCH is explicit because upstream's default branch
#   flipped to `main` (the rewrite: nvim 0.11+, new API, no
#   `require('nvim-treesitter.configs').setup{}`, no :TSUpdateSync). `master` is
#   what almost every guide and most dependent plugins still assume.
#
# No checksum verification: LuaLS publishes no per-release digests, so the trust
#   anchor is GitHub's TLS cert plus the release signer. Stated, not hidden.

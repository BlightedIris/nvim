#!/usr/bin/env bash
# Bootstrap for Linux and macOS.
#
# This script does the smallest possible job: make sure git and a new enough
# Neovim exist, make sure the config is checked out, and then hand over to
# install/install.lua, which does the real work. Everything platform-specific
# beyond "which package manager" lives in the Lua, not here -- keeping two
# bootstrap scripts in sync is the thing worth avoiding.
#
# Usage:
#   ./install/install.sh [options]           # from a checkout
#   curl -fsSL <raw-url>/install/install.sh | bash
#
# Options are passed straight through to install.lua (--check, --tree,
# --dry-run, --all, --with=..., -y, ...).

set -euo pipefail

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/BlightedIris/nvim.git}"
NVIM_MIN="0.12.0"

# --- output ------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
	YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
	DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

step() { printf '%s▶ %s%s\n' "$CYAN" "$*" "$RESET"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$*" "$RESET"; }
die()  { printf '%s  ✗ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
dim()  { printf '%s  %s%s\n' "$DIM" "$*" "$RESET"; }

# --- platform ----------------------------------------------------------------

has() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [ "$(id -u)" -ne 0 ] && has sudo; then
	SUDO="sudo"
fi

detect_pm() {
	for candidate in brew pacman apt-get dnf zypper apk; do
		if has "$candidate"; then
			echo "$candidate"
			return
		fi
	done
	echo "none"
}

PM="$(detect_pm)"

pm_install() {
	case "$PM" in
		brew)    brew install "$@" ;;
		pacman)  $SUDO pacman -S --needed --noconfirm "$@" ;;
		apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y "$@" ;;
		dnf)     $SUDO dnf install -y "$@" ;;
		zypper)  $SUDO zypper --non-interactive install "$@" ;;
		apk)     $SUDO apk add "$@" ;;
		*)       return 1 ;;
	esac
}

# "0.12.5" >= "0.12.0"? Plain sort -V, which is everywhere these two run.
version_ge() {
	[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# --- 1. git ------------------------------------------------------------------

step "Checking for git"
if has git; then
	ok "git $(git --version | awk '{print $3}')"
else
	pm_install git || die "Could not install git; install it and re-run"
	ok "git installed"
fi

# curl or wget is needed by the Lua installer for downloads
if ! has curl && ! has wget; then
	step "Installing curl"
	pm_install curl || warn "Could not install curl; some downloads will fail"
fi

# --- 2. neovim ---------------------------------------------------------------

# Falls back to the official release tarball, because several distributions
# ship a Neovim far older than the 0.12 that nvim-treesitter (main) requires.
install_neovim_release() {
	local arch asset url dest tmp
	arch="$(uname -m)"
	case "$(uname -s)" in
		Darwin)
			case "$arch" in
				arm64) asset="nvim-macos-arm64.tar.gz" ;;
				*)     asset="nvim-macos-x86_64.tar.gz" ;;
			esac
			;;
		Linux)
			case "$arch" in
				aarch64|arm64) asset="nvim-linux-arm64.tar.gz" ;;
				*)             asset="nvim-linux-x86_64.tar.gz" ;;
			esac
			;;
		*) die "Unsupported system: $(uname -s)" ;;
	esac

	url="https://github.com/neovim/neovim/releases/latest/download/${asset}"
	dest="$HOME/.local/share/nvim-release"
	step "Downloading $asset"
	mkdir -p "$dest" "$HOME/.local/bin"
	tmp="$(mktemp -d)"
	if has curl; then
		curl -fL --progress-bar -o "$tmp/$asset" "$url"
	else
		wget -q --show-progress -O "$tmp/$asset" "$url"
	fi
	tar -xzf "$tmp/$asset" -C "$tmp"
	rm -rf "$dest"
	mv "$tmp"/nvim-* "$dest"
	ln -sf "$dest/bin/nvim" "$HOME/.local/bin/nvim"
	rm -rf "$tmp"
	export PATH="$HOME/.local/bin:$PATH"
	ok "Neovim installed to $dest"
	dim "Add ~/.local/bin to your PATH to keep it after this shell exits"
}

step "Checking for Neovim >= $NVIM_MIN"
NVIM_VERSION=""
if has nvim; then
	NVIM_VERSION="$(nvim --version | head -n1 | sed 's/^NVIM v//')"
fi

if [ -n "$NVIM_VERSION" ] && version_ge "$NVIM_VERSION" "$NVIM_MIN"; then
	ok "Neovim $NVIM_VERSION"
else
	if [ -n "$NVIM_VERSION" ]; then
		warn "Neovim $NVIM_VERSION is too old (nvim-treesitter needs $NVIM_MIN+)"
	fi
	# Homebrew and Arch track Neovim closely; elsewhere go straight to the
	# official release rather than installing a version we would reject.
	case "$PM" in
		brew|pacman)
			pm_install neovim || install_neovim_release
			;;
		*)
			install_neovim_release
			;;
	esac
	has nvim || die "Neovim still not on PATH"
	NVIM_VERSION="$(nvim --version | head -n1 | sed 's/^NVIM v//')"
	version_ge "$NVIM_VERSION" "$NVIM_MIN" || die "Neovim $NVIM_VERSION is still older than $NVIM_MIN"
	ok "Neovim $NVIM_VERSION"
fi

# --- 3. the config -----------------------------------------------------------

# Run from a checkout when there is one (the normal case), otherwise clone.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
CONFIG_ROOT=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../init.lua" ]; then
	CONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ -z "$CONFIG_ROOT" ]; then
	CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
	if [ -f "$CONFIG_ROOT/init.lua" ]; then
		step "Using existing config at $CONFIG_ROOT"
	else
		step "Cloning $REPO_URL into $CONFIG_ROOT"
		[ -e "$CONFIG_ROOT" ] && die "$CONFIG_ROOT exists but has no init.lua; move it aside first"
		git clone --recurse-submodules "$REPO_URL" "$CONFIG_ROOT"
		ok "Cloned"
	fi
fi

# --- 4. hand over ------------------------------------------------------------

step "Running the installer"
echo

# Piped in (`curl ... | bash`), stdin is the script itself, not the user.
# Reconnect it to the terminal so the installer can ask questions; where there
# is no terminal it falls back to the default answer for each prompt.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
	exec nvim -l "$CONFIG_ROOT/install/install.lua" "$@" </dev/tty
fi

exec nvim -l "$CONFIG_ROOT/install/install.lua" "$@"

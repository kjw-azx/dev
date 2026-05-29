#!/usr/bin/env bash
#
# Install AI agent configs into a dev container.
#
# Usage (curl-to-bash):
#   curl -fsSL https://raw.githubusercontent.com/kjw-azx/dev/main/install.sh | bash
#
# Overrides (env vars):
#   REPO_RAW   base raw URL to fetch files from (default: this repo @ main)
#   HOME       target home dir for the configs (default: current $HOME)
#
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/kjw-azx/dev/main}"

# source-in-repo path -> destination path (relative to $HOME)
install_file() {
  local src="$1" dest="$2"
  local target="${HOME}/${dest}"

  mkdir -p "$(dirname "$target")"

  if [ -f "$target" ]; then
    cp "$target" "${target}.bak"
    echo "backed up existing ${target} -> ${target}.bak"
  fi

  curl -fsSL "${REPO_RAW}/${src}" -o "$target"
  echo "installed ${target}"
}

echo "Installing AI agent configs into ${HOME} ..."
install_file "claude-settings.json" ".claude/settings.json"
install_file "codex-config.toml"    ".codex/config.toml"
echo "Done."

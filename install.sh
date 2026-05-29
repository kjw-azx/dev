#!/usr/bin/env bash
#
# Install AI agent configs + skills into a dev container.
#
# Usage (curl-to-bash):
#   curl -fsSL https://raw.githubusercontent.com/kjw-azx/dev/main/install.sh | bash
#
# Installs:
#   claude-settings.json -> ~/.claude/settings.json
#   codex-config.toml    -> ~/.codex/config.toml
#   skills/*             -> ~/.claude/skills/  AND  ~/.codex/skills/
#
# Overrides (env vars):
#   REPO   GitHub owner/repo to install from   (default: kjw-azx/dev)
#   REF    branch/tag/sha to install           (default: main)
#   HOME   target home dir for the configs     (default: current $HOME)
#
set -euo pipefail

REPO="${REPO:-kjw-azx/dev}"
REF="${REF:-main}"
TARBALL="https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz"

echo "Installing AI agent configs from ${REPO}@${REF} into ${HOME} ..."

# Fetch the repo once into a temp dir and work from there (lets us install
# whole directory trees like skills/, not just single files).
SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT
curl -fsSL "$TARBALL" | tar -xz -C "$SRC" --strip-components=1

# Copy a single file, backing up any existing target.
install_file() {
  local src="$1" dest="$2"
  local target="${HOME}/${dest}"

  mkdir -p "$(dirname "$target")"
  if [ -f "$target" ]; then
    cp "$target" "${target}.bak"
    echo "  backed up ${target} -> ${target}.bak"
  fi
  cp "${SRC}/${src}" "$target"
  echo "  installed ${target}"
}

# Merge the repo's skills/ into a destination skills dir, backing up any
# same-named skill that already exists.
install_skills() {
  local dest="$1"   # absolute path to a skills dir, e.g. ~/.claude/skills
  mkdir -p "$dest"
  local skill name target
  for skill in "${SRC}/skills/"*/; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    target="${dest}/${name}"
    if [ -e "$target" ]; then
      rm -rf "${target}.bak"
      mv "$target" "${target}.bak"
      echo "  backed up ${target} -> ${target}.bak"
    fi
    cp -R "$skill" "$target"
    echo "  installed ${target}"
  done
}

echo "Configs:"
install_file "claude-settings.json" ".claude/settings.json"
install_file "codex-config.toml"    ".codex/config.toml"

echo "Skills -> Claude:"
install_skills "${HOME}/.claude/skills"
echo "Skills -> Codex:"
install_skills "${HOME}/.codex/skills"

echo "Done."

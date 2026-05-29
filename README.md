# dev

Scripts for setting up AI agent configs in dev containers.

## Install

Run inside the container:

```bash
curl -fsSL https://raw.githubusercontent.com/kjw-azx/dev/main/install.sh | bash
```

This places:

| Source                 | Destination                                       |
| ---------------------- | ------------------------------------------------- |
| `claude-settings.json` | `~/.claude/settings.json`                         |
| `codex-config.toml`    | `~/.codex/config.toml`                            |
| `skills/*`             | `~/.claude/skills/` **and** `~/.codex/skills/`    |

Existing files and same-named skills are backed up to `*.bak` before being overwritten.

### Overrides

Set env vars before running to change behavior:

- `REPO` — GitHub `owner/repo` to install from (default: `kjw-azx/dev`)
- `REF` — branch/tag/sha to install (default: `main`)
- `HOME` — target home directory for the configs (default: current `$HOME`)

```bash
# Install from a different branch
curl -fsSL https://raw.githubusercontent.com/kjw-azx/dev/main/install.sh \
  | REF=some-branch bash
```

# dev

Scripts for setting up AI agent configs in dev containers.

## Install

Run inside the container:

```bash
curl -fsSL https://raw.githubusercontent.com/kjw-azx/dev/main/install.sh | bash
```

This places:

| Source                 | Destination               |
| ---------------------- | ------------------------- |
| `claude-settings.json` | `~/.claude/settings.json` |
| `codex-config.toml`    | `~/.codex/config.toml`    |

Existing files are backed up to `*.bak` before being overwritten.

### Overrides

Set env vars before running to change behavior:

- `REPO_RAW` — base raw URL to fetch from (default: this repo's `main` branch)
- `HOME` — target home directory for the configs (default: current `$HOME`)

```bash
# Install from a different branch
curl -fsSL https://raw.githubusercontent.com/kjw-azx/dev/main/install.sh \
  | REPO_RAW=https://raw.githubusercontent.com/kjw-azx/dev/some-branch bash
```

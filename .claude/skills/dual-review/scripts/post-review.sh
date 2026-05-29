#!/usr/bin/env bash
#
# Post a GitHub PR review payload as a DRAFT (pending) review.
#
# Usage:
#   post-review.sh <payload.json>
#
# The payload must NOT contain an "event" field — omitting it makes the review
# pending (a draft), visible only to the author until they submit it.
#
# Env overrides:
#   GITHUB_TOKEN_FILE   path to the token file (default: ~/.github-token)
#   PR_NUMBER           PR number (default: detected via `gh pr view`)
#
set -euo pipefail

PAYLOAD="${1:?usage: post-review.sh <payload.json>}"
[ -f "$PAYLOAD" ] || { echo "payload not found: $PAYLOAD" >&2; exit 1; }

TOKEN_FILE="${GITHUB_TOKEN_FILE:-$HOME/.github-token}"
if [ ! -f "$TOKEN_FILE" ]; then
  echo "no GitHub token at $TOKEN_FILE — not posting; payload left at $PAYLOAD" >&2
  exit 1
fi
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

# Safety: refuse to post if the payload would submit (not a draft).
if grep -Eq '"event"[[:space:]]*:' "$PAYLOAD"; then
  echo "payload contains an \"event\" field — that would submit, not draft. Remove it." >&2
  exit 1
fi

# Derive owner/repo from the origin remote (handles git@ and https URLs).
REMOTE_URL="$(git config --get remote.origin.url)"
SLUG="$(printf '%s' "$REMOTE_URL" | sed -E 's#^(git@|https?://)([^/:]+)[/:]##; s#\.git$##')"
OWNER="${SLUG%%/*}"
REPO="${SLUG##*/}"
[ -n "$OWNER" ] && [ -n "$REPO" ] || { echo "could not parse owner/repo from $REMOTE_URL" >&2; exit 1; }

PR="${PR_NUMBER:-$(gh pr view --json number -q .number)}"
[ -n "$PR" ] || { echo "could not determine PR number (set PR_NUMBER)" >&2; exit 1; }

echo "Posting draft review to ${OWNER}/${REPO} PR #${PR} ..." >&2

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${OWNER}/${REPO}/pulls/${PR}/reviews" \
  -d @"${PAYLOAD}"

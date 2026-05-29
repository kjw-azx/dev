---
name: dual-review
description: >-
  Runs a two-engine code review (Claude + Codex CLI) on the current branch's PR
  diff, combines and verifies the findings against the running app, drafts inline
  PR comments with line numbers, builds a GitHub review JSON payload, and
  optionally posts it as a draft review. Use when the user asks to review a PR,
  review the current branch, run a code review, double-check a diff before
  merging, or get review comments.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebFetch
---

# Dual code review

A two-engine review pipeline. Claude and the Codex CLI independently review the
**same diff**, their findings are merged and **verified against the running app**,
then turned into a GitHub **draft** review.

## Hard rule: always diff against the branch base, never raw `main`

Every diff in this skill is computed against the **merge base** of the current
branch and its base branch — i.e. only the changes this branch introduced, not
unrelated commits that landed on the base after the branch was cut. Compute the
base **once** in Step 0 and pass the exact command to both reviewers. Do not let
a subagent invent its own diff command.

## Working files

All artifacts are written to the repo root (gitignore them if needed):

- `review-claude.md` — Claude reviewer output
- `review-codex.md` — Codex reviewer output
- `review-combined.md` — merged + verified findings
- `review-payload.json` — GitHub review API payload

---

## Step 0 — Establish scope (run these yourself, first)

Resolve the base ref **entirely from local data — no network calls** (no
`gh`, no `git fetch`, no `git remote show`; a dev container may have no GitHub
access at all). `git merge-base` and the diff commands all operate on the local
object store.

```bash
# 1) If the user named a base branch, honor it; else use $REVIEW_BASE if set.
BASE="${REVIEW_BASE:-}"

# 2) Else use the remote's default branch as recorded locally at clone time.
#    (refs/remotes/origin/HEAD is a local symref — reading it hits no network.)
[ -z "$BASE" ] && BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"

# 3) Else fall back to the first base ref that actually exists locally.
if [ -z "$BASE" ]; then
  for cand in origin/main origin/master main master develop trunk; do
    if git rev-parse --verify --quiet "$cand" >/dev/null; then BASE="$cand"; break; fi
  done
fi
[ -n "$BASE" ] || { echo "could not determine a base ref locally; set REVIEW_BASE" >&2; exit 1; }

HEAD_SHA=$(git rev-parse HEAD)
MERGE_BASE=$(git merge-base "$BASE" HEAD)   # purely local

echo "Base ref   : $BASE"
echo "Merge base : $MERGE_BASE"
echo "Head SHA   : $HEAD_SHA"
```

`$BASE` is a full ref (e.g. `origin/main` or `main`) — use it verbatim, do **not**
prefix it with `origin/` again. If `origin/HEAD` is unset and the fallback picks
the wrong branch, the user can pin it without any network via
`git remote set-head origin <branch>` or by passing `REVIEW_BASE`.

The **canonical diff command** every reviewer must use:

```bash
git diff --merge-base "$BASE" HEAD
```

(equivalently `git diff "$BASE"...HEAD` — three dots — which also diffs from the
merge base). Get the changed-file list and per-file diffs with the same base:

```bash
git diff --merge-base "$BASE" HEAD --name-only        # files in scope
git diff --merge-base "$BASE" HEAD -- <path>          # one file's diff
```

Note the resolved values of `$BASE`, `$MERGE_BASE`, and `$HEAD_SHA` — you will
substitute them literally into the subagent prompts and the payload.

---

## Step 1 — Dispatch both reviewers in parallel

Both reviewers run as **blocking shell commands**, so this skill works whether
the orchestrator is Claude or Codex — neither half depends on a host-specific
agent tool. Issue **both** commands so they run concurrently (run them in the
background and `wait`, or issue both in a single message if your host runs Bash
calls in parallel). Both are blocking, so when both return you know both reviews
are complete — that is the completion signal, no polling needed.

### 1a. Claude reviewer — Claude Code CLI (blocking)

Run Claude Code headlessly with `claude -p`. It writes its own file:

```bash
claude -p "Review ONLY the changes this branch introduced. Use exactly this \
command to view the diff, do not diff against anything else: \
git diff --merge-base $BASE HEAD  (file list: same command with --name-only). \
Review for correctness bugs, security issues, broken edge cases, and regressions. \
For each finding give: file path, the line number on the NEW/right side of the \
diff, severity, explanation, and a suggested fix. Only flag lines present in the \
diff. Write your findings as Markdown to review-claude.md in the repo root." \
  --permission-mode bypassPermissions
```

(In the dev container `claude` already defaults to bypass permissions via
`~/.claude/settings.json`; the explicit flag keeps it working elsewhere. If
`claude` is unavailable or errors, capture stderr, tell the user the Claude half
was skipped, and continue with the Codex findings only — do not abort.)

### 1b. Codex reviewer — Codex CLI (blocking)

Run the Codex CLI non-interactively. It writes its own file:

```bash
codex exec "Review ONLY the changes this branch introduced. Use exactly this \
command to view the diff, do not diff against anything else: \
git diff --merge-base $BASE HEAD  (file list: same command with --name-only). \
Review for correctness bugs, security issues, broken edge cases, and regressions. \
For each finding give: file path, the line number on the NEW/right side of the \
diff, severity, explanation, and a suggested fix. Only flag lines present in the \
diff. Write your findings as Markdown to review-codex.md in the repo root."
```

If `codex exec` is unavailable or errors, capture stderr, tell the user the Codex
half was skipped, and continue with the Claude findings only — do not abort.

### Running both at once

To run the two reviewers concurrently from a single shell, background them and
`wait`:

```bash
claude -p "<claude prompt above>" --permission-mode bypassPermissions &
codex exec "<codex prompt above>" &
wait
```

After both return, confirm `review-claude.md` and `review-codex.md` exist and are
non-empty before continuing.

---

## Step 2 — Combine and verify

1. Read both files. Merge into one finding list; **deduplicate** items that point
   at the same file+line/issue (note when both engines agreed — that raises
   confidence).
2. **Verify each finding** — do not trust them blind. The app is likely running:
   - For backend/API findings, exercise the relevant endpoint (`curl`, or a quick
     script) to confirm the bug reproduces.
   - For UI findings, if a **Playwright MCP server is connected**, drive the app
     to reproduce; otherwise reason from the code and say it's unverified.
   - For pure logic, trace the code path or write a tiny throwaway check.
   Mark each finding **confirmed**, **rejected**, or **unverified**, with a one-line
   note on how you checked.
3. Drop rejected findings. Write the survivors to `review-combined.md`, grouped by
   severity, each with file, new-side line number, verification status, and fix.

---

## Step 3 — Draft inline PR comments

For each confirmed/unverified finding, prepare a GitHub review comment. **Every
comment must land on a line that is part of the diff under review** — re-check
against `git diff --merge-base "$BASE" HEAD -- <path>` and confirm the line
appears as an added (`+`) or context line in a hunk on the right side. If a finding
is real but its line isn't in the diff, fold it into the review **body** instead of
making it an inline comment (the API rejects comments outside the diff).

Comment fields: `path`, `line` (new-side line number), `side: "RIGHT"`, `body`.
For a multi-line range add `start_line` + `start_side: "RIGHT"`.

See [reference.md](reference.md) for the full payload schema and multi-line rules.

---

## Step 4 — Build the review payload

Write `review-payload.json`. **Omit `event`** so the review is created as a
**draft (PENDING)** — visible only to the author until they submit it:

```json
{
  "commit_id": "<HEAD_SHA>",
  "body": "## Dual review (Claude + Codex)\n\n<summary, plus any findings that couldn't be inline>",
  "comments": [
    { "path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "**[high]** ..." }
  ]
}
```

Substitute the real `HEAD_SHA` from Step 0. Show the user the payload and the
summary before posting.

---

## Step 5 — Post as a draft review (only if a token exists)

Check for `~/.github-token`. If it is **absent**, stop here: leave
`review-payload.json` on disk and tell the user how to post it themselves.

If it is **present**, post with the bundled helper, which derives owner/repo and
PR number automatically and POSTs the payload (no `event` ⇒ pending/draft):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/post-review.sh" review-payload.json
```

Report back the review `id`/`html_url` from the response and confirm it was
created as a **PENDING** (draft) review. Remind the user it is not visible to
others until they submit it from the PR's "Files changed" tab.

Overrides the helper honors: `GITHUB_TOKEN_FILE`, `PR_NUMBER`.

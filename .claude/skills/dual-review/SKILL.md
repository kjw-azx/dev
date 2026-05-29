---
name: dual-review
description: >-
  Runs a two-engine code review (Claude + Codex CLI) on the current branch's PR
  diff, combines and verifies the findings against the running app, drafts inline
  PR comments with line numbers, builds a GitHub review JSON payload, and
  optionally posts it as a draft review. Use when the user asks to review a PR,
  review the current branch, run a code review, double-check a diff before
  merging, or get review comments.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, WebFetch
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

```bash
# Base branch: the PR target if there's a PR, else the remote's default branch.
BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null || true)
if [ -z "$BASE" ]; then
  BASE=$(git remote show origin | sed -n 's/.*HEAD branch: //p')
fi
git fetch origin "$BASE" --quiet

HEAD_SHA=$(git rev-parse HEAD)
MERGE_BASE=$(git merge-base "origin/$BASE" HEAD)

echo "Base branch : $BASE"
echo "Merge base  : $MERGE_BASE"
echo "Head SHA    : $HEAD_SHA"
```

The **canonical diff command** every reviewer must use:

```bash
git diff --merge-base "origin/$BASE" HEAD
```

(equivalently `git diff origin/$BASE...HEAD` — three dots — which also diffs from
the merge base). Get the changed-file list and per-file diffs with the same base:

```bash
git diff --merge-base "origin/$BASE" HEAD --name-only        # files in scope
git diff --merge-base "origin/$BASE" HEAD -- <path>          # one file's diff
```

Note the values of `$BASE`, `$MERGE_BASE`, and `$HEAD_SHA` — you will substitute
them literally into the subagent prompts and the payload.

---

## Step 1 — Dispatch both reviewers in parallel

Issue **both** of the following in a **single message** so they run concurrently.
Both calls are blocking, so when both return you know both reviews are complete —
that is the completion signal (no polling needed). The Codex call runs
synchronously via `codex exec`, so it finishes when the Bash call returns.

### 1a. Claude reviewer — `Agent` tool

Spawn a `general-purpose` agent with a prompt like:

> You are reviewing only the changes this branch introduced. Use **exactly** this
> command to see the diff and do not diff against anything else:
> `git diff --merge-base "origin/<BASE>" HEAD` (changed files:
> `git diff --merge-base "origin/<BASE>" HEAD --name-only`).
>
> Review for correctness bugs, security issues, broken edge cases, and clear
> regressions. For each finding record: file path, the **line number in the new
> version of the file** (the right/added side), severity, a concise explanation,
> and a suggested fix. Only flag lines that appear in the diff.
>
> Write your findings as Markdown to `review-claude.md` and nothing else to it.

Substitute the real base branch for `<BASE>`.

### 1b. Codex reviewer — `Bash` tool (blocking)

Run the Codex CLI non-interactively. It writes its own file:

```bash
codex exec "Review ONLY the changes this branch introduced. Use exactly this \
command to view the diff, do not diff against anything else: \
git diff --merge-base origin/$BASE HEAD  (file list: same command with --name-only). \
Review for correctness bugs, security issues, broken edge cases, and regressions. \
For each finding give: file path, the line number on the NEW/right side of the \
diff, severity, explanation, and a suggested fix. Only flag lines present in the \
diff. Write your findings as Markdown to review-codex.md in the repo root."
```

If `codex exec` is unavailable or errors, capture stderr, tell the user the Codex
half was skipped, and continue with the Claude findings only — do not abort.

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
against `git diff --merge-base "origin/$BASE" HEAD -- <path>` and confirm the line
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

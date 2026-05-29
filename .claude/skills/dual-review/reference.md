# GitHub review payload reference

Endpoint used to create the review:

```
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

## Draft vs. submitted

The `event` field controls state:

| `event` value      | Result                                                      |
| ------------------ | ----------------------------------------------------------- |
| *(omitted)* / none | **PENDING** — a draft, visible only to the author           |
| `COMMENT`          | Submitted as a comment review                               |
| `APPROVE`          | Submitted as an approval                                    |
| `REQUEST_CHANGES`  | Submitted requesting changes                                |

This skill **omits `event`** so the review is always a draft. The author submits
it later from the PR's "Files changed" → "Finish your review" UI.

## Top-level fields

```jsonc
{
  "commit_id": "<full HEAD sha>",   // recommended: pins comments to this commit
  "body": "overall review text",     // markdown; also the home for non-inline findings
  "comments": [ /* inline comments, see below */ ]
}
```

## Inline comment object

Use the **line-based** form (not the legacy `position` form):

```jsonc
{
  "path": "src/server/handler.ts",  // repo-relative path
  "line": 128,                        // line number in the NEW version of the file
  "side": "RIGHT",                    // RIGHT = added/context line; LEFT = deleted line
  "body": "**[high]** Off-by-one: ..."
}
```

Multi-line comment (a range):

```jsonc
{
  "path": "src/server/handler.ts",
  "start_line": 120,
  "start_side": "RIGHT",
  "line": 128,            // end line; must be >= start_line
  "side": "RIGHT",
  "body": "This whole block ..."
}
```

## Constraints that cause API errors

- A comment's `line` **must be part of the diff** for that file in this PR. Lines
  outside any hunk are rejected → put those findings in the top-level `body`.
- `side: "RIGHT"` refers to the head/new file; `"LEFT"` to the base/old file. Most
  findings are on `RIGHT`.
- `line` is a **file line number**, not a diff position.
- Keep `commit_id` equal to the current HEAD that was reviewed, or omit it to
  default to the PR's latest commit.

## Verifying a line is in the diff

```bash
git diff --merge-base "origin/$BASE" HEAD -- <path>
```

Only `+` (added) and unprefixed (context) lines on the right side are valid
targets for a `RIGHT` comment. Count line numbers from the `@@ ... +start,count @@`
hunk headers.

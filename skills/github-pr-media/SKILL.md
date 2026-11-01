---
name: github-pr-media
description: Attach genuine UI screenshots to a GitHub pull request as native GitHub media without polluting the Git repository. Use when a change affects visible UI and the PR needs Before/After evidence, when a reviewer asks "where's the screenshot", or when an agent must publish proof of a UI fix. Covers environment checks (gh >= 2.99.0), capture into a temp dir outside the repo, `gh pr create/edit/comment --attach`, size and format limits, and how to triage partial vs total upload failure.
---

# GitHub PR Media

Goal: **the reviewer sees the real UI, the repository stays clean.**

## Hard rules

1. **Never commit screenshots.** Capture into `$TMPDIR`, never into the working tree.
   A screenshot that sits in the repo "just for the PR" ends up in history.
2. **Never fabricate a Before image.** If the pre-change state is not actually
   available, drop the Before section and say so in the PR. An invented comparison
   is worse than no comparison.
3. **Never claim verification you did not perform.** If you could not run the build
   or the simulator, write that limitation down.
4. **Check the environment before composing commands.** `--attach` only exists in
   `gh` >= 2.99.0. On older builds you get `unknown flag: --attach`.

## Step 0 — environment

```bash
gh --version                                  # need >= 2.99.0
gh auth status
gh repo view --json viewerPermission --jq .viewerPermission   # need WRITE or better
```

Non-obvious facts that cost real debugging time:

- `read` and `triage` permissions do **not** produce 403 — the upload endpoint
  answers **404**, which looks exactly like "repository not found".
- GitHub Enterprise Server is refused outright (`attaching files is not supported
  on GitHub Enterprise Server`). `ghe.com` data-residency tenants are fine.
- OAuth from `gh auth login` or a classic PAT works. Do not assume
  `GITHUB_TOKEN` in Actions, or a fine-grained PAT, can upload.
- Do not test the flag with `gh pr create --help | grep -q -- '--attach'`.
  `grep -q` exits early, gh takes SIGPIPE, and `set -o pipefail` then reports
  failure on a perfectly good build. Use `grep -c`, or check `$?` of the pipeline
  without `-q`.

## Step 1 — capture, outside the repo

```bash
ASSET_DIR="$(mktemp -d "${TMPDIR%/}/pr-media.XXXXXX")"

xcrun simctl io booted screenshot "$ASSET_DIR/after.png"   # iOS Simulator
screencapture -i "$ASSET_DIR/after.png"                    # macOS, interactive
```

Sanity-check each file before uploading: `stat -f%z "$file"`, and actually look at
the image. A blank or wrong-screen screenshot is worse than none.

## Step 2 — write the body with local paths

```markdown
## UI 截图

### Before（修改前）
![修改前的设置页面](./before.png)

### After（修改后）
![修改后的设置页面](./after.png)
```

Path resolution: **relative to the body file's directory, falling back to the
current working directory.** A typo can therefore silently match a different
same-named file instead of erroring.

## Step 3 — publish

Create:

```bash
gh pr create --base main --title "$TITLE" \
  --body-file "$ASSET_DIR/pr-body.md" \
  --attach "$ASSET_DIR/before.png" \
  --attach "$ASSET_DIR/after.png"
```

Update an existing body at a specific position:

```bash
gh pr view 123 --json body --jq .body > "$ASSET_DIR/current.md"
# edit current.md, then:
gh pr edit 123 --body-file "$ASSET_DIR/current.md" --attach "$ASSET_DIR/after.png"
```

Append without touching the body (round-N verification):

```bash
gh pr comment 123 --body "Round 2: tightened button spacing." \
  --attach "$ASSET_DIR/after.png#Round 2 verification"
```

## Step 4 — triage a nonzero exit before retrying

Uploads happen **before** the PR is created.

| Result | PR exists? | What to do |
| --- | --- | --- |
| Error contains `no pull request was created` | **No** | Every upload failed. Fix and re-run `gh pr create`; no duplicate risk. |
| Error, but a PR URL was printed to stdout | Yes | Partial failure. `gh pr comment --attach` the missing files. Do **not** create again. |
| Permission / GHES error | **No** | Raised while building the uploader, before any creation. Nothing to clean up. |

Then verify: `gh pr view --json body --jq .body` shows hosted URLs, `git status`
is clean, and the images actually render in a browser. Note that for private
repos the attachment URLs require auth, so `curl` is not a valid liveness check.

## Limits

| Type | Limit | Notes |
| --- | --- | --- |
| Files per command | 50 | `--attach` is repeatable, but the same file cannot be attached twice |
| Images / GIF | 10 MB | png, jpg, jpeg, gif, svg (+ webp accepted by the CLI, see below) |
| Video | 100 MB CLI | server enforces 10 MB on free plans, 100 MB on paid |
| Alt text | `--attach 'path#alt'` | applies only to **appended** files; a reference already in the body keeps its own Markdown alt |

- Video: reference it as `![](video.mp4)` with the reference as the **only**
  content of its paragraph, or it degrades into a link. H.264 for compatibility.
- WebP is accepted by the gh client, but GitHub's documented image list covers
  only PNG/GIF/JPEG/SVG. Test one WebP before batching.
- `--attach` cannot be combined with `gh pr create --web` or `--dry-run`.

## Closing checklist

- [ ] Screenshots came from a real build, and I looked at them
- [ ] No secrets, tokens, account names, or real user data visible
- [ ] Every file within limits
- [ ] PR body references the final images; stale ones removed, not stacked
- [ ] `git status --short` shows no media files
- [ ] Rendered PR checked in a browser

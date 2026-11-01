# github-pr-media-guide

Attach **Before/After UI screenshots** to a GitHub pull request as native GitHub
media — the reviewer sees the real UI, and nothing extra lands in your Git history.

This repo is the practical version, not the documentation paraphrase. Every
non-obvious claim here was checked against `cli/cli` **v2.103.3** source and the
GitHub docs on 2026-11-01, and the two scripts are tested. The evidence table at
the end of the guide maps each claim to the exact source file.

## Why not just commit the screenshots?

Because they are review artifacts, not source. Once they are committed you pay for
them twice: repository size forever, and a history that every future clone carries.
GitHub's native attachments give you a permanent, permission-scoped URL with zero
impact on the repository.

## Quick start

```bash
# 0. environment (30 seconds, do not skip)
gh --version                     # need >= 2.99.0
./scripts/pr-check-env.sh owner/repo

# 1. capture, outside the repository
ASSET_DIR="$(mktemp -d "${TMPDIR%/}/pr-media.XXXXXX")"
screencapture -i "$ASSET_DIR/after.png"

# 2. write the body with local paths, then publish
cp templates/pr-body.md "$ASSET_DIR/pr-body.md"

gh pr create --base main --title "feat: ..." \
  --body-file "$ASSET_DIR/pr-body.md" \
  --attach "$ASSET_DIR/before.png" \
  --attach "$ASSET_DIR/after.png"
```

## What's in here

| Path | What it is |
| --- | --- |
| [`docs/PR-MEDIA-GUIDE.zh-CN.md`](docs/PR-MEDIA-GUIDE.zh-CN.md) | The full guide (Chinese). Workflow, failure triage, limits, FAQ. |
| [`skills/github-pr-media/SKILL.md`](skills/github-pr-media/SKILL.md) | Drop-in skill/rule file for coding agents (Claude Code, Codex, WorkBuddy, …). |
| [`scripts/pr-check-env.sh`](scripts/pr-check-env.sh) | Verifies gh version, `--attach` availability, auth, and target-repo write access. |
| [`scripts/pr-media-comment.sh`](scripts/pr-media-comment.sh) | Adds one comment with N attachments to an existing PR, leaving the body alone. |
| [`templates/pr-body.md`](templates/pr-body.md) | PR body template with Before/After sections (Chinese). |
| [`templates/pr-body.en.md`](templates/pr-body.en.md) | Same, in English. |

## The four things that actually bite

1. **`gh` too old.** `--attach` shipped in **v2.99.0** (2026-09-01). On anything
   older you get `unknown flag: --attach`, and people then spend an hour debugging
   permissions instead of running `brew upgrade gh`.

2. **A nonzero exit does not mean "no PR".** Uploads run *before* creation, so:
   all uploads failed → **no PR exists**; some failed → **the PR exists**, the URL
   was printed to stdout, exit code was still nonzero. Retrying `gh pr create`
   blindly is how you get duplicate PRs.

3. **Insufficient permission looks like a 404.** The upload endpoint returns 404
   for `read` and `triage`, not 403. "Repository not found" usually means "get
   write access".

4. **`gh ... --help | grep -q -- '--attach'` lies.** `grep -q` exits on the first
   match, `gh` takes SIGPIPE, and with `set -o pipefail` the pipeline reports
   failure on a working binary. Use `grep -c`. (We hit this while writing v1.1 of
   the guide; the check script now avoids it.)

## Install the skill

```bash
# Claude Code / WorkBuddy style skill directory
cp -R skills/github-pr-media ~/.workbuddy/skills/
```

Or paste the "Pull Request UI Media Policy" section of the guide into your
`AGENTS.md` / `CLAUDE.md`, if you would rather keep it as plain rules.

## Verified facts, briefly

| Claim | Source of truth |
| --- | --- |
| 50 files per command | `internal/attachments/flags.go` — `maxAttachments = 50` |
| Images 10 MB, video 100 MB (client) | `internal/attachments/userasset.go` — `maxImageBytes`, `maxVideoBytes` |
| Video 10 MB free / 100 MB paid (server) | GitHub Docs — Attaching files |
| `ADMIN`/`MAINTAIN`/`WRITE` only; others 404 | `internal/attachments/client.go` — `uploadPermissions` |
| GHES refused client-side | `internal/attachments/client.go` — `checkHost` |
| `--attach` × `--web` / `--dry-run` rejected | `pkg/cmd/pr/create/create.go` — `MutuallyExclusive` |
| Total failure → no PR created | `pkg/cmd/pr/create/create.go` — `submitPR`, `uploaded == 0` branch |
| body-file paths relative to its dir, fallback cwd | `gh pr create --help` |

## Requirements

- GitHub.com (not GHES)
- macOS for the capture snippets (`screencapture`, `sips`, `simctl`); the upload
  commands are platform-independent, and both scripts handle GNU `stat` too.

## License

MIT — see [LICENSE](LICENSE).

# github-pr-media-guide

Attach **Before/After UI screenshots** to a GitHub pull request as native GitHub
media — the reviewer sees the real UI, and nothing extra lands in your Git history.

> Every non-obvious claim here was checked against `cli/cli` **v2.103.3** source and
> the GitHub docs on 2026-11-01; both scripts are tested. The evidence table is at
> the end of the guide.

[中文](README.md) · [Full guide (Chinese)](docs/PR-MEDIA-GUIDE.zh-CN.md) · [Agent skill](skills/github-pr-media/SKILL.md)

## Requirements

1. `gh` ≥ **2.99.0** (`--attach` shipped in this version, 2026-09-01)
2. **write / maintain / admin** on the target repository (`read` and `triage` fail —
   and they fail with a **404**, not a 403)
3. GitHub.com (GitHub Enterprise Server is refused; `ghe.com` data-residency tenants work)

## Five minutes, start to finish

```bash
# 1. Put the guide anywhere. It is read-only reference, not a git project you work in.
git clone https://github.com/GetSayAll/github-pr-media-guide ~/Tools/github-pr-media-guide
GUIDE="$HOME/Tools/github-pr-media-guide"

# 2. Go to the project you are actually sending a PR to, and check the environment
cd /path/to/your-project
"$GUIDE/scripts/pr-check-env.sh"

# 3. Capture outside the repository
ASSET_DIR="$(mktemp -d "${TMPDIR%/}/pr-media.XXXXXX")"
xcrun simctl io booted screenshot "$ASSET_DIR/after.png"   # simulator
# screencapture -i "$ASSET_DIR/after.png"                   # macOS, interactive

# 4. Copy the template and edit it
cp "$GUIDE/templates/pr-body.en.md" "$ASSET_DIR/pr-body.md"

# 5. Publish — still in the same project directory
gh pr create --base main --title "feat: rework settings layout" \
  --body-file "$ASSET_DIR/pr-body.md" \
  --attach "$ASSET_DIR/before.png" \
  --attach "$ASSET_DIR/after.png"
```

**One working directory throughout.** After `cd` into your project, always call the
guide's scripts by absolute path (`"$GUIDE/..."`).

> Why this is spelled out: running `./scripts/pr-check-env.sh` inside the guide clone
> checks **the guide repo itself** — you are its owner, so everything is green, and
> your actual PR target was never tested. The v1.1 script now warns about exactly this.

## Pick your path

| You want to… | Go to |
| --- | --- |
| Check whether this machine can do it at all | run `"$GUIDE/scripts/pr-check-env.sh"` |
| Add Before/After by hand | [guide §3](docs/PR-MEDIA-GUIDE.zh-CN.md) |
| Add images to an existing PR | [guide §4](docs/PR-MEDIA-GUIDE.zh-CN.md) or `scripts/pr-media-comment.sh` |
| Have a coding agent do it | install the skill, below |
| Debug a failure or a nonzero exit | [guide §8](docs/PR-MEDIA-GUIDE.zh-CN.md) |

## Install the skill

[`skills/github-pr-media/SKILL.md`](skills/github-pr-media/SKILL.md) is a rule file for coding
agents. **No project-private content, and no `AGENTS.md` edits** — install it into the user-level
directory once and every project picks it up.

```bash
"$GUIDE/scripts/install-skill.sh" --dry-run   # see where it would land
"$GUIDE/scripts/install-skill.sh"             # do it
```

The script detects which agents actually exist on this machine and writes only to those:

| Tool | Detected by | Target |
| --- | --- | --- |
| WorkBuddy | `/Applications/WorkBuddy.app` | `~/.workbuddy/skills/github-pr-media/` |
| Claude Code | `claude` on `PATH` | `~/.claude/skills/github-pr-media/` |
| Codex | `codex` on `PATH` | `~/.codex/skills/github-pr-media/` |

> **A config directory alone is not proof of installation.** Uninstalling a CLI usually leaves
> `~/.claude` behind, so "directory exists, tool gone" is labelled `looks uninstalled` and
> skipped — otherwise you believe it is installed when it is not. Every write is sha256-verified.

Once installed, the agent handles it end to end: capture to a temp dir → write Markdown with local
paths → `gh --attach` → triage the failure type before retrying → verify the rendered PR and
`git status`.

### Updating it

Edit `skills/github-pr-media/SKILL.md` in this repo → commit → re-run `install-skill.sh`.
Never edit the copies under `~/.<tool>/skills`; they are artifacts and the next sync overwrites them.

Full details (detection rules, `--force` / `--target`, manual sync, uninstall) —
[installation guide (Chinese)](docs/INSTALL-SKILL.zh-CN.md).

## Repo layout

| Path | What it is |
| --- | --- |
| [`docs/PR-MEDIA-GUIDE.zh-CN.md`](docs/PR-MEDIA-GUIDE.zh-CN.md) | Full guide (Chinese): workflow, failure triage, limits, FAQ, evidence appendix |
| [`docs/INSTALL-SKILL.zh-CN.md`](docs/INSTALL-SKILL.zh-CN.md) | Installing, updating, syncing and removing the skill |
| [`skills/github-pr-media/SKILL.md`](skills/github-pr-media/SKILL.md) | Loadable agent rule file |
| [`scripts/install-skill.sh`](scripts/install-skill.sh) | Detects installed agents, syncs the skill, verifies sha256 |
| [`scripts/pr-check-env.sh`](scripts/pr-check-env.sh) | Checks gh version, `--attach`, auth, and target-repo write access |
| [`scripts/pr-media-comment.sh`](scripts/pr-media-comment.sh) | One comment with N attachments on an existing PR, body untouched |
| [`templates/pr-body.md`](templates/pr-body.md) · [`.en.md`](templates/pr-body.en.md) | PR templates with Before/After sections |

## The four traps that actually bite

1. **`gh` too old.** `--attach` needs **v2.99.0**. Older builds answer
   `unknown flag: --attach`, and people then spend an hour debugging permissions
   instead of running `brew upgrade gh`.

2. **A nonzero exit does not mean "no PR".** Uploads run *before* creation:
   all failed → **no PR exists** (error says `no pull request was created`);
   some failed → **the PR exists**, URL printed to stdout, exit code still nonzero.
   Re-running `gh pr create` blindly is how you get duplicate PRs.

3. **Insufficient permission looks like a 404.** The endpoint returns 404 for `read`
   and `triage`. "Repository not found" usually means "get write access".

4. **`gh ... --help | grep -q -- '--attach'` lies.** `grep -q` exits on the first match,
   `gh` takes SIGPIPE, and with `set -o pipefail` a working binary reports failure.
   Use `grep -c`. (We hit this while writing v1.1; the check script avoids it.)

## Verified facts

| Claim | Source of truth |
| --- | --- |
| 50 files per command | `internal/attachments/flags.go` — `maxAttachments = 50` |
| Images 10 MB, video 100 MB (client) | `internal/attachments/userasset.go` |
| Video 10 MB free / 100 MB paid (server) | GitHub Docs — Attaching files |
| Only `ADMIN`/`MAINTAIN`/`WRITE`; others 404 | `internal/attachments/client.go` |
| GHES refused client-side | `internal/attachments/client.go` — `checkHost` |
| `--attach` × `--web` / `--dry-run` rejected | `pkg/cmd/pr/create/create.go` |
| Total failure → no PR created | `pkg/cmd/pr/create/create.go` — `submitPR` |

## License

MIT — see [LICENSE](LICENSE).

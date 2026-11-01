#!/usr/bin/env bash
# Fail-fast environment check for GitHub PR media attachments.
#
#   ./pr-check-env.sh [owner/repo]
#
# Exit codes: 0 ok · 1 gh missing/too old · 2 not authenticated · 3 no write access
set -uo pipefail

MIN_MAJOR=2
MIN_MINOR=99

info()  { printf '  %s\n' "$*"; }
ok()    { printf '  [OK]   %s\n' "$*"; }
bad()   { printf '  [FAIL] %s\n' "$*"; }
warn()  { printf '  [WARN] %s\n' "$*"; }

printf 'GitHub PR media environment check\n'
printf '================================\n'

# --- 1. gh present ---------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  bad 'gh (GitHub CLI) is not installed.'
  info 'Install it with: brew install gh'
  exit 1
fi
ok "gh found: $(command -v gh)"

# --- 2. version -----------------------------------------------------------
raw="$(gh --version 2>/dev/null | sed -n '1p')"
# "gh version 2.103.3 (2026-10-26)"
ver="$(printf '%s' "$raw" | sed -n 's/.*version \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
if [ -z "$ver" ]; then
  warn "could not parse version from: $raw"
else
  major="${ver%%.*}"
  rest="${ver#*.}"
  minor="${rest%%.*}"
  if [ "$major" -gt "$MIN_MAJOR" ] \
     || { [ "$major" -eq "$MIN_MAJOR" ] && [ "$minor" -ge "$MIN_MINOR" ]; }; then
    ok "version $ver (>= ${MIN_MAJOR}.${MIN_MINOR}.0)"
  else
    bad "version $ver is too old; --attach needs >= ${MIN_MAJOR}.${MIN_MINOR}.0 (released 2026-09-01)"
    info 'Upgrade with: brew upgrade gh'
    exit 1
  fi
fi

# --- 3. --attach actually exposed on each command -------------------------
# Do NOT pipe into `grep -q` here: it exits early, gh gets SIGPIPE, and with
# `set -o pipefail` a perfectly good build reports 141. Capture first.
missing=0
for cmd in create edit comment; do
  help_text="$(gh pr "$cmd" --help 2>/dev/null || true)"
  case "$help_text" in
    *--attach*)
      ok "gh pr $cmd: --attach available"
      ;;
    *)
      bad "gh pr $cmd: --attach missing"
      missing=1
      ;;
  esac
done
[ "$missing" -eq 0 ] || { info 'Your build advertises a supported version but lacks the flag; reinstall gh.'; exit 1; }

# --- 4. authentication ----------------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  bad 'not authenticated. Run: gh auth login --web'
  exit 2
fi
acct="$(gh auth status 2>&1 | sed -n 's/.*account \([^ ]*\).*/\1/p' | sed -n '1p')"
ok "authenticated${acct:+ as $acct}"

# --- 5. target repository write access ------------------------------------
repo="${1:-}"
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  if [ -z "$repo" ]; then
    warn 'no repo argument and not inside a GitHub repository; skipping permission check'
    info "Re-run inside a repo, or pass owner/repo explicitly."
    exit 0
  fi
  info "resolved repository from cwd: $repo"
  # Running this inside the guide clone is the most common false alarm: every
  # check passes because you own this repo, but your PR target is elsewhere.
  case "$repo" in
    */github-pr-media-guide)
      warn 'that is this guide repo, not the project you want to send a PR to'
      info 'Run this from your project directory, or pass owner/repo explicitly:'
      info '  ./scripts/pr-check-env.sh your-org/your-repo'
      ;;
    *)
      info 'if this is not your PR target, pass owner/repo or cd to that project first'
      ;;
  esac
fi

perm="$(gh repo view "$repo" --json viewerPermission --jq .viewerPermission 2>/dev/null || true)"
if [ -z "$perm" ]; then
  bad "cannot read $repo (wrong name, or no access at all)"
  exit 3
fi
case "$perm" in
  ADMIN|MAINTAIN|WRITE)
    ok "$repo permission: $perm (can attach)"
    ;;
  READ|TRIAGE)
    # The upload endpoint answers 404 for these, which reads like "repo not found".
    bad "$repo permission: $perm — uploads will fail with 404, not 403"
    info 'Ask for write access, or push from a branch/fork that gets it.'
    exit 3
    ;;
  *)
    warn "$repo permission: ${perm:-unknown} (unexpected value; probing not possible here)"
    ;;
esac

printf '\nEnvironment OK. Next: docs/PR-MEDIA-GUIDE.zh-CN.md -> step 3\n'

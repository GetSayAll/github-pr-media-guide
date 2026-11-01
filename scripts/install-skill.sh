#!/usr/bin/env bash
# Install or update the github-pr-media skill in the user-level skill directories
# of the coding agents actually present on this machine.
#
#   ./install-skill.sh                 # detect, then install/update
#   ./install-skill.sh --dry-run       # show what would happen, change nothing
#   ./install-skill.sh --target PATH   # also sync into a custom skills directory
#   ./install-skill.sh --force NAME    # sync even if that agent was not detected
#
# A config directory alone is NOT treated as proof of installation: uninstalling
# a CLI usually leaves ~/.<tool> behind. A tool counts as installed when its
# binary is on PATH or its app bundle exists; a leftover directory is reported
# separately and skipped.
set -uo pipefail

SKILL_NAME=github-pr-media
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUIDE_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$GUIDE_DIR/skills/$SKILL_NAME/SKILL.md"

dry_run=0
extra_targets=""
forced_tools=""

usage() {
  cat <<'EOF'
Usage: install-skill.sh [options]

  --dry-run        Show the plan; do not write anything.
  --target PATH    Extra skills directory to sync into (repeatable).
  --force TOOL     Sync even when TOOL is not detected (workbuddy|claude|codex).
  -h, --help       This text.

Detects WorkBuddy (app or ~/.workbuddy), Claude Code (claude on PATH),
and Codex (codex on PATH), then copies skills/github-pr-media into the
matching ~/.<tool>/skills/ directory.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --target)
      [ "$#" -ge 2 ] || { echo "Error: --target needs a path" >&2; exit 2; }
      extra_targets="$extra_targets$2
"
      shift
      ;;
    --force)
      [ "$#" -ge 2 ] || { echo "Error: --force needs a tool name" >&2; exit 2; }
      forced_tools="$forced_tools $2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$SRC" ]; then
  echo "Error: skill source not found at $SRC" >&2
  echo "Run this from a clone of github-pr-media-guide." >&2
  exit 1
fi

sha_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -c1-8
  else
    sha256sum "$1" | cut -c1-8
  fi
}

SRC_SHA="$(sha_of "$SRC")"
printf 'Skill source: %s\n' "$SRC"
printf 'Checksum:     %s\n\n' "$SRC_SHA"

printf '%-14s %-34s %s\n' 'TOOL' 'DETECTED BY' 'ACTION'
printf '%-14s %-34s %s\n' '--------------' '----------------------------------' '------'

installed=0
skipped=0
failed=0

# name | binary | app bundle | skills dir
targets="WorkBuddy|workbuddy|/Applications/WorkBuddy.app|$HOME/.workbuddy/skills
Claude Code|claude||$HOME/.claude/skills
Codex|codex||$HOME/.codex/skills"

sync_into() {
  # $1 = label, $2 = destination skills dir, $3 = detection evidence
  local label="$1" dest_dir="$2" evidence="$3" dest_file
  dest_file="$dest_dir/$SKILL_NAME/SKILL.md"

  if [ "$dry_run" -eq 1 ]; then
    printf '%-14s %-34s %s\n' "$label" "$evidence" "would write it"
    installed=$((installed + 1))
    return 0
  fi

  if ! mkdir -p "$dest_dir/$SKILL_NAME"; then
    printf '%-14s %-34s %s\n' "$label" "$evidence" "FAILED to create directory"
    failed=$((failed + 1))
    return 1
  fi
  if ! cp "$SRC" "$dest_file"; then
    printf '%-14s %-34s %s\n' "$label" "$evidence" "FAILED to write"
    failed=$((failed + 1))
    return 1
  fi

  if [ "$(sha_of "$dest_file")" = "$SRC_SHA" ]; then
    printf '%-14s %-34s %s\n' "$label" "$evidence" "ok (checksum verified)"
    installed=$((installed + 1))
  else
    printf '%-14s %-34s %s\n' "$label" "$evidence" "CHECKSUM MISMATCH"
    failed=$((failed + 1))
  fi
}

while IFS='|' read -r name bin app dest; do
  [ -n "$name" ] || continue

  evidence=''
  installed_hint=0

  if [ -n "$bin" ] && command -v "$bin" >/dev/null 2>&1; then
    evidence="cli $(command -v "$bin")"
    installed_hint=1
  elif [ -n "$app" ] && [ -d "$app" ]; then
    evidence="app $app"
    installed_hint=1
  elif [ -d "$(dirname "$dest")" ]; then
    evidence="only $(dirname "$dest") exists"
  fi

  force_hit=0
  case " $forced_tools " in
    *" $name "*|*" $bin "*) force_hit=1 ;;
  esac
  if [ "$force_hit" -eq 1 ]; then
    installed_hint=1
    # Do not claim a leftover directory as evidence when the user forced it.
    [ -n "$evidence" ] && case "$evidence" in only\ *) evidence='' ;; esac
    evidence="${evidence:-forced by --force}"
  fi

  if [ "$installed_hint" -eq 1 ]; then
    sync_into "$name" "$dest" "${evidence:-forced}"
  else
    if [ -n "$evidence" ]; then
      printf '%-14s %-34s %s\n' "$name" "$evidence" "skipped (looks uninstalled)"
    else
      printf '%-14s %-34s %s\n' "$name" "not found" "skipped"
    fi
    skipped=$((skipped + 1))
  fi
done <<EOF
$targets
EOF

# Anything the caller pointed at explicitly, without judgement.
if [ -n "$extra_targets" ]; then
  printf '%s' "$extra_targets" | while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ "$dry_run" -eq 1 ]; then
      printf '%-14s %-34s %s\n' '--target' "-" "would write $t/$SKILL_NAME/SKILL.md"
    else
      mkdir -p "$t/$SKILL_NAME" && cp "$SRC" "$t/$SKILL_NAME/SKILL.md" \
        && printf '%-14s %-34s %s\n' '--target' "-" "ok ($t)"
    fi
  done
  # NOTE: the loop above runs in a subshell; extra targets are reported but not
  # counted, and a failure there does not change the exit code.
fi

printf '\n'
if [ "$dry_run" -eq 1 ]; then
  printf 'Dry run: %s agent(s) would be updated, %s skipped.\n' "$installed" "$skipped"
else
  printf 'Updated %s agent(s), skipped %s, failed %s.\n' "$installed" "$skipped" "$failed"
fi

if [ "$installed" -eq 0 ] && [ "$skipped" -gt 0 ]; then
  printf 'No supported agent detected. Point the script at one explicitly:\n'
  printf '  %s --target ~/.some-agent/skills\n' "$0"
fi

[ "$failed" -eq 0 ] || exit 1

printf '\nUpdate flow: edit skills/%s/SKILL.md in the guide, re-run this script.\n' "$SKILL_NAME"
printf 'Never edit the copies under ~/.<tool>/skills — the next sync overwrites them.\n'

#!/usr/bin/env bash
# Attach one or more images to an existing PR as a single comment.
# Leaves the PR description untouched.
#
#   ./pr-media-comment.sh [-R owner/repo] [-b "comment body"] <PR> <file[#alt]...>
#
# Examples:
#   ./pr-media-comment.sh 123 ./after.png
#   ./pr-media-comment.sh -R GetSayAll/example 123 './before.png#修改前' './after.png#修改后'
#
# Requires gh >= 2.99.0. Run inside the repository, or pass -R explicitly.
set -euo pipefail

MIN_MAJOR=2
MIN_MINOR=99
MAX_IMAGE_BYTES=10000000    # GitHub limit is 10 MB; keep a small margin
MAX_VIDEO_BYTES=100000000   # paid plans; free plans reject above 10 MB server-side

usage() {
  printf 'Usage: %s [-R owner/repo] [-b "body"] <PR_NUMBER_OR_URL> <file[#alt]...>\n' "$(basename "$0")" >&2
  exit 2
}

repo_flag=()
body='UI 验证截图（GitHub 原生附件，未纳入 Git 仓库）'

while getopts ':R:b:h' opt; do
  case "$opt" in
    R) repo_flag=(-R "$OPTARG") ;;
    b) body="$OPTARG" ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -ge 2 ] || usage
pr="$1"
shift

# --- gh presence and version ---------------------------------------------
command -v gh >/dev/null 2>&1 || { echo 'Error: gh (GitHub CLI) is not installed. Try: brew install gh' >&2; exit 1; }

# Parse without `head`: piping into a command that exits early raises SIGPIPE
# in gh, and with `set -o pipefail` that aborts a run that is perfectly fine.
ver="$(gh --version 2>/dev/null | sed -n 's/.*version \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' | sed -n '1p')"
if [ -n "$ver" ]; then
  major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
  if [ "$major" -lt "$MIN_MAJOR" ] || { [ "$major" -eq "$MIN_MAJOR" ] && [ "$minor" -lt "$MIN_MINOR" ]; }; then
    printf 'Error: gh %s is too old; --attach needs >= %s.%s.0. Try: brew upgrade gh\n' \
      "$ver" "$MIN_MAJOR" "$MIN_MINOR" >&2
    exit 1
  fi
fi

# --- validate every file before uploading anything ------------------------
attachments=()
seen_paths=''

for arg in "$@"; do
  # '<path>#<alt text>' — split on the first '#'
  case "$arg" in
    *'#'*) file="${arg%%#*}"; alt="${arg#*#}" ;;
    *)     file="$arg";       alt='' ;;
  esac

  [ -n "$file" ] || { printf 'Error: empty file path in argument: %s\n' "$arg" >&2; exit 1; }
  [ -f "$file" ] || { printf 'Error: file not found: %s\n' "$file" >&2; exit 1; }
  [ -r "$file" ] || { printf 'Error: file not readable: %s\n' "$file" >&2; exit 1; }

  # Same file twice is rejected by gh; catch it before the upload.
  real="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  case "$seen_paths" in
    *"|$real|"*) printf 'Error: the same file is attached twice (gh rejects this): %s\n' "$file" >&2; exit 1 ;;
  esac
  seen_paths="$seen_paths|$real|"

  ext="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    png|jpg|jpeg|gif|webp|svg) limit=$MAX_IMAGE_BYTES; kind=image ;;
    mp4|mov|webm)              limit=$MAX_VIDEO_BYTES; kind=video ;;
    *) printf 'Error: unsupported extension .%s (allowed: png jpg jpeg gif webp svg mp4 mov webm): %s\n' "$ext" "$file" >&2; exit 1 ;;
  esac

  if size=$(stat -f%z "$file" 2>/dev/null); then
    :                                     # BSD / macOS
  else
    size=$(stat -c%s "$file")             # GNU / Linux
  fi

  if [ "$size" -gt "$limit" ]; then
    printf 'Error: %s is %s bytes, over the %s limit (%s bytes)\n' \
      "$file" "$size" "$kind" "$limit" >&2
    if [ "$kind" = image ]; then
      printf 'Hint: sips -Z 1600 "%s" --out "%s.resized.png"\n' "$file" "$file" >&2
    fi
    exit 1
  fi

  # Video renders as a player and drops alt text; flag it rather than fail.
  if [ "$kind" = video ] && [ -n "$alt" ]; then
    printf 'Warning: alt text is ignored for videos (%s)\n' "$file" >&2
  fi

  if [ -n "$alt" ]; then
    attachments+=(--attach "$file#$alt")
  else
    attachments+=(--attach "$file")
  fi
done

# --- confirm the PR exists and is reachable ------------------------------
if ! gh pr view "$pr" "${repo_flag[@]+"${repo_flag[@]}"}" --json url --jq .url >/dev/null; then
  printf 'Error: cannot access PR %s. Check the number, the repository (-R), and your permissions.\n' "$pr" >&2
  exit 1
fi

# --- post the comment ----------------------------------------------------
# A nonzero exit can still mean partial success: check the PR before retrying.
if ! gh pr comment "$pr" "${repo_flag[@]+"${repo_flag[@]}"}" \
      --body "$body" "${attachments[@]}"; then
  printf '\nThe command failed, but some attachments may have uploaded.\n' >&2
  printf 'Check before retrying:  gh pr view %s --json comments --jq ".comments[-1].body"\n' "$pr" >&2
  exit 1
fi

printf 'Done. Comment posted on PR %s.\n' "$pr"

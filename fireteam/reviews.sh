#!/usr/bin/env bash
# Manage pipeline review scratch under .claude/reviews/ (gitignored).
# Usage:
#   reviews.sh write <sha>    write findings from stdin to the file for <sha>
#   reviews.sh path [<sha>]   print the findings path for a commit (default HEAD)
#   reviews.sh list           list review files with staleness marked
#   reviews.sh clean          delete review files that no longer match HEAD
#   reviews.sh purge          delete all review files
set -eu

# Where Fire Team is installed (this script's own directory).
FIRETEAM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT"
mkdir -p .claude/reviews
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo none)

case "${1:-list}" in
  write)
    # The path is COMPUTED from the sha, never taken from the caller, so this
    # cannot be used to write outside .claude/reviews/.
    [ -n "${2:-}" ] || { echo "usage: reviews.sh write <sha>" >&2; exit 2; }
    SHA=$(git rev-parse --verify --quiet "$2^{commit}" 2>/dev/null) || \
      { echo "not a commit: $2" >&2; exit 2; }
    case "$SHA" in
      *[!0-9a-f]* | "") echo "refused: unresolvable revision" >&2; exit 2 ;;
    esac
    [ ${#SHA} -eq 40 ] || { echo "refused: unresolvable revision" >&2; exit 2; }
    OUT=".claude/reviews/${SHA}.md"
    cat > "$OUT"
    [ -s "$OUT" ] || { rm -f "$OUT"; echo "refused: empty findings" >&2; exit 2; }
    echo "$OUT"
    ;;
  path)
    SHA=${2:-$HEAD_SHA}
    SHA=$(git rev-parse "$SHA" 2>/dev/null || echo "$SHA")
    echo ".claude/reviews/${SHA}.md"
    ;;
  list)
    found=0
    for f in .claude/reviews/*.md; do
      [ -e "$f" ] || continue
      found=1
      base=$(basename "$f" .md)
      case "$HEAD_SHA" in "$base"*) echo "current  $f" ;; *) echo "stale    $f" ;; esac
    done
    [ "$found" = 0 ] && echo "(no review files)"
    ;;
  clean)
    n=0
    for f in .claude/reviews/*.md; do
      [ -e "$f" ] || continue
      base=$(basename "$f" .md)
      case "$HEAD_SHA" in "$base"*) ;; *) rm -f "$f"; n=$((n+1)) ;; esac
    done
    echo "removed $n stale review file(s)"
    ;;
  purge)
    rm -f .claude/reviews/*.md 2>/dev/null || true
    echo "removed all review files"
    ;;
  *)
    echo "usage: reviews.sh {path [<sha>]|list|clean|purge}" >&2; exit 2 ;;
esac

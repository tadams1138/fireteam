#!/usr/bin/env bash
# Manage pipeline review scratch under .claude/reviews/ (gitignored).
# Usage:
#   reviews.sh write <sha>    write findings from stdin to the file for <sha>
#   reviews.sh append <sha>   append a further chunk from stdin to that file
#   reviews.sh path [<sha>]   print the findings path for a commit (default HEAD)
#   reviews.sh list           list review files with staleness marked
#   reviews.sh clean          delete review files that no longer match HEAD
#   reviews.sh purge          delete all review files
#
# Why `append` exists: the reviewer holds no Write tool by design, so its findings
# reach disk only as stdin to this script -- inside a single shell command, which
# the tool layer caps at a few kilobytes. A long findings file exceeded that cap and
# was silently truncated, and the reviewer compressed its analysis to fit. Chunking
# fixes that without widening anyone's grant: `write` opens the file, `append` adds
# to it, and the destination is still COMPUTED here from a verified SHA rather than
# taken from the caller.
set -eu

# Where Fire Team is installed (this script's own directory).
FIRETEAM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT"
mkdir -p .claude/reviews
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo none)

# Resolve a caller-supplied revision to a verified 40-hex SHA, setting $SHA.
#
# Every write path in this script derives its filename from $SHA and nothing else,
# so a caller cannot direct output outside .claude/reviews/. Keep it that way: this
# must stay the only way a destination is chosen. Sets a global rather than echoing
# a result, so that a rejection here exits the script rather than a subshell.
resolve_sha() {
  [ -n "${1:-}" ] || { echo "usage: reviews.sh $2 <sha>" >&2; exit 2; }
  SHA=$(git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null) || \
    { echo "not a commit: $1" >&2; exit 2; }
  case "$SHA" in
    *[!0-9a-f]* | "") echo "refused: unresolvable revision" >&2; exit 2 ;;
  esac
  [ ${#SHA} -eq 40 ] || { echo "refused: unresolvable revision" >&2; exit 2; }
}

# Byte count of a file, whitespace stripped so `test -gt` always sees an integer.
size_of() { wc -c < "$1" | tr -d '[:space:]'; }

case "${1:-list}" in
  write)
    resolve_sha "${2:-}" write
    OUT=".claude/reviews/${SHA}.md"
    # `write` always opens a clean file, so a re-review of the same commit replaces
    # the old findings rather than doubling them. That also means a `write` issued
    # mid-sequence -- where `append` was meant -- discards the chunks already sent.
    # Warn rather than block: re-reviewing is legitimate, losing findings silently
    # is not.
    if [ -s "$OUT" ]; then
      echo "warning: ${OUT} already held $(size_of "$OUT") bytes; replacing it." >&2
      echo "if you meant to add to it, use: reviews.sh append <sha>" >&2
    fi
    cat > "$OUT"
    [ -s "$OUT" ] || { rm -f "$OUT"; echo "refused: empty findings" >&2; exit 2; }
    echo "$OUT"
    ;;
  append)
    resolve_sha "${2:-}" append
    OUT=".claude/reviews/${SHA}.md"
    # Refuse to create the file. A chunk arriving before `write` means the opening
    # chunk was lost, and a findings file that starts mid-sentence reads as complete.
    [ -f "$OUT" ] || { echo "refused: no findings file for ${SHA} -- call 'write' first" >&2; exit 2; }
    BEFORE=$(size_of "$OUT")
    cat >> "$OUT"
    AFTER=$(size_of "$OUT")
    # An empty chunk almost always means the payload was truncated away in transit.
    [ "$AFTER" -gt "$BEFORE" ] || { echo "refused: empty chunk -- nothing appended" >&2; exit 2; }
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
    echo "usage: reviews.sh {write <sha>|append <sha>|path [<sha>]|list|clean|purge}" >&2; exit 2 ;;
esac

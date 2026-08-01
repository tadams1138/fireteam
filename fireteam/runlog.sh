#!/usr/bin/env bash
# Records what actually happened during a Fire Team run, so the debrief
# analyzes evidence instead of guessing. Logs live in .claude/runs/ (gitignored).
#
# Usage:
#   runlog.sh start "<feature description>"      begin a run, prints the log path
#   runlog.sh stage <n> <agent> <model> <outcome> ["<notes>"]
#   runlog.sh gate <name> <decision> ["<notes>"]
#   runlog.sh note "<text>"
#   runlog.sh cost "<figure from /cost>"          optional, user-supplied
#   runlog.sh end <outcome>
#   runlog.sh path | show | list | clean
set -eu

# Where Fire Team is installed (this script's own directory).
FIRETEAM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT"
mkdir -p .claude/runs
CUR=.claude/runs/.current
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

need_current() {
  [ -f "$CUR" ] || { echo "no active run — call: runlog.sh start \"<desc>\"" >&2; exit 2; }
  LOG=$(cat "$CUR")
  [ -f "$LOG" ] || { echo "run log missing: $LOG" >&2; exit 2; }
}

case "${1:-show}" in
  start)
    [ -n "${2:-}" ] || { echo "usage: runlog.sh start \"<description>\"" >&2; exit 2; }
    ID=$(date -u +%Y%m%d-%H%M%S)
    LOG=".claude/runs/${ID}.md"
    BASE=$(git rev-parse HEAD 2>/dev/null || echo none)
    {
      echo "# Fire Team run ${ID}"
      echo
      echo "- started: $(now)"
      echo "- base commit: ${BASE}"
      echo "- request: $2"
      echo
      echo "## Timeline"
      echo
    } > "$LOG"
    printf '%s' "$LOG" > "$CUR"
    echo "$LOG" ;;

  stage)
    need_current
    [ "$#" -ge 5 ] || { echo "usage: runlog.sh stage <n> <agent> <model> <outcome> [notes]" >&2; exit 2; }
    HEADSHA=$(git rev-parse --short HEAD 2>/dev/null || echo none)
    printf -- '- %s  stage=%s agent=%s model=%s outcome=%s head=%s notes=%s\n' \
      "$(now)" "$2" "$3" "$4" "$5" "$HEADSHA" "${6:-none}" >> "$LOG" ;;

  gate)
    need_current
    [ "$#" -ge 3 ] || { echo "usage: runlog.sh gate <name> <decision> [notes]" >&2; exit 2; }
    printf -- '- %s  GATE=%s decision=%s notes=%s\n' "$(now)" "$2" "$3" "${4:-none}" >> "$LOG" ;;

  note)
    need_current
    [ -n "${2:-}" ] || { echo "usage: runlog.sh note \"<text>\"" >&2; exit 2; }
    printf -- '- %s  note: %s\n' "$(now)" "$2" >> "$LOG" ;;

  cost)
    need_current
    [ -n "${2:-}" ] || { echo "usage: runlog.sh cost \"<figure>\"" >&2; exit 2; }
    printf -- '- %s  cost (user-supplied): %s\n' "$(now)" "$2" >> "$LOG" ;;

  end)
    need_current
    {
      echo
      echo "## Result"
      echo
      echo "- ended: $(now)"
      echo "- outcome: ${2:-unspecified}"
      echo "- head commit: $(git rev-parse HEAD 2>/dev/null || echo none)"
    } >> "$LOG"
    echo "$LOG" ;;

  path)  need_current; echo "$LOG" ;;
  show)  need_current; cat "$LOG" ;;
  list)  ls -1 .claude/runs/*.md 2>/dev/null || echo "(no runs)" ;;
  clean) rm -f .claude/runs/*.md "$CUR" 2>/dev/null || true; echo "run logs cleared" ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

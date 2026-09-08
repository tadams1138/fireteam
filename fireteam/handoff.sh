#!/usr/bin/env bash
# Commit a stage's work in the constitutional handoff format (Article V).
#
# Usage: handoff.sh <role> <next-role|complete> "<state>" "<summary>" \
#                   ["<note>"...] [-- "<unverified>"...]
#
# Every value is a positional argument on purpose. Do NOT prefix this command
# with an environment assignment (STATE="..." handoff.sh ...) -- permission rules
# match a command's leading text, so a leading assignment matches no rule and
# interrupts the user for approval every single time.
#
# Notes and unverified items are variadic, one argument each, rendered as bullets.
# Article V requires every deviation to be listed, and a single string cannot hold
# three of them legibly -- so pass three arguments:
#
#   handoff.sh tdd-implementer solid-reviewer "58/58" "add assignment" \
#     "stryker not run" "retried a flaky timing assertion"
#
# Everything after a bare `--` becomes an Unverified: entry instead: facts about
# the limits of your own work, which Article VIII exempts from the ban on writing
# to a later role. See Article V for which field a thing belongs in.
#
# Prints the resulting SHA. Refuses to stage review scratch.
set -eu

# Where Fire Team is installed (this script's own directory).
FIRETEAM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$#" -lt 4 ]; then
  echo "usage: handoff.sh <role> <next-role|complete> \"<state>\" \"<summary>\" \\" >&2
  echo "                  [\"<note>\"...] [-- \"<unverified>\"...]" >&2
  echo "  e.g. handoff.sh tdd-implementer solid-reviewer \"58/58 acceptance, 71/71 unit\" \\" >&2
  echo "                  \"add specialist assignment\" \"stryker not run\" \\" >&2
  echo "                  -- \"scenarios 2 and 4 pass against a no-op filter\"" >&2
  exit 2
fi
ROLE=$1; NEXT=$2; STATE=$3; SUMMARY=$4
shift 4

# Split the remaining arguments on a bare `--`: notes before it, unverified after.
NOTES=""
UNVERIFIED=""
past_sep=0
for arg in "$@"; do
  if [ "$past_sep" = 0 ] && [ "$arg" = "--" ]; then past_sep=1; continue; fi
  if [ "$past_sep" = 1 ]; then
    UNVERIFIED="${UNVERIFIED}- ${arg}
"
  else
    NOTES="${NOTES}- ${arg}
"
  fi
done

# An empty field is written as "none" rather than omitted. An explicit "none" is a
# claim the role made and the debrief can hold it to; a missing field is silence.
render_field() {
  if [ -z "$2" ]; then
    printf '%s: none\n' "$1"
  else
    printf '%s:\n%s' "$1" "$2"
  fi
}

ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT"

# Never let review scratch into a commit, whatever the caller intended.
git reset -q -- .claude/reviews 2>/dev/null || true

git add -A -- . ':(exclude).claude/reviews' 2>/dev/null || git add -A .
git reset -q -- .claude/reviews 2>/dev/null || true

if git diff --cached --quiet; then
  echo "nothing staged — no commit made" >&2
  exit 1
fi

# CLAUDE.md and .claude/settings.json are the orchestrator's to write (Article VI) —
# no role owns them. Their presence here almost always means an earlier gate's edits
# were left uncommitted and this stage's `git add -A` swept them in. Warn, don't
# block: the commit may still be legitimate (e.g. a role touching its own working
# tree state), and it's the human reviewing the handoff who should judge that.
STRAY=$(git diff --cached --name-only -- CLAUDE.md .claude/settings.json .claude/settings.local.json)
if [ -n "$STRAY" ]; then
  echo "warning: this commit includes files no role should own:" >&2
  printf '%s\n' "$STRAY" | sed 's/^/  /' >&2
  echo "if these came from a gate you approved, they should have been committed" >&2
  echo "separately before this stage ran — check the attribution before relying on it." >&2
fi

{
  printf '%s: %s\n\n' "$ROLE" "$SUMMARY"
  printf 'Handoff: %s\n' "$NEXT"
  printf 'State: %s\n' "$STATE"
  render_field Notes "$NOTES"
  render_field Unverified "$UNVERIFIED"
} | git commit -q -F -

SHA=$(git rev-parse HEAD)
echo "$SHA"

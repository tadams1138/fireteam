#!/usr/bin/env bash
# Commit a stage's work in the constitutional handoff format (Article V).
#
# Usage: handoff.sh <role> <next-role|complete> "<state>" "<summary>" ["<notes>"]
#
# Every value is a positional argument on purpose. Do NOT prefix this command
# with an environment assignment (STATE="..." handoff.sh ...) -- permission rules
# match a command's leading text, so a leading assignment matches no rule and
# interrupts the user for approval every single time.
#
# Prints the resulting SHA. Refuses to stage review scratch.
set -eu

# Where Fire Team is installed (this script's own directory).
FIRETEAM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$#" -lt 4 ]; then
  echo "usage: handoff.sh <role> <next-role|complete> \"<state>\" \"<summary>\" [\"<notes>\"]" >&2
  echo "  e.g. handoff.sh tdd-implementer solid-reviewer \"58/58 acceptance, 71/71 unit\" \\" >&2
  echo "                  \"add specialist assignment\" \"stryker not run\"" >&2
  exit 2
fi
ROLE=$1; NEXT=$2; STATE=$3; SUMMARY=$4; NOTES=${5:-none}

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

git commit -q -F - << MSGEOF
${ROLE}: ${SUMMARY}

Handoff: ${NEXT}
State: ${STATE}
Notes: ${NOTES}
MSGEOF

SHA=$(git rev-parse HEAD)
echo "$SHA"

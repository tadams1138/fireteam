#!/usr/bin/env bash
# Install Fire Team into ~/.claude. Idempotent; safe to re-run to upgrade.
# Usage:  ./install.sh [target]      (default target: ~/.claude)
#
# Runs anywhere a bash exists: Linux, macOS, WSL, and Git Bash on Windows.
#
# Finds its source files whether they sit in the shipped tree
# (fireteam/, agents/, commands/) or flat in one directory next to this script.
# Reports every file it copies and fails loudly on anything missing.
#
# This is the ONLY part of Fire Team that writes to the install directory. It
# also normalizes what it installs -- strips CR, sets the executable bit, and
# prunes files left by earlier versions. preflight.sh only ever reports problems
# there and points back here, so that nothing but this installer, run by you,
# touches anything outside a repository.
set -u
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# HOME is set on Linux and macOS, and by Git Bash and WSL on Windows. Fall back
# to the Windows profile variables for a bash started without it, so the default
# target resolves the same way on every platform.
home_dir() {
  if [ -n "${HOME:-}" ]; then printf '%s' "$HOME"; return 0; fi
  if [ -n "${USERPROFILE:-}" ]; then printf '%s' "$USERPROFILE" | tr '\\' '/'; return 0; fi
  if [ -n "${HOMEDRIVE:-}" ] && [ -n "${HOMEPATH:-}" ]; then
    printf '%s%s' "$HOMEDRIVE" "$HOMEPATH" | tr '\\' '/'; return 0
  fi
  return 1
}

if [ "$#" -ge 1 ]; then
  DEST=$1
elif H=$(home_dir); then
  DEST="$H/.claude"
else
  echo "cannot determine your home directory — pass the target: install.sh <dir>" >&2
  exit 1
fi

# Fail here rather than letting every copy fail one by one. A bad target -- a
# path that cannot be created, or one that exists but is not writable -- is a
# problem with the argument, and saying so once is clearer than eleven
# copy-failures pointing at the source tree.
if ! mkdir -p "$DEST" 2>/dev/null || [ ! -w "$DEST" ]; then
  echo "cannot install to: $DEST" >&2
  if [ "$#" -ge 1 ]; then
    echo >&2
    echo "That is the target you passed as an argument. Check it is a real path you" >&2
    echo "can write to — the target shown in the README is a placeholder to replace," >&2
    echo "not a literal path. To install to the default ~/.claude, pass no argument:" >&2
    echo >&2
    echo "  bash install.sh" >&2
  fi
  exit 1
fi

SCRIPTS="constitution.md preflight.sh handoff.sh reviews.sh runlog.sh install.sh"
AGENTS="fireteam-spec-author.md fireteam-tdd-implementer.md fireteam-solid-reviewer.md fireteam-retro.md"
COMMANDS="fireteam.md"

# Files shipped by earlier versions and since removed or renamed. Installing is
# a copy, so without this an upgrade leaves the old file sitting there -- and a
# stale agent or wrapper script still gets discovered and used.
OBSOLETE_FIRETEAM="dev.sh pipeline.conf.example pipeline.conf command-guard.sh"
OBSOLETE_AGENTS="pipeline-retro.md spec-author.md tdd-implementer.md solid-reviewer.md"
OBSOLETE_COMMANDS="assembly-line.md"

missing=""
unwritable=""
copied=0

# Locate a file by name across every plausible layout.
locate() {
  for cand in "$SRC/$1" "$SRC/../$2/$1" "$SRC/$2/$1" "$SRC/../$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}

install_group() { # $1 = subdir under DEST, $2 = source-tree subdir, $3... = filenames
  label=$1; destdir="$DEST/$1"; srcsub=$2; shift 2
  mkdir -p "$destdir"
  for f in $@; do
    if src=$(locate "$f" "$srcsub"); then
      if cp "$src" "$destdir/$f" 2>/dev/null; then
        echo "  + $label/$f"
        copied=$((copied+1))
      else
        unwritable="$unwritable $label/$f"
      fi
    else
      missing="$missing $label/$f"
    fi
  done
}

echo "Installing Fire Team to $DEST"
echo "  source: $SRC"
echo
install_group fireteam fireteam $SCRIPTS
install_group agents   agents   $AGENTS
install_group commands commands $COMMANDS

# Normalize line endings and permissions on anything that landed. The .sh files
# must be LF whatever the source checkout did to them. chmod is best-effort:
# Windows filesystems have no real executable bit, and preflight.sh treats a
# missing one there as advisory rather than a failure.
for f in "$DEST"/fireteam/*.sh; do
  [ -e "$f" ] || continue
  tmp="$f.tmp$$"
  if tr -d '\r' < "$f" > "$tmp"; then cat "$tmp" > "$f"; fi
  rm -f "$tmp"
  chmod +x "$f" 2>/dev/null || true
done

# Remove anything a previous version installed that is no longer part of Fire Team.
removed=0
prune() { # $1 = subdir, $2... = filenames
  d="$DEST/$1"; sub=$1; shift
  for f in $@; do
    if [ -e "$d/$f" ]; then
      rm -f "$d/$f" && echo "  - $sub/$f (obsolete)" && removed=$((removed+1))
    fi
  done
}
prune fireteam $OBSOLETE_FIRETEAM
prune agents   $OBSOLETE_AGENTS
prune commands $OBSOLETE_COMMANDS

echo
# A file that could not be found is a source-tree problem; one that could not be
# written is a target problem. They need different advice, so report them apart.
if [ -n "$missing" ] || [ -n "$unwritable" ]; then
  echo "INSTALL INCOMPLETE — copied $copied file(s)."
  if [ -n "$missing" ]; then
    echo
    echo "Could not find in the source tree at $SRC:"
    for m in $missing; do echo "  ! $m"; done
    echo
    echo "Put every Fire Team file in one directory alongside install.sh (or keep the"
    echo "shipped fireteam/ + agents/ + commands/ layout) and run this again."
  fi
  if [ -n "$unwritable" ]; then
    echo
    echo "Could not write into $DEST:"
    for m in $unwritable; do echo "  ! $m"; done
    echo
    echo "Check that you own that directory and its contents are not read-only."
  fi
  exit 1
fi

echo "Fire Team installed — $copied file(s)$([ "$removed" -gt 0 ] && echo ", $removed obsolete removed")."
echo "  scripts + constitution : $DEST/fireteam/"
echo "  agents                 : $DEST/agents/fireteam-*.md"
echo "  command                : $DEST/commands/fireteam.md  ->  /fireteam"
echo
echo "One-time setup — add to $DEST/settings.json so the pipeline's own scripts"
echo "run without prompting on every invocation:"
cat <<'JSON'

  "permissions": {
    "allow": [
      "Bash(~/.claude/fireteam/preflight.sh:*)",
      "Bash(~/.claude/fireteam/handoff.sh:*)",
      "Bash(~/.claude/fireteam/reviews.sh:*)",
      "Bash(~/.claude/fireteam/runlog.sh:*)"
    ],
    "deny": [
      "Bash(cd:*)",
      "Bash(pushd:*)",
      "Write(~/.claude/fireteam/**)",
      "Edit(~/.claude/fireteam/**)"
    ]
  }

JSON
echo "Merge it by hand — this installer never edits a permissions file."
echo
echo "Verify in any repo with:  $DEST/fireteam/preflight.sh"

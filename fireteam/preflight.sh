#!/usr/bin/env bash
# Fire Team preflight — verifies every invariant the pipeline depends on, and
# repairs the ones it can.
#
# Inside the repository, anything this script can fix, it fixes: those repairs
# are idempotent and the pipeline cannot run without them, so reporting them and
# making you act would only cost a round trip. Repairs print as FIXED lines.
#
# It writes nothing outside the repository -- no exceptions, including for its
# own install. Problems there are reported, not repaired; that directory belongs
# to install.sh.
#
# Two phases. The install phase needs no repository, so you can verify an
# install from anywhere. The repository phase needs one.
#
# Usage:  preflight.sh          (or: bash preflight.sh, where no exec bit exists)
# Exit:   0 = ready, 1 = blocked (message says what needs your decision)
set -u

# Where Fire Team is installed (this script's own directory).
FIRETEAM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Platform. These scripts are POSIX shell and run anywhere a bash exists: Linux,
# macOS, WSL, and Git Bash on Windows. Two checks below differ by platform,
# because a Windows filesystem has no real executable bit and a Windows checkout
# can silently rewrite LF to CRLF. WSL reports Linux, which is correct -- its
# filesystem behaves like one.
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
  Linux)                PLATFORM=linux   ;;
  Darwin)               PLATFORM=macos   ;;
  *)                    PLATFORM=unknown ;;
esac

fail=0
note()  { printf '  %s\n' "$*"; }
ok()    { printf 'OK    %s\n' "$*"; }
bad()   { printf 'FAIL  %s\n' "$*"; fail=1; }
fixed() { printf 'FIXED %s\n' "$*"; }

append_block() {   # append to a file, ensuring it starts on a fresh line
  target=$1; shift
  if [ -s "$target" ] && [ -n "$(tail -c1 "$target" 2>/dev/null)" ]; then
    printf '\n' >> "$target"
  fi
  printf '%s\n' "$@" >> "$target"
}

# =============================================================================
# PHASE 1 — install health (global; no repository required)
# =============================================================================
echo "-- install: $FIRETEAM_HOME  (platform: $PLATFORM)"
AG="$FIRETEAM_HOME/../agents"
CM="$FIRETEAM_HOME/../commands"
for f in "$FIRETEAM_HOME/constitution.md" \
         "$FIRETEAM_HOME/handoff.sh" \
         "$FIRETEAM_HOME/reviews.sh" "$FIRETEAM_HOME/runlog.sh" \
         "$AG/fireteam-spec-author.md" \
         "$AG/fireteam-tdd-implementer.md" \
         "$AG/fireteam-solid-reviewer.md" \
         "$AG/fireteam-retro.md" \
         "$CM/fireteam.md"; do
  if [ ! -f "$f" ]; then bad "missing $(basename "$f")"; continue; fi
  case "$f" in
    *.sh)
      # A CR in the shebang gives "bad interpreter: /usr/bin/env^M". install.sh
      # strips these, so this only catches a hand-copy or a Windows-editor save.
      # This script repairs nothing outside the repository (Article I). The
      # install directory belongs to install.sh; here we only report.
      if head -c 400 "$f" | tr -d '\n' | grep -q "$(printf '\r')"; then
        bad "$(basename "$f") has CRLF line endings — will fail with 'bad interpreter'"
        note "fix: re-run $FIRETEAM_HOME/install.sh"
      elif [ ! -x "$f" ]; then
        # A Windows filesystem has no executable bit to set, so a missing one
        # there is normal rather than a broken install. The script still runs,
        # invoked as `bash <script>` -- which the shipped allow rules cover.
        if [ "$PLATFORM" = windows ]; then
          ok "$(basename "$f")"
          note "no exec bit (normal on Windows) — invoke as: bash $f"
        else
          bad "$(basename "$f") is not executable"
          note "fix: re-run $FIRETEAM_HOME/install.sh"
        fi
      else
        ok "$(basename "$f")"
      fi ;;
    *) ok "$(basename "$f")" ;;
  esac
done

# Anything else in the install directory is left over from an older version.
# install.sh prunes the ones it knows about; this catches the rest.
for f in "$FIRETEAM_HOME"/*; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    constitution.md|preflight.sh|handoff.sh|reviews.sh|runlog.sh|install.sh) ;;
    *) bad "unexpected file in the install: $(basename "$f")"
       note "not part of Fire Team — a leftover from an older version. Re-run"
       note "install.sh, or delete it. Agents can still find and use it." ;;
  esac
done

# =============================================================================
# PHASE 2 — repository readiness
# =============================================================================
echo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "-- repository: (none)"
  note "not inside a git repository — install verified, repository checks skipped"
  echo
  if [ "$fail" = 0 ]; then echo "Install OK. Run again inside a repository to check it."; exit 0
  else echo "Preflight BLOCKED — repair the install above."; exit 1; fi
fi
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT" || exit 1
echo "-- repository: $ROOT"

# Snapshot the tree BEFORE any repair, so dirt this script creates can be told
# apart from dirt that was already there.
PRE_DIRTY=$(git status --porcelain 2>/dev/null)

# --- scratch is ignored ------------------------------------------------------
# Ignore first, create second: nothing can be observed untracked in between.
ign_missing=""
git check-ignore -q .claude/reviews/probe 2>/dev/null || ign_missing="$ign_missing .claude/reviews/"
git check-ignore -q .claude/runs/probe    2>/dev/null || ign_missing="$ign_missing .claude/runs/"
if [ -z "$ign_missing" ]; then
  ok "scratch is gitignored"
else
  append_block .gitignore \
    "# Fire Team scratch — findings and run logs are process records," \
    "# true only until acted upon. See constitution Article V."
  for d in $ign_missing; do printf '%s\n' "$d" >> .gitignore; done
  fixed "gitignored:$ign_missing"
fi

# --- scratch exists ----------------------------------------------------------
# Idempotent and invisible to git (empty directories are not tracked).
mkdir -p .claude/reviews .claude/runs
ok "scratch directories ready"

# --- nothing scratch is tracked ----------------------------------------------
# .gitignore does not untrack an already-committed file, so this is a distinct
# failure from the check above, and it applies to run logs as well as reviews.
tracked=$(git ls-files .claude/reviews .claude/runs 2>/dev/null)
if [ -n "$tracked" ]; then
  bad "scratch files are TRACKED by git — they must never be committed"
  printf '%s\n' "$tracked" | sed 's/^/       /'
  note "fix: git rm -r --cached .claude/reviews .claude/runs"
else
  ok "no scratch files tracked"
fi

# --- clean working tree ------------------------------------------------------
# handoff.sh stages with `git add -A`, so anything untracked-and-not-ignored
# would be swept into a stage commit.
POST_DIRTY=$(git status --porcelain 2>/dev/null)
if [ -z "$POST_DIRTY" ]; then
  ok "working tree clean"
elif [ -z "$PRE_DIRTY" ]; then
  bad "commit the .gitignore change this run just made, then start"
  note "git add .gitignore && git commit -m 'ignore Fire Team scratch'"
else
  bad "working tree is dirty — commit, stash, or ignore before starting"
  printf '%s\n' "$PRE_DIRTY" | sed 's/^/       /'
  [ "$PRE_DIRTY" != "$POST_DIRTY" ] && note "(plus the .gitignore entry this run added)"
fi

# --- permissions -------------------------------------------------------------
S=.claude/settings.json
if [ ! -f "$S" ]; then
  note "advisory: no $S — the pipeline will prompt for every tool call. Stage 1"
  note "          proposes rules scoped to this repo; approve them at the gate."
else
  leak=0
  for pat in 'Write(**/fireteam' 'Edit(**/fireteam' \
             'Write(.claude/settings' 'Edit(.claude/settings'; do
    if awk '/"deny"/{d=1} /"allow"/{d=0} !d' "$S" | grep -qF "$pat"; then leak=1; fi
  done
  if [ "$leak" = 1 ]; then
    bad "$S allowlists writes to the fireteam install or to settings.json itself"
    note "these must always prompt — an allow rule there turns a narrow execution"
    note "permission into an open shell. Remove it (constitution Article VI)."
  else
    ok "privileged paths are not allowlisted"
  fi
  # additionalDirectories is what extends file-tool access beyond the cwd. With
  # it unset, Read/Write/Edit cannot reach outside the repository at all.
  for cfg in "$S" "$FIRETEAM_HOME/../settings.json"; do
    [ -f "$cfg" ] || continue
    if grep -qF 'additionalDirectories' "$cfg" \
       && ! grep -qE 'additionalDirectories"?[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' "$cfg"; then
      bad "$cfg sets additionalDirectories — file tools can then write outside the repo"
      note "remove it unless you truly need it (Article I)"
    fi
  done

  # The pipeline's own scripts: granted at user level, repo level, or not at all.
  USER_S="$FIRETEAM_HOME/../settings.json"
  if grep -qF 'fireteam/handoff.sh' "$S" 2>/dev/null \
     || grep -qF 'fireteam/handoff.sh' "$USER_S" 2>/dev/null; then
    ok "pipeline scripts are allowlisted"
  else
    note "advisory: the pipeline's own scripts are not allowlisted — you will be asked"
    note "          to approve each handoff, run-log, and review write. Add them once"
    note "          to $(cd "$FIRETEAM_HOME/.." 2>/dev/null && pwd)/settings.json;"
    note "          install.sh prints the block."
  fi
  if grep -qF 'Bash(cd:' "$S"; then
    ok "cd is denied"
  else
    note "advisory: no \"Bash(cd:*)\" denial — without it a stray directory change"
    note "          prompts you instead of failing the agent (Article I)"
  fi
fi

# --- documented build/test commands ------------------------------------------
# The pipeline runs what the project documents, not what a shared script guesses.
if [ -f CLAUDE.md ] && grep -qiE '^[[:space:]]*[-*]?[[:space:]]*(test|build)[[:space:]]*:' CLAUDE.md; then
  ok "CLAUDE.md documents build/test commands"
  if grep -nE '(^|[^a-zA-Z])cd[[:space:]]' CLAUDE.md | grep -qiE '(test|build|format|accept)'; then
    bad "a documented command uses 'cd' — it matches no permission rule and will"
    note "prompt on every run. Rewrite it with the tool's own path argument:"
    note "  dotnet test <path> | npm --prefix <dir> | git -C <dir> | make -C <dir>"
    grep -nE '(^|[^a-zA-Z])cd[[:space:]]' CLAUDE.md | sed 's/^/       /'
  else
    ok "documented commands are cd-free"
  fi
else
  note "advisory: no build/test commands in CLAUDE.md — stage 1 will establish them"
  note "          and propose lines for you to approve"
fi

echo
if [ "$fail" = 0 ]; then echo "Preflight PASSED — pipeline ready."; exit 0
else echo "Preflight BLOCKED — resolve the FAIL lines above."; exit 1; fi

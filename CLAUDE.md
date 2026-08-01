# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Fire Team is the **source** for a Claude Code extension: a five-stage,
spec → implement → review → apply → debrief development pipeline made of four subagents, one
slash command, a constitution, and four shell scripts. It contains no application code and no
test suite of its own — the deliverable is the prompt/script bundle that gets installed into
`~/.claude`.

Consequence: editing a file here changes nothing until `install.sh` copies it. A running
pipeline reads `~/.claude/...`, never this working tree.

## Install / verify

```bash
./fireteam/install.sh              # copy into ~/.claude (idempotent; also prunes obsolete files)
./fireteam/install.sh /some/target # alternate target
~/.claude/fireteam/preflight.sh    # verify the install; run from inside a repo for the full check
```

`install.sh` is the only component that writes to the install directory. It strips CR, sets
`+x`, and deletes files from earlier versions listed in the `OBSOLETE_*` variables. Any file
added, renamed, or removed must be reflected in `install.sh`'s `SCRIPTS`/`AGENTS`/`COMMANDS`
lists **and** in `preflight.sh`'s required-file loop and its allowed-filename `case` — an
unlisted file in the install directory is reported as a stale leftover and fails preflight.

There is no build, lint, or test command. Verification is `preflight.sh` plus running
`/fireteam` against a real repository.

## Layout → install mapping

| Source | Installs to | Purpose |
|---|---|---|
| `fireteam/constitution.md` | `~/.claude/fireteam/` | shared rules every agent reads first |
| `fireteam/*.sh` | `~/.claude/fireteam/` | preflight, handoff, reviews, runlog, install |
| `agents/fireteam-*.md` | `~/.claude/agents/` | the four stage agents |
| `commands/fireteam.md` | `~/.claude/commands/` | the `/fireteam` orchestrator prompt |

## Architecture: where the invariants live

Three layers enforce the same discipline, and they must stay in sync. A rule stated in only
one of them is a bug.

1. **Agent frontmatter** — the hard boundary. `tools:` is the enforcement mechanism:
   `fireteam-solid-reviewer` and `fireteam-retro` hold no `Write`/`Edit`, so read-only is a
   fact, not a request. None holds `Agent`, so no subagent can spawn subagents.
2. **`constitution.md`** — nine articles, read first by every agent. Role prompts specialize;
   they never contradict it. Article numbers are cited across all the agent files and the
   command — renumbering an article means updating every citation.
3. **`preflight.sh`** — mechanically checks what can be checked (gitignored scratch, clean
   tree, no tracked scratch, permission leaks, `cd`-free documented commands) and repairs what
   it safely can inside the repo.

The orchestrator (`commands/fireteam.md`) delegates and gates; it writes no code. Stage
handoffs are commits (`handoff.sh`), stage 3's output is gitignored scratch under
`.claude/reviews/<sha>.md` (`reviews.sh`), and the run log under `.claude/runs/` (`runlog.sh`)
is the only evidence stage 5 has — so it must be written as each stage happens, not
reconstructed.

## Design constraints these files exist to satisfy

Understand these before changing anything; most of the odd-looking code is here on purpose.

- **Permission rules match a command's *leading text*.** This is why the constitution bans
  `cd`, `pushd`, `( cd … && … )`, leading env assignments (`STATE="x" handoff.sh …`), `env`,
  `sudo`, and `bash -c` wrappers — each makes an approved command match nothing and interrupt
  the user on every run. It is also why every script takes positional arguments only. Article I
  carries the per-tool substitution table (`dotnet test <path>`, `npm --prefix <dir>`,
  `git -C <dir>`, …).
- **Nothing but `install.sh` writes outside a repository** (Article I). `preflight.sh`
  deliberately only *reports* install problems and points back at `install.sh`. Roles use
  `.claude/runs/` and `.claude/reviews/` for scratch — never `/tmp`.
- **`~/.claude/fireteam/` and `.claude/settings.json` are privileged** (Article VI). No
  subagent edits them; a subagent that finds them wrong proposes a diff and stops. They are
  never added to `permissions.allow` — an allow rule there turns a narrow execution grant into
  an open shell. `install.sh` prints the settings block and tells the user to merge it by hand.
- **Repo-specific knowledge belongs in the target repo's `CLAUDE.md`, not in these scripts.**
  The installed scripts are shared by every repository on the machine. Stage 1 discovers a
  repo's build/test commands and *proposes* `CLAUDE.md` lines; a human applies them.
- **Review findings are never committed** (Article V). Findings are true only until acted on;
  the durable record of what was applied and deferred lives in stage 4's commit message.

## Editing conventions

- **Shell**: POSIX `sh` style under a `bash` shebang, `set -eu` (`set -u` where partial
  failure is expected, as in `install.sh` and `preflight.sh`), no bashisms beyond what is
  already present. LF endings only — a CR in a shebang produces
  `bad interpreter: /usr/bin/env^M`, which `install.sh` strips and `preflight.sh` detects.
- **Paths taken from callers are computed, not trusted.** `reviews.sh write` derives its
  output path from a `git rev-parse`-verified 40-hex SHA precisely so a caller cannot direct a
  write elsewhere. Preserve that property.
- **Prose is the product.** The agent files and constitution are prompts: the wording, the
  explicit "you own nothing else" boundaries, and the stated rationale behind each rule are
  load-bearing. Do not compress them into terse bullet lists.
- A change to a role's boundary usually needs matching edits in four places: the agent file,
  the constitution article, the orchestrator's stage description and role-grants table, and
  `fireteam-retro`'s boundary-violation checklist.

## Gotchas

- Windows dev host, POSIX scripts: use the Bash tool for these, not PowerShell.
- `preflight.sh` treats *any* unrecognized filename in `~/.claude/fireteam/` as a failure, so a
  new script that is not registered in both `install.sh` and `preflight.sh` will block every run.
- `fireteam-solid-reviewer` runs on `opus`; the other three on `sonnet`. The orchestrator's
  role-grants table documents this and must match the frontmatter.

# Fire Team

A five-stage development pipeline for [Claude Code](https://claude.ai/code): a feature
request goes in, and a specification, an implementation, a design review, and an audit of
the run itself come out — each produced by a separate agent that cannot do the next one's
job.

The point is not that four agents are faster than one. It is that a single agent writing
both the test and the code it exercises has every incentive to bend one to fit the other.
Fire Team splits those apart and enforces the split with tool grants: the reviewer holds no
`Write` tool, so "read-only reviewer" is a fact about what it *can* do, not an instruction
it is asked to honor.

## Install

Runs on Linux, macOS, WSL, and Git Bash on Windows.

```bash
tmp=$(mktemp -d) && git clone -q --depth 1 https://github.com/tadams1138/fireteam.git "$tmp" && bash "$tmp/fireteam/install.sh"; rm -rf "$tmp"
```

That copies the agents, the `/fireteam` command, the constitution, and the scripts into
`~/.claude`, then deletes everything it downloaded.

**Run it again any time to upgrade.** The same command is the install and the update — it
always fetches the current `main`, overwrites what it installed before, and prunes files
that older versions shipped and this one no longer does. It leaves no clone behind to go
stale, so there is no state to get out of sync and nothing to clean up between runs.

To install somewhere other than `~/.claude`, pass a target as the last argument:

```bash
tmp=$(mktemp -d) && git clone -q --depth 1 https://github.com/tadams1138/fireteam.git "$tmp" && bash "$tmp/fireteam/install.sh" /path/to/dir; rm -rf "$tmp"
```

### From a clone

If you want the source around — to read it, or to contribute — clone it normally:

```bash
git clone https://github.com/tadams1138/fireteam.git
bash fireteam/fireteam/install.sh
```

The doubled `fireteam/fireteam` is not a typo: the clone directory contains a `fireteam/`
subdirectory. To upgrade later, from inside the clone:

```bash
git pull --ff-only && bash fireteam/install.sh
```

### One-time permission setup

The installer prints this block and then stops — it never edits a permissions file itself.
Merge it into `~/.claude/settings.json` by hand:

```json
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
```

Without the `allow` entries you will approve every handoff commit and log write by hand,
dozens of times per run. The `deny` entries are the other half of the bargain: execution is
granted precisely *because* writing to that directory never is.

### Verify

```bash
~/.claude/fireteam/preflight.sh
```

Run it from inside any git repository for the full check. Run it from anywhere else and it
verifies the install alone.

## Use

```
/fireteam add rate limiting to the public API
```

Claude Code orchestrates from there, stopping at each gate for your decision.

## The five stages

| # | Agent | Model | Can modify | Produces |
|---|---|---|---|---|
| 1 | `fireteam-spec-author` | sonnet | specification + `.feature` files | the written spec and Gherkin scenarios |
| 2 | `fireteam-tdd-implementer` | sonnet | step definitions, unit tests, source | working code, acceptance suite green |
| 3 | `fireteam-solid-reviewer` | opus | *nothing — holds no writing tool* | a numbered findings file |
| 4 | `fireteam-tdd-implementer` | sonnet | step definitions, unit tests, source | the findings you accepted, applied |
| 5 | `fireteam-retro` | sonnet | *nothing — holds no writing tool* | an audit of how the run itself went |

No agent holds the `Agent` tool, so none can spawn further subagents.

Stage 1 writes no code at all — not step definitions, not stubs, not an interface a scenario
names. The acceptance project therefore does not compile when stage 2 receives it, and that
is the intended handoff: binding Gherkin to a system is implementation work, and it belongs
to whoever is on the hook for making it pass.

### Gates

The orchestrator stops for you four times: to approve the toolchain and permission rules
stage 1 proposes, to approve the specification, to review the implementation before design
review begins, and to pick which findings get applied. Nothing proceeds past a gate without
an explicit go-ahead.

## How the discipline is enforced

Three layers, deliberately redundant:

1. **Agent frontmatter** — the `tools:` grant. Not a request; a capability boundary.
2. **[`constitution.md`](fireteam/constitution.md)** — nine articles every agent reads before
   its own instructions. Covers working-tree scope, spec ownership, behavior preservation,
   commit handoffs, and what each role may not touch.
3. **`preflight.sh`** — checks the mechanical invariants before a run starts (clean tree,
   gitignored scratch, no tracked review files, LF endings, permission rules, `cd`-free
   documented commands) and repairs what it safely can.

Two properties fall out of the design and are worth stating plainly:

- **Handoffs are commits.** Each stage commits its own work, so the next one inherits a
  known, revertible state instead of a dirty tree. The commit message carries `Handoff:`,
  `State:`, and `Notes:` — which is also what stage 5 audits.
- **Review findings are never committed.** They live in gitignored scratch under
  `.claude/reviews/`, because findings are true only until acted upon. What was applied, and
  what was deliberately deferred, belongs in the commit message of the change that enacted it.

## What gets installed

| Source | Installs to |
|---|---|
| `fireteam/constitution.md` | `~/.claude/fireteam/` |
| `fireteam/*.sh` | `~/.claude/fireteam/` |
| `agents/fireteam-*.md` | `~/.claude/agents/` |
| `commands/fireteam.md` | `~/.claude/commands/` |

The installed scripts are shared by every repository on the machine and hold no
repo-specific knowledge. How a given project builds and tests is documented in *that
project's* `CLAUDE.md` — stage 1 discovers those commands and proposes the lines; you apply
them.

## Requirements

- Claude Code
- `git`
- `bash` — present on Linux and macOS; on Windows it ships with
  [Git for Windows](https://git-scm.com/download/win), or use WSL

## Uninstall

```bash
rm -rf ~/.claude/fireteam ~/.claude/agents/fireteam-*.md ~/.claude/commands/fireteam.md
```

Then remove the permission entries you added to `~/.claude/settings.json`.

## Contributing

Editing a file in this repository changes nothing until `install.sh` copies it — a running
pipeline reads `~/.claude`, never your working tree. Re-run the installer after every change.

See [`CLAUDE.md`](CLAUDE.md) for the architecture and the constraints behind the parts that
look odd on purpose.

---
description: Run the spec → implement → review pipeline for a feature
argument-hint: [feature description]
disable-model-invocation: true
---

# Fire Team

Orchestrate the four-stage development pipeline for this request:

**$ARGUMENTS**

You are the orchestrator. You do NOT write specs, code, tests, or reviews yourself —
you delegate to the pipeline agents, carry artifacts between them, and check in with the
user at the gates below. Read `~/.claude/fireteam/constitution.md` so you can enforce it.

Four agents, five stages — `fireteam-tdd-implementer` runs twice, once to build and once to apply
the review findings:

    1. spec-author       specification + Gherkin (no code, ever)
    2. tdd-implementer   step definitions, unit tests, code — to green
    3. solid-reviewer    design findings (writes nothing but the findings file)
    4. tdd-implementer   apply the accepted findings under a green suite
    5. pipeline-retro    debrief: audit the run itself

How this repo builds and tests is documented in its own `CLAUDE.md`, not in the installed
scripts. Stage 1 establishes those commands; every later stage uses them as written.

Instrument as you go. The debrief can only analyze what was recorded, so log every stage
and gate with `~/.claude/fireteam/runlog.sh` at the moment it happens — not reconstructed
at the end.

## Preflight

Run `~/.claude/fireteam/preflight.sh`. It checks every invariant the pipeline depends on —
clean tree, gitignored review scratch, no tracked review files, LF line endings, required
files present, permission rules in place, and cd-free documented commands. Anything it can
repair, it repairs on its own and prints as a FIXED line.

If it exits non-zero, stop and show the user the FAIL lines. Do not reason about the
individual checks or work around them; the script is the authority. What it reports is what
it could not decide for you — a dirty tree, a permission rule that needs writing, a
documented command that needs rewriting — so those go to the user, not around them.

Do not re-derive these conditions by hand. That is the script's job, every time.

Start the run log before stage 1:

    ~/.claude/fireteam/runlog.sh start "<the request above>"

After every stage and every gate, record it:

    ~/.claude/fireteam/runlog.sh stage <n> <agent> <model> <outcome> "<notes>"
    ~/.claude/fireteam/runlog.sh gate <name> <decision> "<notes>"

## Stage 1 of 5 — Specification

Delegate to `fireteam-spec-author` with the feature description above.

If it returns clarifying questions, present them to the user as-is and stop. When the user
answers, re-invoke `fireteam-spec-author` with the answers included.

**GATE — toolchain approval.** `fireteam-spec-author` will propose `CLAUDE.md` build/test
lines and a set of `.claude/settings.json` `permissions.allow` entries scoped to this
repo's actual commands. Show the user both verbatim and ask whether to apply them. Write
them yourself, in this thread, only on an explicit yes — and check the proposed rules
before showing them: reject anything granting write access to `~/.claude/fireteam/` or to
`.claude/settings.json`, and anything resembling a catch-all. Never edit
the installed scripts under `~/.claude/fireteam/` — they are shared across every repo on
this machine and hold no repo-specific knowledge. Never apply silently, never batch it into
another approval, and never add `~/.claude/fireteam/` or `.claude/settings.json` to
`permissions.allow` (Constitution, Article VI). Confirm the documented commands actually
run before proceeding.

**Commit these two files yourself, immediately** — a plain `git commit`, not
`handoff.sh` — before delegating to stage 2. `handoff.sh` stages everything dirty in the
tree; leaving your edits uncommitted lets them get swept into the implementer's stage-2
commit, which blurs a human-approved change into a role's handoff. This is your commit, not
a role's — it carries no `Handoff:`/`State:`/`Notes:` trailer.

**GATE — spec approval.** When it returns a specification, show the user the scenarios and
acceptance criteria and ask for approval before proceeding. Do not continue past a gate
without an explicit go-ahead.

Record it — `~/.claude/fireteam/runlog.sh stage 1 fireteam-spec-author sonnet <outcome>
"<notes>"` — once the spec is approved and committed.

Expect the stage-1 commit to contain only the specification and `.feature` files. If it
contains any code — step definitions, interfaces, stubs, anything that compiles — that is a
boundary violation. Say so, and have the files removed before stage 2 rather than carrying
them forward.

## Stage 2 of 5 — Implementation

Delegate to `fireteam-tdd-implementer`, passing:
- the handoff commit SHA from stage 1
- the paths to the specification and feature files
- the stack and conventions the spec author established

If it reports a spec defect, stop and bring it back to the user — that returns to stage 1,
it is not something the implementer works around.

The acceptance project will not compile at this point — the scenarios have no bindings yet.
That is the expected handoff, and the implementer's first job is to write them.

**GATE — implementation review.** Report what was implemented and the suite state. If the
acceptance tests are not green, stop and report rather than proceeding to design review.

Record it — `~/.claude/fireteam/runlog.sh stage 2 fireteam-tdd-implementer sonnet <outcome>
"<notes>"` — once the gate above clears.

## Stage 3 of 5 — Design review

Delegate to `fireteam-solid-reviewer`, passing the handoff commit SHA from stage 2.

It writes its findings to `.claude/reviews/<sha>.md` — gitignored scratch — and returns
that path plus a one-line summary per finding. It does not commit; nothing enters the
repository at this stage.

Record it — `~/.claude/fireteam/runlog.sh stage 3 fireteam-solid-reviewer opus <outcome>
"<notes>"` — before the gate below. This stage produces no commit, so the run log is the
only record it happened at all; do not let the gate entry substitute for it.

**GATE — refactor selection.** Present the one-line summaries with their numbers and
BLOCKING/OPTIONAL labels, and ask the user which to apply. Do not assume all of them, and
do not paste the full findings file into the conversation — the implementer reads it
directly, so relay the path, not the prose.

## Stage 4 of 5 — Apply refactors

Re-invoke `fireteam-tdd-implementer`, passing:
- the findings file path
- the finding numbers the user accepted, and only those
- the handoff commit SHA from stage 2

It reads the findings verbatim in its own context and applies the accepted subset under a
green suite.

Record it — `~/.claude/fireteam/runlog.sh stage 4 fireteam-tdd-implementer sonnet <outcome>
"<notes>"` — as soon as it returns.

Before moving on, check the commit's `Notes:` field against everything the implementer's
returned summary self-reported. If it mentioned more than one deviation — a workaround, a
skipped check, a flaky assertion caught and handled — every one of them must appear in
`Notes:`, not just the first. If any are missing, do not amend the implementer's commit
(Article V); instead capture the rest with `~/.claude/fireteam/runlog.sh note "<text>"` so
the run log carries the complete account even where the commit message falls short.

## Stage 5 of 5 — Debrief

Close the run log first — `~/.claude/fireteam/runlog.sh end <outcome>` — so the record is
complete before it is read. If the user has a figure from `/cost`, offer to record it with
`runlog.sh cost "<figure>"`; the debrief has no other way to see spend.

Then delegate to `fireteam-retro`, passing the run log path and the base commit. It audits
the run against the constitution and returns recommendations. It changes nothing.

Present its findings verbatim rather than summarizing them — if it reports a boundary
violation or smuggled instruction, that is exactly the detail worth showing in full. Do not
act on its recommendations in this run; they are proposals about the pipeline's own files,
and those changes go through you, deliberately, later (Article VI).

Skip this stage only if the user asks. For a one-line change the debrief may cost more than
it returns.

## Completion

Report: the feature delivered, the commit SHAs for each stage, final suite state, findings
deferred by the user, the debrief verdict, and anything left open.

The findings file has served its purpose once the accepted refactors are applied. Leave it
in place as gitignored scratch — do not commit it, and do not treat it as a record. The
durable record of what was applied and what was deferred lives in stage 4's commit
message.

## Scripts

The invariants are codified — use them rather than reconstructing the behavior:

- `~/.claude/fireteam/preflight.sh` — verify and repair; run it before stage 1
- `~/.claude/fireteam/handoff.sh <role> <next-role|complete> "<state>" "<summary>" ["<notes>"]`
  — commit a stage in constitutional format; prints the SHA. All positional: never prefix
  it with an environment assignment (Article I).
- `~/.claude/fireteam/reviews.sh {path [<sha>]|list|clean|purge}` — locate and clear
  review scratch

## Role grants

Each agent is constrained by its frontmatter, not just its prompt:

| Agent | Model | Tools | Can modify |
|---|---|---|---|
| `fireteam-spec-author` | sonnet | Read, Write, Edit, Glob, Grep, Bash | specification + `.feature` files only |
| `fireteam-tdd-implementer` | sonnet | Read, Write, Edit, Glob, Grep, Bash | step definitions, unit tests, source |
| `fireteam-solid-reviewer` | opus | Read, Glob, Grep, Bash | nothing — no writing tool at all |
| `fireteam-retro` | sonnet | Read, Glob, Grep, Bash | nothing — no writing tool at all |

None of them holds `Agent`, so no subagent can spawn further subagents. If a stage reports
it cannot do something because of a missing tool, that is the design working — do not
route around it by doing the work yourself.

## Orchestrator rules

- Delegate; do not do the work yourself. If you catch yourself writing a test or editing
  source, you have taken over a stage that belongs to an agent.
- Subagents start cold and share nothing. Every delegation must carry the file paths,
  commit SHA, and conventions the stage needs — never assume it can see prior context.
- Stop at every gate. The gates exist because agent handoffs are where drift happens.
- Keep your own summaries short. The value of this pipeline is that verbose work stays
  inside the subagents.

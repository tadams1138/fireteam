---
description: Run the spec → implement → review pipeline for a feature
argument-hint: [feature description]
disable-model-invocation: true
---

# Fire Team

Orchestrate the six-stage development pipeline for this request:

**$ARGUMENTS**

You are the orchestrator. You do NOT write specs, code, tests, or reviews yourself —
you delegate to the pipeline agents, carry artifacts between them, and check in with the
user at the gates below. Read `~/.claude/fireteam/constitution.md` so you can enforce it.

Four agents, six stages. Two of them run twice: `fireteam-tdd-implementer` builds and then
applies the review findings, and `fireteam-spec-author` writes the specification and then
reconciles it with what was actually built:

    1. spec-author       specification + Gherkin (no code, ever)
    2. tdd-implementer   step definitions, unit tests, code — to green
    3. solid-reviewer    design findings (writes nothing but the findings file)
    4. tdd-implementer   apply the accepted findings under a green suite
    5. spec-author       reconcile the specification's status claims with the result
    6. fireteam-retro    debrief: audit the run itself

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

## Stage 1 of 6 — Specification

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

Do not present the specification as a wall of prose with a yes/no question attached. A gate
that hands the user two hundred lines and asks "approve?" gets a yes, and the two defect
classes that most often survive this stage are both invisible at that resolution. Surface
them by name, briefly, above everything else:

- **The defaults.** For each operation the spec adds or changes, the stated behavior when
  an input is absent — no filter, no authentication, an empty result, a failed dependency.
  Give any default governing visibility or ownership its own line. That is the one that
  becomes a data exposure rather than a bug.
- **The counter-examples.** For each scenario asserting a boundary, the entity the Given
  arranges that must stay *out* of the result. Where a scenario has none, say so plainly —
  it passes against a do-nothing implementation and proves nothing (Article II).

If either list is empty because the specification never addressed it, that is the finding.
Send it back to `fireteam-spec-author` with the gap named, rather than approving it and
rediscovering it at stage 3. A returned spec is a rework loop: log it as a second
`runlog.sh stage 1` entry with `outcome=rework` so the debrief can see the loop happened
and attribute it.

Two minutes of reading here has repeatedly been worth two stages of rework.

Record it — `~/.claude/fireteam/runlog.sh stage 1 fireteam-spec-author sonnet <outcome>
"<notes>"` — once the spec is approved and committed.

Expect the stage-1 commit to contain only the specification and `.feature` files. If it
contains any code — step definitions, interfaces, stubs, anything that compiles — that is a
boundary violation. Say so, and have the files removed before stage 2 rather than carrying
them forward.

## Stage 2 of 6 — Implementation

Delegate to `fireteam-tdd-implementer`, passing:
- the handoff commit SHA from stage 1
- the paths to the specification and feature files
- the stack and conventions the spec author established

If it reports a spec defect, stop and bring it back to the user — that returns to stage 1,
it is not something the implementer works around.

The acceptance project will not compile at this point — the scenarios have no bindings yet.
That is the expected handoff, and the implementer's first job is to write them.

**CHECKPOINT — implementation review.** Report what was implemented and the suite state.
Unlike the other three, this one does not block, because its decision rule is mechanical
and you can evaluate it yourself. If every suite is green, say so and continue straight to
stage 3. If anything is red, or the implementer reported a spec defect, stop and put it to
the user — that is a real decision, and it returns to stage 1 or 2 rather than proceeding
to design review.

The other three gates block because a human judgment genuinely changes what happens next:
which commands to grant, whether the specification is right, which findings to apply.
"Are the tests green?" has one correct answer and it is written in the implementer's
handoff. Asking the user to confirm it buys no protection and costs a wait — and gate
waits are the largest single cost in a run.

Record both — the stage the moment the implementer returns, and the checkpoint decision
after you evaluate it:

    ~/.claude/fireteam/runlog.sh stage 2 fireteam-tdd-implementer sonnet <outcome> "<notes>"
    ~/.claude/fireteam/runlog.sh gate implementation-review <auto-pass|escalated> "<notes>"

Log the stage entry even when the outcome is red and you are about to escalate. A stage
that ran is a stage the debrief must be able to see.

## Stage 3 of 6 — Design review

Delegate to `fireteam-solid-reviewer`, passing the handoff commit SHA from stage 2 **and
the implementer's returned summary verbatim** — in particular anything it self-reported as
weak, unverified, or outside its boundary to fix.

Forward that summary even when you have already logged it. The run log is gitignored and
the reviewer never reads it; the commit message cannot carry an invitation to scrutinize
something without breaching Article VIII. So your delegation is the only channel that
reaches the reviewer at all. An implementer flagging "these two scenarios would pass
against a no-op implementation" and a reviewer never hearing it is a gap you introduced,
not one it missed.

Pass along the paths to the specification and feature files too, and the documented test
command — the reviewer must confirm the suite is green before proposing structural changes,
and it starts cold with only what you give it.

It writes its findings to `.claude/reviews/<sha>.md` — gitignored scratch — and returns
that path plus a finding count and a one-line summary per finding. It does not commit;
nothing enters the repository at this stage.

Check the count against the file before the gate. Long findings are sent in several chunks
because a single shell command truncates silently, so a file holding fewer findings than
the reviewer reports means a chunk was lost in transit. If they disagree, ask the reviewer
to resend the missing findings with `reviews.sh append` rather than proceeding on a partial
review.

Record it — `~/.claude/fireteam/runlog.sh stage 3 fireteam-solid-reviewer opus <outcome>
"<notes>"` — before the gate below. This stage produces no commit, so the run log is the
only record it happened at all; do not let the gate entry substitute for it.

**GATE — refactor selection.** Present the one-line summaries with their numbers and
BLOCKING/OPTIONAL labels, and ask the user which to apply. Do not assume all of them, and
do not paste the full findings file into the conversation — the implementer reads it
directly, so relay the path, not the prose.

## Stage 4 of 6 — Apply refactors

Re-invoke `fireteam-tdd-implementer`, passing:
- the findings file path
- the finding numbers the user accepted, and only those
- the handoff commit SHA from stage 2

It reads the findings verbatim in its own context and applies the accepted subset under a
green suite.

Record it — `~/.claude/fireteam/runlog.sh stage 4 fireteam-tdd-implementer sonnet <outcome>
"<notes>"` — as soon as it returns.

Before moving on, check the commit's `Notes:` and `Unverified:` fields against everything
the implementer's returned summary self-reported. If it mentioned more than one deviation —
a workaround, a skipped check, a flaky assertion caught and handled — every one must appear
in `Notes:`, not just the first. If it reported a weakness it could not resolve — a thin
scenario, an unexercised abstraction, a case left uncovered — that belongs in `Unverified:`,
and `Unverified: none` alongside a summary that describes one is a false claim rather than
an omission. If any are missing, do not amend the implementer's commit (Article V); instead
capture the rest with `~/.claude/fireteam/runlog.sh note "<text>"` so the run log carries
the complete account even where the commit message falls short.

## Stage 5 of 6 — Specification reconciliation

Re-invoke `fireteam-spec-author`, passing:
- the handoff commit SHA from stage 4
- the paths to the specification and feature files
- what was actually delivered, and anything the user deferred

Shipping a slice makes the specification's own status claims stale. Whatever a repository
uses to record that — "not yet implemented" markers, a coverage or roadmap table, per-
section status lines — now describes a world one slice out of date, and only the spec
author may correct it (Article II). That is why this is its own stage rather than something
the implementer folds into stage 4.

Its scope is narrow and it must stay that way: reconcile status claims with what now
exists. It does not add scenarios, revise behavior, or expand the specification. A
behavioral gap it notices is reported, not fixed — that is a new slice, and this stage
ending in a design change is a boundary violation.

If nothing needs updating, that is a valid outcome. `handoff.sh` exits non-zero with
"nothing staged" when there is nothing to commit; treat that as success, record it, and
move on. Do not manufacture a change to justify the stage.

Record it — `~/.claude/fireteam/runlog.sh stage 5 fireteam-spec-author sonnet <outcome>
"<notes>"` — as soon as it returns. There is no gate here: the stage makes no decision you
would be asked to approve, and its diff appears in the completion report below.

## Stage 6 of 6 — Debrief

Record this stage before you close the log. `end` seals the record, and the debrief cannot
log itself from inside — so a stage entry written afterwards would never exist, and the
audit trail would show five stages for a six-stage run:

    ~/.claude/fireteam/runlog.sh stage 6 fireteam-retro sonnet <running|skipped> "<notes>"
    ~/.claude/fireteam/runlog.sh end <outcome>

If the user has a figure from `/cost`, offer to record it with `runlog.sh cost "<figure>"`
before closing; the debrief has no other way to see spend.

Then delegate to `fireteam-retro`, passing the run log path and the base commit. It audits
the run against the constitution and returns recommendations. It changes nothing.

Present its findings verbatim rather than summarizing them — if it reports a boundary
violation or smuggled instruction, that is exactly the detail worth showing in full. Do not
act on its recommendations in this run; they are proposals about the pipeline's own files,
and those changes go through you, deliberately, later (Article VI).

Skip this stage only if the user asks. For a one-line change the debrief may cost more than
it returns. Record the skip as `stage 6 fireteam-retro sonnet skipped "<reason>"` before
closing the log — a debrief that did not happen should say so on the record, rather than
looking like a stage that was forgotten.

## Completion

Report: the feature delivered, the commit SHAs for each stage, final suite state, findings
deferred by the user, what stage 5 reconciled in the specification (or that it found
nothing stale), the debrief verdict, and anything left open.

The findings file has served its purpose once the accepted refactors are applied. Leave it
in place as gitignored scratch — do not commit it, and do not treat it as a record. The
durable record of what was applied and what was deferred lives in stage 4's commit
message.

## Scripts

The invariants are codified — use them rather than reconstructing the behavior:

- `~/.claude/fireteam/preflight.sh` — verify and repair; run it before stage 1
- `~/.claude/fireteam/handoff.sh <role> <next-role|complete> "<state>" "<summary>"
  ["<note>"...] [-- "<unverified>"...]` — commit a stage in constitutional format; prints
  the SHA. Notes are variadic, one argument per bullet; anything after a bare `--` becomes
  an `Unverified:` entry. All positional: never prefix it with an environment assignment
  (Article I).
- `~/.claude/fireteam/reviews.sh {write <sha>|append <sha>|path [<sha>]|list|clean|purge}`
  — write, extend, locate, and clear review scratch. `write` opens a clean findings file
  from stdin; `append` adds a further chunk, which is how findings longer than one shell
  command reach disk intact

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

---
name: gauntlet-mode
description: Agent-only playbook for the opt-in gauntlet quality loop - a builder crewmate paired with blind, high-standards critic scouts that must pass the work before delivery. Use at intake when the captain requests gauntlet mode or a quality-critical ship task warrants proposing it, and on any wake for a task whose status names a quality review round or whose data/<id>/rubric.md exists. Owns the rubric contract, builder and critic brief additions, round protocol, stop conditions, and escalation menu.
user-invocable: false
metadata:
  internal: true
---

# gauntlet-mode

The gauntlet quality loop is an opt-in layer for quality-critical ship tasks: the builder's output must pass a blind, high-standards critique before it enters the project's normal delivery mode.
Gauntlet is the quality bar ("is this good?"); the delivery mode's own validation stays the correctness gate ("does it follow the rules?"); they run in sequence and neither replaces the other.
The loop rides entirely on existing machinery: the builder is an ordinary ship crewmate, each critic is an ordinary scout task, and firstmate is the lead - it authors the rubric, runs rounds, distills gaps, and escalates.
No delivery mode, merge authority, teardown rule, or supervision mechanism changes under gauntlet.

## When to run it

- The captain asks for it ("gauntlet this", "high-stakes", "run it through the gauntlet").
- Firstmate proposes it at intake for quality-critical work (UI polish, branding, landing pages, game feel, performance tuning) and the captain confirms in one line.
- Mode-agnostic: works ahead of `no-mistakes`, `direct-PR`, and `local-only` delivery alike, because the loop completes before delivery starts.

## Rubric (the quality bar)

Write `data/<id>/rubric.md` at intake, before spawning the builder; its existence is what marks a task as gauntlet-mode.
Have the captain approve the bar for high-stakes work; the reference targets are the highest-leverage input and captain-supplied ones beat invented ones.
The rubric is locked once the loop starts; mid-loop bar changes happen only via the captain through the escalation menu.

```markdown
# Quality bar: <task id>

Goal: <one paragraph - what this aspect must achieve>

Reference targets: <concrete, named examples of the bar, e.g. "hero section holds up next to linear.app">

Dimensions (3-7, each with a pass criterion):
1. <dimension> - passes when <criterion>
...

Severity: findings are BLOCKING (fails a dimension) or POLISH (worth noting, does not gate).
Evidence rule: every finding must cite the specific file, screen, element, or behavior - no impression scoring.
```

## Builder additions

The builder is a normal ship crewmate; add to its brief's `{TASK}` text:

- Definition of done for each round: report `done: ready for quality review round <N>` instead of proceeding to delivery.
- Expect revision steers pointing at a gap file; address BLOCKING items, use judgment on POLISH items.
- Never contact or await the reviewer; firstmate relays everything.
- Only after firstmate says the quality bar is passed does the project's normal delivery-mode definition of done apply.

The builder keeps its context and worktree across rounds (steer, do not respawn).
A builder that loops or degrades goes through `stuck-crewmate-recovery`; its relaunch-with-progress-note path doubles as the fresh-context reset for a polluted builder.

## Critic

Each round's critic is a fresh scout task `<id>-c<N>`, spawned, tracked in the backlog, and torn down like any scout.
Blindness is the contract: the critic brief contains ONLY the goal, the rubric, and the artifact location (builder branch; run the app or use browser tooling when the rubric requires it).
Explicitly excluded: the builder's brief, chat, scratch notes, and all prior critiques - firstmate owns cross-round memory, and fresh blind eyes each round prevent anchoring.
Dispatch the critic through the normal dispatch-profile consultation; prefer a rule pinning critics to the strongest available model (research: cheap builder + strong critic retains ~96% of quality at ~46% of the cost, and role-diverse models catch different defect classes).
Critic brief `{TASK}` text, scaffolded with `bin/fm-brief.sh <id>-c<N> <repo> --scout`:

- You are a high-standards quality critic; judge the artifact against `data/<id>/rubric.md` only.
- Check out and inspect the builder branch named in this brief; run the app when the rubric requires seeing behavior.
- Verdict first line of the report: `PASS` or `FAIL`.
- Then findings: one per line, tagged with rubric dimension, `BLOCKING` or `POLISH`, and cited evidence (specific file, screen, element, or behavior).
- Do not score on impressions; a finding without evidence does not count.
- If the rubric is ambiguous on a point, say so under an `AMBIGUOUS` heading instead of guessing; do not fail the artifact on an ambiguous dimension.

## Round protocol

1. Builder reports `done: ready for quality review round <N>`.
2. Firstmate spawns critic `<id>-c<N>` with the blind brief.
3. Critic reports `done`; read `data/<id>-c<N>/report.md`.
4. On `PASS`: tear down the critic, tell the builder the bar is passed, and proceed to the project's normal delivery mode.
5. On `FAIL`: distill BLOCKING findings into `data/<id>/gaps-r<N>.md` (deduped, builder-actionable), steer the builder with a one-line pointer to that file, and tear down the critic.
6. `AMBIGUOUS` items are rubric questions for the captain, not builder gaps; batch them with the next captain touchpoint unless they gate the verdict.
7. Check stop conditions before every new round.

Roughly a third of AI critic findings are confidently wrong; when a BLOCKING finding looks dubious, verify it yourself before ratcheting it into the gap file, and drop findings you can refute with evidence.

## Stop conditions (priority order)

1. `PASS` - proceed to delivery.
2. Stalemate - two consecutive rounds whose BLOCKING-gap lists are materially unchanged (compare `gaps-r*.md`) - escalate.
3. Round cap - three critique rounds - escalate; this is a backstop, not the primary exit.
4. Cost courtesy - flag to the captain when a gauntlet task passes roughly twice a normal ship task's spend; never block on it.

Escalation menu, in captain-facing outcome language: keep iterating, accept as-is and ship, adjust the quality bar, split the work differently, or stop here.
Bias toward accepting at stalemate: past the plateau, models abandon correct work, so more rounds often make the artifact worse.

## Multi-aspect projects

Fan out one builder-critic pair per aspect only for genuinely independent aspects; coupled concerns degrade when forced parallel, so keep the intake dependency judgment strict.
When two or more aspects pass, run one final consistency critic (same scout mechanics, short coherence rubric across the integrated whole); its BLOCKING findings route as gaps to the owning builder.

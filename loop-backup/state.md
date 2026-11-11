# dsx-ai-factory/nvke loop-kit — triage state

> The loop's **memory** on disk. Lives at `<repo>/.loop/state.md`, deliberately outside `.claude/`
> (the harness blocks unattended writes there) and git-excluded locally. Each round resumes from
> here; humans act on **Actionable**. Don't hand-edit during a run.
>
> **Screening discipline:** `~/source/nvke-study/RESEARCH-WORKFLOW.md`. Availability != actionability.
> nvke merges ~11 PRs/day: **re-verify any verdict from an earlier round before using it.**
> Important conclusions are mirrored into `~/source/nvke-study` (this directory has no remote).

## Actionable
_Proposals that passed the independent skeptic evaluator. Ready for a human._

_None yet._ Round 1 (bootstrap) found no candidate verified actionable for code.

## Comment-sized candidates (not yet through the skeptic)

- **#2022** -- DONE: our PR #2282 is open (closes it); comment posted. Do not re-propose.

## Parked
- **#1177** providers: CONFIGURED doesn't prove the provider works -- bullet 1 shipped in #1602; the rest
  needs a Product ruling (absent provider -> hard create error?). Re-look when a Product answer appears.
- **#2194 epic + #2195-#2221, #2212** (28 os-image issues, one author, filed 2026-11-07, 0 comments) -- one
  owner's plan. Read the epic before screening any child.
- **#2023, #2104 "main is red"** -- automation-filed CI noise, not contributions.
- **danbudris 2026-11-10 batch** #2266 #2267 #2269 #2270 #2271 -- siblings #2263/#2264/#2265/#2268 had PRs within
  hours. Re-look in ~1 week.

## Done / Taken (do not re-propose)
See `~/source/nvke-study/tools/known-taken.txt` (round 1: 15 of 17 screened issues taken or claimed).

## Round log

### Round 0 -- bootstrap, 2026-11-11 (upstream `487f5110`)
- Measured: 121 open issues / 110 unassigned / 82 open PRs (24 reference no issue) / 150 merged in 14 days.
- Screened 17/110. Verdicts: 9 TAKEN with closing-keyword PR, 2 claimed, 4 TAKEN? (adjacent PR, diff unread),
  1 entangled (#2022), 1 needs ruling (#1177).
- Not yet run: a real `loop-run.sh` round (see `~/source/nvke-study/HANDOFF.md`).

# Screening coverage ledger

Honest accounting of what has and hasn't been screened. `screen-issues.sh --limit N` is a
**sample**, not coverage; this file says what it never reached.

**Measured 2026-11-11** (`gh issue list`, `gh api search/issues`, `tools/pr-index.sh --no-cache`,
upstream `dsx-ai-factory/nvke` at `487f5110`):

| Metric | Count |
|---|---|
| Open issues | 121 |
| Open **unassigned** issues | **110** |
| Screened with the four rules | **17** (15%) |
| **Never screened** | **93** ⚠️ |
| Verified actionable **for code** | **0** |
| Entangled with an open PR, comment is the deliverable | **1** (#2022) |
| Free but needs a Product ruling | **1** (#1177) |
| Open PRs | 82 |
| Open PRs referencing ≥1 issue | 58 |
| **Open PRs referencing NO issue** | **24** |
| Merged PRs in the trailing 14 days (since 2026-10-28) | **150** |
| `good first issue` / `help wanted` open | 4 / 4 |
| `needs-triage` (no priority yet) | 47 |

## ⚠️ This is round 1. Coverage is 15%, not "done"

Round 1 **deliberately sampled** the issues that look most like bounded newcomer work —
`bug`, `good first issue`, `help wanted` — to calibrate how fast this repo moves before
spending API budget on a sweep. Do not read the candidate list as "the available work"; read
it as "the available work among 17 of 110".

### What round 1 screened (17)

`#2265 #2268 #2264 #2248 #2067 #2058 #1177 #2263 #1369 #707 #1957 #2022 #2136 #609 #1242
#2002 #2021` — every `good first issue`, every `help wanted`, and the older `bug`-labelled
unassigned issues. Verdicts in `tools/known-taken.txt`.

| Verdict | Issues |
|---|---|
| TAKEN — open PR **with closing keyword** for this issue | #609 (#2231), #707 (#2234), #1369 (#2015, draft), #1957 (#1972), #2002 (#2004), #2058 (#2246), #2067 (#2184, draft), #2264 (#2272), #2268 (#2275) |
| TAKEN — claimed by comment / `/assign`, no PR yet | #2248 (`/assign`, scope agreed with triager), #2136 (claim wording in comments; claimant not yet read) |
| TAKEN? — open PR is topic-adjacent but has **no** closing keyword for it; PR diff **not read** | #1242 (#2164), #2263 (#2279), #2265 (#2272, #2279), #2021 (#2045) |
| Entangled (light) | #2022 — confirmed bug, P2, exact fix prescribed, no PR closes it; open PR #2072 (same author) renames `datahall`→`site-N` in the same package and adds **no** duplicate check (diff read) |
| Free, needs Product ruling | #1177 — bullet 1 shipped (#1602); remaining ask is "should an absent provider be a hard create error?" |

**Take rate: 15 of 17 (88%)** had a PR or claim. The verdict basis for the four `TAKEN?`
rows is weaker than the rest: they were classified from the cross-reference only.

### Never screened (93) — the first things to look at next

1. **28 `os-image` issues by one author** (#2195–#2221 + #2212, epic #2194; filed 2026-11-07;
   P1/P2; 0 comments). An epic breakdown by one owner. Read the epic first; expect them to be
   owner-reserved.
2. **The `danbudris` batch** #2266, #2267, #2269, #2270, #2271 (filed 2026-11-10, "willing to
   contribute" ticked). Siblings #2263–#2265/#2268 had PRs within hours; assume the same.
3. **`mchmarny` Oct-2 batch** (#1174–#1185, #565, #566): 13 issues (12 unscreened), 0–3 comments, ~40 days old,
   mostly `feature` — the oldest large cluster of unclaimed work. Highest-value next sweep.
4. **`lalitadithya` CLI feature requests** (#1368, #1390, #1401): #1368/#1390 are `AGING` claims
   (32d) per `claims.sh`; #1401 `ACTIVE`. Ask the claimant before anything.
5. **`feature` issues in general** (75 open) — Product-triaged; most need a ruling first.
6. **P0 trio**: #2023 and #2104 are "main is red" CI issues (transient, automation-filed,
   likely fixed); #2181 is a controller-API TLS feature by a maintainer.
7. **Docs-only** (#1089, #1626, #1993, #2244) — #2244 has a `/assign` claim.

### Not covered at all

- Closed issues and merged PRs (no obsolete-grep done for anything).
- Discussions (Q&A, NVKEP threads).
- The 58 open PRs that *do* reference an issue were only read through the index, not diff-by-diff.
- No candidate older than 3 months was obsolete-grepped (the oldest unclaimed issue is #520,
  2026-09-05, ~67 days; #1177's triage comment already says bullet 2 is partly stale — the
  pattern to expect).

## Sweep order for round 2

1. `git fetch upstream` + `pr-index.sh --no-cache --unreferenced` (stale in a day).
2. `mchmarny` batch (#1174–#1185, #565, #566) with R1–R4 and obsolete-grep.
3. #520, #609-adjacent bugs older than 30 days not yet seen (`area/controller` P2 bugs).
4. Read epic #2194 and decide whether any child is open to outsiders.
5. Re-check #2022 against #2072's diff, and #1177 for a Product answer.
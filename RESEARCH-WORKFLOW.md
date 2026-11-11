# Contribution Research Workflow — NVKE

The method carried over from `~/source/agent-sandbox-study` and `~/source/agent-router-study`,
plus what round 1 on this repo (2026-11-11) measured differently. Parts:

- **`tools/profile-repo.sh`** — probes the repo into `PROJECT-FACTS.md`. Run once per project, first.
- **`tools/pr-index.sh`** — PR→issue reverse index (§1a). **Run this before any issue screen.**
- **`tools/screen-issues.sh`** — availability screening (§1). Defaults to `--profile nvke`.
- **`tools/claims.sh`** — sweeps open issues for informal "I'll take this" claims (§1c).
- **`tools/review-plan.sh`** — adversarial review loop over a plan (§5).
- **This document** — the judgment the scripts cannot do.

**Pipeline:** profile → PR sweep → screen → read → plan → review-loop until converged →
verify findings → fold in → implement.

---

## 0. The one-line summary of the style

> **Never state anything you haven't verified against the code or the API, and never
> present a candidate you haven't screened. When you're wrong, say so plainly and fix
> the artifact.**

---

## 1. Availability screening — four rules (portable, do not delete)

| Rule | Check | Came from |
|---|---|---|
| **R1** | `cross-referenced` timeline PRs, regardless of closing keyword or assignee — **read** them, don't count them | agent-sandbox **#968**: four open PRs while looking unassigned |
| **R2** | The **last comment**, not the metadata | agent-sandbox **#225**: open + assigned + merged PR, finished and never closed |
| **R3** | The **body**, for author self-implementation (POC / fork / "willing to contribute") | agent-sandbox **#1157**: finished 14-commit POC on a fork, no PR |
| **R4** | **Every** comment, for PR announcements and maintainer rulings | agent-sandbox **#764**: *"Fixed in #1078. PTAL"* buried in a comment |

`AVAILABLE` / `HUMAN-REVIEW` / `TAKEN` are triage, not conclusions. **A `TAKEN` verdict from
R1 means "an open PR cross-references this" — read the PR to see whether it is the fix or
merely adjacent.** In round 1 of nvke, 4 of the 15 `TAKEN` verdicts rest on a PR that does
*not* carry a closing keyword for the issue (see `COVERAGE.md`), so they are recorded as
`TAKEN?` until the PR diff is read.

Also from agent-router (not yet seen on nvke, keep the habit): a merged cross-reference can
be the issue's **cause**, not its **cure** — decide the direction, then grep the tree.

## 1a. Invert rule 1 first — `tools/pr-index.sh`

```bash
tools/pr-index.sh --unreferenced          # PRs that name no issue
tools/pr-index.sh --grep 'regex'          # keyword sweep over title/body/branch
FORMAT=tsv tools/pr-index.sh --no-cache   # full issue→PR index
```

Measured 2026-11-11: **24 of 82 open PRs reference no issue** (29%). No issue-side screen can
see them. Evidence weight: body/title refs strong, branch refs weak (the very first row of
the index, `#13 ← #2278`, is a branch-name match on `…cluster-api-v1.13.7`: a version, not an
issue number).

⚠️ **Cache key.** `pr-index.sh` as copied from agent-sandbox keyed its cache on state only and
would have served another project's PR list. This copy includes the repo slug in the key.
Verified here by: total PR count from the tool (82) == `gh` search count (82).

## 1b. Screening economics on this repo — **fast**

| | agent-sandbox | agent-router | **nvke** |
|---|---|---|---|
| Open issues / unassigned | 137 / 78 | 143 / 135 | **121 / 110** |
| Open PRs | 78 | 142 | **82** |
| PRs referencing no issue | 20 | 43 | **24** |
| Merged PRs in 14 days | — | 44 (~3/day) | **150 (~11/day)** |
| `good first issue` / `help wanted` on open issues | in use | 0 / 0 | **4 / 4** |
| Take rate on the 17 best-looking candidates | — | 9/16 | **15/17 taken (9 with a PR that closes the issue)** |

Consequences:

1. **Age is a positive availability signal, recency is a negative one.** nvke merges ~11 PRs a
   day. The 17 screened issues were the ones that *look* like newcomer work (bugs,
   `good first issue`, `help wanted`); all but two already had a PR or a claim, and the
   freshest (filed 2026-11-10) already had PRs the same day (#2263/#2264/#2265/#2268 →
   #2272, #2275, #2279). **The reporter, usually a maintainer, files the issue and opens the
   fix within hours.** Do not screen issues younger than ~7 days except to learn what the
   maintainers are doing.
2. **A screen goes stale in a day or two, not a week.** At ~11 merges/day re-run
   `pr-index.sh --no-cache` before quoting any verdict that is older than the session.
3. **`good first issue` is not an on-ramp here.** Three of the four open `good first issue`
   issues are maintainer-filed and already have an open PR (#2264, #2268; #2265's two PRs are
   topic-adjacent and unread); the fourth (#2248)
   has a contributor assigned via `/assign`. Triage labelled them *after* a PR existed.
4. **Review capacity is the bottleneck** (82 open PRs; unvetted authors need `/ok to test`,
   see `PROJECT-FACTS.md`). A comment that unblocks a maintainer decision beats a speculative
   PR that joins the queue.
5. **Maintainer batches.** `danbudris` filed nine issues on 2026-11-10 (#2263–#2271; five of them,
   #2266/#2267/#2269/#2270/#2271, carry "willing to contribute"); `ayuskauskas` filed **28** `os-image` issues on 2026-11-07
   (#2195–#2221, epic #2194, all P1, 0 comments). Treat each batch as *one owner's plan*, not
   28 free issues. Unscreened — see `COVERAGE.md`.

### Availability ≠ actionability — five states

- **Taken** — someone is on it (PR, assignment, claim).
- **Entangled** — free, but a *specific open PR touches the same files*. Deliver a coordination
  comment, not a competing PR. (#2022 ↔ #2072.)
- **Blocked** — free but depends on unmerged work, possibly in another repo
  (`dsx-ai-factory/cluster-api-provider-nico`, NVKR, AICR are named in issues).
- **Obsolete** — free, unblocked, and already true on `main`. Grep before planning anything older
  than ~3 months; at ~11 merges/day that is ~1000 merges.
- **Actionable** — free, unblocked, still real, and testable here (§6).

## 1c. `tools/claims.sh` — and its nvke false positive

`claims.sh` greps bodies/comments for claim phrasing. On nvke **"willing to contribute"
matches the issue form's own checkbox text**, so five `danbudris` issues light up as
`ACTIVE`. That is not noise to discard: a maintainer ticking "willing to contribute" on
their own issue is an R3 signal ("the author intends to implement it"), and their sibling
issues #2263/#2264/#2265/#2268 did get a PR within hours. But it is a *template field*, not a claim comment — weight it below a
`/assign` or "I'll take this" comment.

## 2. What to plan, and in what order

nvke has a real priority ladder (`priority/P0..P2`, set by a triager; 47 of 121 open issues
are still `needs-triage`), but the ladder tracks *urgency to the team*, not *availability to
us*. Rank by:

1. **Maintainer-filed + old + still unclaimed** (age inverted, §1b).
2. **`bug` with a `file:line`-verifiable premise** over `feature` (23 vs 75 open). Features go
   through Product (`docs/issue-triage.md`), so they usually need a ruling first.
3. **Triaged by an engineer with an explicit fix recipe** (e.g. #2022: "build a map of
   `Endpoint()` → key, fail on a duplicate, add a trailing-slash table case").
4. **Skip `roadmap/exploring` / `[NVKEP]` issues** unless writing a proposal — they ask the
   community for input; a comment is the deliverable.
5. **Skip the epics** (#2194 family) until the owner says which children are open.

**Sometimes the deliverable is a comment**: confirm scope, offer to take a follow-up after an
in-flight PR, answer a Product question with evidence.

## 3. Plan file format

`plans/<issue-NNNN|roadmap>-<slug>.md`, in this order:

1. **Header** — issue link, labels, dates, and an **availability line naming the screens run**
   (incl. `pr-index.sh --unreferenced` and its date + upstream SHA).
2. **§0 blocker/claim notice** — taken / entangled / blocked / obsolete goes **first**.
3. **Background** — every claim has a `file:line` verified at a named SHA.
4. **Approach + alternatives table** — rejected options and why.
5. **File-by-file change list** — exact paths. If `controller/api/openapi.yaml` or a `.proto`
   is touched, say so and name the regenerate step; never plan a hand-edit of generated output.
6. **Test & verification plan** — exact commands (§6), and which tests will skip locally.
7. **PR mechanics** — Conventional-Commit title matching the live `main` rule (§6), `Closes:`
   line, DCO sign-off on every commit, verified signatures, AI-assistance note.
8. **Risks / open questions** — mark blocking ones 🚩.
9. **Work schedule** — with a gate before coding if a question blocks.
10. **Review sections** — appended audit record (§5).

## 4. Verify everything

- **Line references drift in hours.** ~11 merges/day. Quote symbols; re-check `file:line`
  against a named SHA in the same session.
- **The rename splits your search space.** Issues say `nkectl` / `nkecli` / `NKE` / `CWE` /
  `nke-stack`; the code says `nvkectl` / `NVKE`; env settings are still `NKE_CONTROLLER_*`.
  Search both spellings. See `PROJECT-FACTS.md` § *Identity*.
- **Thirteen Go modules in one workspace** (`go.work`). A grep hit means nothing until you know
  which module owns it, and the module's own `AGENTS.md` (controller, agent, cli, os-image,
  nktp) has its own toolchain rules.
- **Generated output is not source.** `controller/api/*.gen.go`, `agent/pkg/agent/proto/*.pb.go`,
  CRD/deepcopy/RBAC files, `THIRD_PARTY_NOTICES.md`: change the source and regenerate.
- **Tests are the spec.** controller tests ≈ controller implementation (131k vs 113k lines);
  cli tests are larger than its implementation (31.5k vs 24k).
- **Trace the whole call path** — an early return upstream can make a whole downstream design
  unreachable.
- **Follow cross-repo links** to current state. Blockers named in issues live in
  `cluster-api-provider-nico`, NVKR, AICR; an issue's description of them is as old as the issue.
- **Read the open PR's diff, not just its title**, before calling an issue taken *or* free.

## 5. The review loop — `tools/review-plan.sh`

```bash
tools/review-plan.sh --repo-dir /path/to/worktree plans/issue-NNNN-slug.md   # max 5 passes
tools/review-plan.sh --dry-run plans/issue-NNNN-slug.md                      # show prompt only
```

Stops after 2 consecutive passes with no High/Medium. Never edits the plan itself; ~1 in 6
findings was wrong on agent-sandbox, so verify each before folding it in. When findings
degrade into self-inconsistency from earlier revisions (typically pass 6), consolidate and stop.
`codex exec -s read-only` works headless; `claude -p` fails when nested in a live Claude Code
session — run it from a clean shell.

## 6. Repo-specific mechanics (verified 2026-11-11 against `CONTRIBUTING.md`, `AGENTS.md`, `.github/`)

Full detail in `PROJECT-FACTS.md` § *PR mechanics*. The ones that fail a PR before a human
reads it:

- **Fork workflow.** Push to `yuzhiquan/nvke`, PR from the fork, **never** a branch on
  `dsx-ai-factory/nvke`.
- **DCO:** `git commit -s` on **every** commit, org members included.
- **Verified signatures:** `main` has a `required_signatures` rule. `commit.gpgsign` is **not
  set** on this machine — set up signing before the first PR (§HANDOFF).
- **PR title = squash commit subject**, checked by a `commit_message_pattern` rule:
  `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9/_.-]+\))?!?: .+`.
  Branch commits are not checked.
- **Branch name** `<type>/<short-description>`. No JIRA prefix (`~/source` project).
- **`Closes #N` goes in the PR body** (template `Closes:` line). Open issue-first for anything
  non-trivial; PR #2240 (open) proposes making a linked issue mandatory.
- **AI disclosure is required** for a substantial AI-generated share — a plain sentence you
  write. **No** `Co-Authored-By` agent trailer and **no** "Generated with …" footer.
- **Rebase is not forbidden** (CONTRIBUTING documents `git rebase --keep-base --signoff` and
  `--gpg-sign` fixes). Still prefer `git merge` mid-review unless fixing DCO/signatures.
- **Checks you must see present, not just green.** `copy-pr-bot` mirrors only vetted authors'
  heads; others get `needs-ok-to-test`. `gh pr checks <n> --json name,workflow`.
- **Local gates.** `make preflight` needs **GNU Make ≥ 4**; this Mac has 3.81 and no `gmake`.
  Use per-module targets, which work with either: `make -C <module> lint test`. **Verified**
  on `auth/` (tests pass, `0 issues` from lint; ~10s test, ~30s lint with a cold lint-tool
  download). `controller/AGENTS.md` lists extra steps (generate, license, api-compat-check).
- **No `TODO:` comments in `controller/`** (linter); use `FIXME:` + GitHub issue link.
- **Account must match directory.** `~/source/**` → `yuzhiquan`. `gh` was found active as
  `yuzhiquantubi` at the start of round 1 and had to be switched.
- **Remotes.** `~/source/nvke`: `origin` = `git@github.com:yuzhiquan/nvke.git` (**not** the
  `github.com-yzq` alias — a push as the wrong SSH identity will 404) and `upstream` =
  `dsx-ai-factory/nvke` (added in round 1). Read `upstream/main`, never `origin/main`.
- **Research is read-only** against the working clone; use a detached worktree:
  `git -C ~/source/nvke worktree add -q --detach /tmp/nvke-wt upstream/main`.

## 7. Running it

```bash
cd ~/source/nvke-study
git -C ~/source/nvke fetch upstream                    # always first
tools/pr-index.sh --unreferenced                       # PR side
tools/claims.sh --self yuzhiquan                       # informal claims
FORMAT=md tools/screen-issues.sh --no-cache --discover --skip-taken tools/known-taken.txt --limit 30
FORMAT=md tools/screen-issues.sh --no-cache 2022 1177  # specific candidates
```

Then per result: read body + every comment (R2/R4); read each cross-referenced PR's diff;
grep the tree for the thing the issue says is missing (obsolete?); follow cross-repo links
(blocked?); write the plan (§3) only if actionable; update `plans/README.md`, `COVERAGE.md`
and `tools/known-taken.txt`; commit to this repo. **Never modify the upstream clone during
research.**
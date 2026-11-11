# Contribution-research tools

Three tools for finding genuinely available work in an open-source GitHub repo, and for
pressure-testing an implementation plan before writing code. Built for
`kubernetes-sigs/agent-sandbox`, then generalised — **verified working on `pallets/flask`**, whose
label vocabulary shares nothing with Kubernetes'.

| Tool | Job |
|---|---|
| `screen-issues.sh` | Apply four availability rules to issues; emit evidence + a triage verdict |
| `pr-index.sh` | Invert rule 1 — build a PR→issue reverse index; find PRs referencing no issue |
| `claims.sh` | One-call sweep of open issues for informal claims ("I'll take this"); prints claimant, date, age bucket and any open PR |
| `review-plan.sh` | Run adversarial review passes over a plan until findings stop |
| `profile-repo.sh` | Probe a repo → `PROJECT-FACTS.md`, the facts plans keep re-deriving |

## Quick start on a new project

```bash
# 0. Build the fact base ONCE, from the mainline branch. Every later plan cites it
#    instead of re-probing. Use a detached worktree so you never disturb your
#    working branch:
#      git worktree add -q --detach /tmp/wt origin/main
./profile-repo.sh --repo-dir /tmp/wt --out ../PROJECT-FACTS.md
#      git worktree remove --force /tmp/wt

# 1. Which PRs claim which issues? Run this FIRST — it is one API sweep and it
#    catches work that no issue-side check can see.
./pr-index.sh --repo OWNER/NAME
./pr-index.sh --repo OWNER/NAME --unreferenced   # PRs mentioning no issue at all
./pr-index.sh --repo OWNER/NAME --grep 'keyword|other'  # PRs by title/body/branch text (roadmap items, unfiled work)
# Responses are cached 15 min (CACHE_TTL=seconds); --no-cache forces a refetch.

# 1b. Who has said they will do what, and how long ago? Unassigned is not free.
./claims.sh --repo OWNER/NAME --self YOUR_LOGIN        # ACTIVE <=30d, AGING <=90d, LAPSED beyond

# 2. Screen candidates. Pick the profile matching the project's label style.
./screen-issues.sh --repo OWNER/NAME --profile github-generic --discover --limit 20

# 3. Screen specific issues once you have candidates.
./screen-issues.sh --repo OWNER/NAME --profile github-generic 123 456
```

## Why the rules are portable but the labels are not

The **four screening rules** read timelines, bodies and comments — universal GitHub mechanics, so
they work anywhere unchanged:

| Rule | Check | The false positive it came from |
|---|---|---|
| **R1** | cross-referenced PRs, ignoring closing keywords; **read** them | #968 had four open PRs while looking unassigned and unlinked |
| **R2** | the *last comment*, not metadata | #225 was OPEN + assigned + had a merged PR — finished work nobody closed |
| **R3** | the *body*, for author self-implementation | #1157's author had a 14-commit POC on a fork, no PR |
| **R4** | *every* comment, for PR announcements and design history | #764 had "Fixed in #1078. PTAL" in a comment |

**Label vocabularies are not portable.** Measured:

- `kubernetes-sigs/*` — `kind/*`, `priority/*`, `lifecycle/*`
- `prometheus/prometheus` — `area/*`, `component/*`, `backport-*`
- `grafana/grafana` — deep `area/alerting/*` hierarchies
- `pallets/flask` — flat: `bug`, `docs`, `typing`, `auto-closed`

So label heuristics live in **profiles** (`profiles/*.conf`), and every key is optional — an unset
key disables that heuristic rather than breaking.

| Profile | For |
|---|---|
| `kubernetes` | Kubernetes/CNCF/prow: `kind/*`, `priority/*`, `lifecycle/*` (the default) |
| `github-generic` | Most projects: flat `bug`/`docs`/`good first issue` labels, no priority ladder |
| `area-component` | `area/*` + `component/*` taxonomies (Prometheus, Grafana) |

Write your own by copying one:

```bash
SKIP_LABELS="wontfix,invalid,stale"      # not worth planning
PROPOSAL_LABELS="rfc,proposal"           # deliverable is a design, not code
PROCESS_LABELS="breaking-change"         # needs a design doc first
INVITE_LABELS="good first issue"         # maintainers want help — ranked first
PRIORITY_PREFIX="priority/"              # empty = no priority filtering
PRIORITY_ORDER="high,medium,low"
PROCESS_ARTIFACT="RFC"                   # cosmetic, used in messages
```

## Verdicts are triage, not conclusions

`AVAILABLE` · `HUMAN-REVIEW` · `TAKEN` · `DONE-UNCLOSED`

**`HUMAN-REVIEW` means "read the evidence I printed", not "unavailable".** R2 and R4 turn on
meaning, not pattern matching, so they cannot be fully automated. Treating `AVAILABLE` as final is
the exact mistake that put a taken issue in front of the user.

Three states the tool can't distinguish, and you must:

- **Taken** — someone else is on it.
- **Blocked** — free, but depends on unmerged work. `grep` for the extension point a feature claims
  to plug into; if it doesn't exist yet, the issue isn't startable.
- **Actionable** — free *and* unblocked. Across ~68 issues in one repo, this was rare.

## Optional multi-account guard

If you use different GitHub identities per directory, set both and the tool warns on mismatch
(a wrong-account `/assign` has happened):

```bash
export ACCOUNT_DIR_PREFIX="$HOME/work"
export ACCOUNT_FOR_DIR="work-username"
```

Unset = no check.

## Bugs found by porting to a second repo

Generalising is what surfaced these — each was invisible while only one repo was in view:

1. **Cross-repo/fork cross-references.** `pallets/flask#6065`'s timeline lists "PR #1" from
   `AdarshJ173/flask` — a *fork* — beside the two real upstream PRs. Reporting a fork's PR #1 as
   upstream #1 is badly misleading, so R1 now filters on `repository_url`.
2. **Rate limits looked like empty results.** A secondary-rate-limit 403 was swallowed and rendered
   as "no open unassigned issues", which sent me debugging a tool bug that didn't exist. Discovery
   now fails loudly and distinguishes rate-limit from empty.

Earlier, single-repo bugs worth knowing about: tab-delimited metadata shifted fields when a value
was empty (tab is IFS whitespace — use `0x1f`); a jq precedence slip (`[.num|tostring, .author]`
parses as `[.num] | (tostring, .author)` — parenthesise); and an R3 regex that only scanned bodies,
missing a volunteer offer made in a comment.

## Requirements

`gh` (authenticated), `jq`, `bash` 4+. `review-plan.sh` additionally needs `codex` (verified
working headless) or `claude` (works from a plain shell; errors when nested inside a Claude Code
session).

## Why a fact base matters

`screen-issues.sh` answers *is this available?* and `review-plan.sh` answers *is this plan
wrong?* — but neither carries project knowledge, so every plan re-derived the same things.
Several review findings were nothing more than a project fact learned late: that
`k8s/**/*.yaml` is globbed into release assets, that one RBAC role is generated per tree,
that duration fields are integer seconds here.

`profile-repo.sh` emits only what it can **probe**; anything heuristic is marked **⚠ VERIFY**.
`PROJECT-FACTS.md` then gains a hand-maintained section for what probing cannot infer — the
prow commit-message rules, the API conventions, the code landmines. Append to it rather than
rediscovering.

**Counting trap it was built around:** `find -name '*.py'` in agent-sandbox returns **22,012**
files; 21,832 are vendored virtualenvs and the real number is **180**. A generated fact that is
wrong is worse than no fact, because plans cite it. The prober prunes before it counts, and it
warns when you profile a non-default branch.

See `../RESEARCH-WORKFLOW.md` for the judgment half — what to plan, in what order, and when the
right deliverable is a comment rather than a PR.

---

## Porting notes — nvke (2026-11-11)

Copied from `~/source/agent-sandbox-study/tools` (includes `claims.sh`). Changes and findings:

1. **`pr-index.sh` cache key now includes the repo slug.** The copy keyed on state only and would have
   served another project's PRs. Check: tool's PR total (82) == `gh` search total (82), titles are nvke's.
2. **Defaults retargeted.** `REPO` is `dsx-ai-factory/nvke` in `pr-index.sh`, `screen-issues.sh`,
   `claims.sh`; `screen-issues.sh` now defaults to `PROFILE=nvke` (it defaulted to *no profile*,
   which silently applies Kubernetes/prow labels that nvke does not use).
3. **`profile-repo.sh` aborted on a big repo** (`set -o pipefail` + a filter/`head` pipeline in
   `biggest_files` killed the script with no error on nvke's ~1,700 `.go` files, leaving no output
   file). Added `|| true`. Also excludes `*.gen.go` from "largest implementation files" (nvke's three
   biggest `.go` files are generated), and the "naive count" caveat now names its source repo
   instead of asserting agent-sandbox's numbers as this repo's.
4. **`claims.sh` false-ish positive:** the nvke issue form's "willing to contribute" checkbox text
   matches its claim regex. Weigh it below a `/assign` or "I'll take this" comment (see
   `../RESEARCH-WORKFLOW.md` §1c).
5. **`profiles/nvke.conf`** is new: `priority/P0..P2`, `good first issue`/`help wanted`, no
   lifecycle bot, no KEP process. Label frequencies measured and recorded in the file.
6. `known-taken.txt` starts with round-1 verdicts; continuation lines are `#`-prefixed so the
   `--skip-taken` regex cannot read PR numbers as issues (spot-checked).

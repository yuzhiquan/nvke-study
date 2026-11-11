# nvke contribution plans — index

> **Latest: round 1 — 2026-11-11.** Repo profiled, tooling ported, 17 of 110 unassigned issues
> screened. **No plan written** — nothing screened is verified actionable for code. One comment
> drafted (#2022), unposted. See `../COVERAGE.md` before treating the list below as available work.

## Ranked candidates

| # | Issue | Deliverable | Plan | Status |
|---|---|---|---|---|
| 1 | [#2022](https://github.com/dsx-ai-factory/nvke/issues/2022) `dsx.Decode` accepts two datahalls sharing one API endpoint | **PR** | [drafts/patch-2022-reject-shared-endpoints.diff](../drafts/patch-2022-reject-shared-endpoints.diff) | ✅ **[PR #2282](https://github.com/dsx-ai-factory/nvke/pull/2282) opened 2026-11-11**, comment posted on the issue; awaiting review |
| 2 | [#2136](https://github.com/dsx-ai-factory/nvke/issues/2136) nico-sim container nodes fail kubelet imageFs stats (fuse-overlayfs) | **comment** → small PR | [issue-2136-nico-sim-fuse-overlayfs.md](issue-2136-nico-sim-fuse-overlayfs.md) | 🟡 FREE (round-1 TAKEN verdict was a regex false positive); 🚩 waiting on a maintainer to pick fix option; comment drafted, unposted |
| 3 | [#1177](https://github.com/dsx-ai-factory/nvke/issues/1177) providers: CONFIGURED doesn't prove the provider works | **comment** (only if useful) | _not written_ | 🚩 needs a Product ruling (absent provider → hard create error?) |

## Ruled out in round 1

Taken / adjacent PR: ~~#609~~ ~~#707~~ ~~#1369~~ ~~#1957~~ ~~#2002~~ ~~#2058~~ ~~#2067~~
~~#2264~~ ~~#2268~~ ~~#2248~~ ~~#2136~~; unverified-adjacent (`TAKEN?`): #1242 #2263 #2265 #2021.
Reasons: `../tools/known-taken.txt`.

## Run changelog

| Run | Date | What |
|---|---|---|
| 1 | 2026-11-11 | Opened PR #2282 for #2022 (first contribution). |
| 0 | 2026-11-11 | Bootstrap: study repo, tools ported (3 bugs, see `../tools/README.md`), facts probed at `487f5110`, 17 issues screened, loop wired. |

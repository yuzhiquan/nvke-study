# HANDOFF — nvke-study

_Last updated 2026-11-11, end of bootstrap round 1. Upstream `dsx-ai-factory/nvke` @ `487f5110`._

## State

- Study repo built (`~/source/nvke-study`, local git repo, **no GitHub remote yet**).
- Tools ported and smoke-tested (`tools/README.md` § Porting notes).
- 17 of 110 unassigned issues screened (15%). **0 verified actionable for code.**
  Two comment-sized candidates: #2022 (draft in `drafts/`, unposted) and #1177 (needs Product).
- Loop wired in `~/source/nvke`: `loop.config.yaml`, `.loop/state.md`, `.loop/loop-run.sh`
  (all git-excluded via `.git/info/exclude`). See "Loop" below for what has/hasn't been run.

## Nothing is in flight upstream

No branch, PR or comment has been created. `origin` = `yuzhiquan/nvke` fork (untouched).

## Do these before the first PR

1. **Commit signing.** `main` requires verified signatures and DCO. `commit.gpgsign` is unset.
   Register a GPG/SSH signing key on the `yuzhiquan` GitHub account, then in `~/source/nvke`:
   `git config commit.gpgsign true`. Without it the PR is blocked at the merge box.
2. **`origin` SSH host.** `~/source/nvke` `origin` is `git@github.com:yuzhiquan/nvke.git`. Per the
   account rules `yuzhiquan` pushes use `git@github.com-yzq:…`; the default host authenticates as
   `yuzhiquantubi`. I tried to repoint it during bootstrap and was denied — **your call**:
   `git -C ~/source/nvke remote set-url origin git@github.com-yzq:yuzhiquan/nvke.git`.
3. **GNU Make ≥ 4** (`brew install make` → `gmake`) to run `make preflight`; or run the module
   targets `make -C <module> lint test`.
4. **Create the study repo's remote** (private): `git@github.com-yzq:yuzhiquan/nvke-study.git`, then
   push. `.loop/state.md` is not otherwise backed up.

## Next steps (round 2)

See `COVERAGE.md` § Sweep order. Start by `git fetch upstream` and `tools/pr-index.sh --no-cache`.
Read #2072's current diff before posting the #2022 comment.

## Gotchas

- `gh` active account drifted to `yuzhiquantubi`; I switched to `yuzhiquan`. Re-check before any write.
- zsh: don't start an `echo` with `=====` (parsed as a command substitution).
- Screens go stale within a day or two (~11 merges/day).
- `claims.sh` flags the issue-form "willing to contribute" checkbox as an `ACTIVE` claim.
- `AGENTS.md` bans adding agent attribution to commits/PRs, and requires an AI-use note in the PR
  description written by the human.

## Loop

See `~/source/nvke/.loop/state.md`. The loop only triages and proposes; it never edits code, runs
git, comments, or opens PRs.

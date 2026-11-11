# HANDOFF — nvke-study

_Last updated 2026-11-11, end of bootstrap round 1. Upstream `dsx-ai-factory/nvke` @ `487f5110`._

## State

- Study repo built (`~/source/nvke-study`, pushed to `yuzhiquan/nvke-study`).
- Tools ported and smoke-tested (`tools/README.md` § Porting notes).
- 17 of 110 unassigned issues screened (15%). **0 verified actionable for code.**
  Two comment-sized candidates: #2022 (draft in `drafts/`, unposted) and #1177 (needs Product).
- Loop wired in `~/source/nvke`: `loop.config.yaml`, `.loop/state.md`, `.loop/loop-run.sh`
  (all git-excluded via `.git/info/exclude`). See "Loop" below for what has/hasn't been run.

## In flight upstream

- **PR [#2282](https://github.com/dsx-ai-factory/nvke/pull/2282)** `fix(e2e): reject two dsx sites that share an api endpoint`, closes #2022. Branch `fix/reject-shared-dsx-endpoints` on the fork, 1 signed (DCO + SSH-verified) commit. Comment posted on #2022. Worktree `/tmp/nvke-2022` (disposable; the patch is in `drafts/`).
- Watch: review, `/ok to test` (`needs-ok-to-test`), CodeRabbit, and whether #2072 merges first (patch applies on top of it).
- Not run for this PR: `make preflight` (Make 3.81) and e2e lanes; the PR body says so.

## Do these before the first PR

1. ~~Commit signing~~ **done 2026-11-11.** Key `~/.ssh/id_ed25519_yuzhiquan_signing` (no passphrase) registered as a *signing* key on `yuzhiquan`; `~/source/nvke` has `gpg.format=ssh`, `commit.gpgsign=true`. GitHub reports commits as Verified.
2. **`origin` SSH host.** `~/source/nvke` `origin` is `git@github.com:yuzhiquan/nvke.git`. Per the
   account rules `yuzhiquan` pushes use `git@github.com-yzq:…`; the default host authenticates as
   `yuzhiquantubi`. I tried to repoint it during bootstrap and was denied — **your call**:
   `git -C ~/source/nvke remote set-url origin git@github.com-yzq:yuzhiquan/nvke.git`.
3. **GNU Make ≥ 4** (`brew install make` → `gmake`) to run `make preflight`; or run the module
   targets `make -C <module> lint test`.
4. ~~study repo remote~~ pushed to `yuzhiquan/nvke-study` (**public**; consider making it private). Refresh `loop-backup/` after each loop round.

## Next candidate

- **#2136** (nico-sim imageFs stats): free, waiting on a maintainer's choice. Plan: `plans/issue-2136-nico-sim-fuse-overlayfs.md`; comment drafted in `drafts/`, unposted.

## Next steps (round 2)

See `COVERAGE.md` § Sweep order. Start by `git fetch upstream` and `tools/pr-index.sh --no-cache`.
Check #2282's review state first (`gh pr view 2282 --repo dsx-ai-factory/nvke`).

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

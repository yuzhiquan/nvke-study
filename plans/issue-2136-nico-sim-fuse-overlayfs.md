# #2136 — nico-sim container nodes fail kubelet imageFs stats (fuse-overlayfs)

- Issue: https://github.com/dsx-ai-factory/nvke/issues/2136 — `[Bug]`, `bug`, `area/controller`, **P2** (triaged by jedimt, 2026-11-06)
- **Availability (2026-11-11, upstream `487f5110`):** FREE. `screen-issues.sh` said TAKEN; that was a false positive — the claim regex matched "A maintainer will pick one" in the triage comment. Read in full: no contributor claim. `pr-index.sh --no-cache --grep "nico-sim|fuse-overlayfs|snapshotter"` found no PR. Not yet checked: closed/merged PRs touching `controller/nico-sim`.
- **Status: BLOCKED ON A DESIGN CHOICE.** Triage: "A maintainer will pick one." Do not write code before they do.

## Problem (from the issue body + triage; code line verified)

`nico-sim`'s container backend starts each node with `KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER=fuse-overlayfs`
(`controller/nico-sim/internal/container/service.go:267`, verified at `487f5110`). containerd then reports its image
filesystem mountpoint as `/var/lib/containerd/io.containerd.snapshotter.v1.fuse-overlayfs`, which does not exist; the data is in
`/var/lib/containerd-fuse-overlayfs`. Per the report: `/stats/summary` returns 500 on every node, image GC fails
(`ImageGCFailed`), and the eviction manager fails each sync. **The kubelet behaviour itself is taken from the reporter's logs; jedimt
did not run a cluster and neither did I.**

## Options (from triage)

1. Create a symlink when `nico-sim` creates the node (the reporter's workaround; triage calls it "small and correct").
2. Drop `fuse-overlayfs` now that nodes have a `/var` volume (#1811). Needs a check that image whiteouts still work.

## Testability here

- Unit tests next to the code: `controller/nico-sim/internal/container/service_test.go`, `docker_test.go` (can assert the container args / the symlink command).
- **Cannot reproduce the kubelet failure locally** — the Docker daemon was not confirmed running (`docker info` showed only the client). Say so in the PR.
- Gate: `make -C controller/nico-sim test lint` (not run yet).

## Deliverable

**Comment first**, asking which option the maintainers prefer and offering to implement option 1. Then a small PR. Draft: `../drafts/comment-2136-pick-an-option.md` (unposted).

## PR mechanics (see PROJECT-FACTS.md § PR mechanics)

Branch `fix/nico-sim-imagefs-stats`; title `fix(nico-sim): ...` (scope allowed by the live regex); `git commit -s`, signed; `Closes: #2136`; AI-assistance note; no agent trailer.

## Open questions 🚩

- Which option? (maintainer)
- Does `nico-sim` have a test seam for the node-create command, or would option 1 need one? (read `service.go` around :267 first)

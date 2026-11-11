# nvke-study

Research repo for contributing to **`dsx-ai-factory/nvke`** (NVIDIA Kubernetes Engine, "NVKE":
a management plane for GPU Kubernetes on bare metal). Documentation and tooling only — no
upstream code lives here. Modelled on `~/source/agent-sandbox-study` and
`~/source/agent-router-study`.

- Upstream: <https://github.com/dsx-ai-factory/nvke> (public, Apache-2.0, ~1.1k stars)
- Fork / working clone: `yuzhiquan/nvke` → `~/source/nvke` (`origin` = fork, `upstream` = dsx-ai-factory)
- Loop: `~/source/nvke/loop.config.yaml`, `.loop/` (git-excluded locally; backed up via this repo)
- Status: **round 1, 2026-11-11.** See [`HANDOFF.md`](HANDOFF.md) and [`COVERAGE.md`](COVERAGE.md).

## What the project is

A seed cluster stands up a highly available control plane, which then creates GPU tenant clusters
on demand (`AGENTS.md`, `docs/architecture.md` in the upstream repo). Components:

| Module | Role | Impl / test lines (Go, gen + pb excluded) |
|---|---|---|
| `controller/` | NVKE controller (formerly CWE): Temporal workflows, PostgreSQL, OpenAPI REST | 112.8k / 131.7k |
| `agent/` | node agent, gRPC over SPIFFE/SPIRE mTLS, drives kubeadm | 21.6k / 21.1k |
| `cli/` | `nvkectl` | 24.0k / 31.5k |
| `auth/` | authn / authz libraries used by the controller | 4.6k / 7.5k |
| `management-engine/` | `NVKECluster` reconciler + CRDs (`apis/v1`) | 7.8k / 4.8k |
| `release/` | release + qualification tooling | 8.4k / 9.1k |
| `cluster-api-provider-provisioned/` | CAPI infra provider for pre-provisioned hosts | 2.3k / 1.4k |
| `os-image/`, `nktp/` | node OS image spec / telemetry Helm chart | 0.4k Go / chart |

13 Go modules under one `go.work`. Latest release **v0.23.1** (2026-11-03); **v0.24.0-rc.7** is
out. Pre-1.0, fast-moving: ~11 PRs merge per day.

## Where to start reading (2–4 days)

Order by real size, then read **tests as the spec** (`wc -l`, 2026-11-11, `487f5110`):

1. **Day 1 — orientation.** Upstream `README.md`, `AGENTS.md`, `docs/architecture.md`,
   `docs/development.md` (test-environment guide), then the module `AGENTS.md` of the area you
   will touch. `ROADMAP.md` for direction.
2. **Day 1–2 — controller.** `controller/internal/server/clusters.go` (1,685 lines) with
   `clusters_test.go` (2,260). The REST surface is generated from `controller/api/openapi.yaml`
   (`*.gen.go` are the three biggest "files" and are **not** source — skip them).
3. **Day 2 — agent.** `agent/internal/agent/agent.go` (2,514) and
   `control_plane_graceful_shutdown.go` (1,348).
4. **Day 3 — CLI.** `cli/internal/nvkectl/bootstrap.go` (1,464) with `bootstrap_test.go`
   (**2,729**, the largest test file) and `cli/internal/bootstrap/controllerdeploy/`.
5. **Day 3–4 — e2e.** `controller/test/e2e/` (`tenant_test.go` 2,150) and `docs/qualification/`.

Schema/generated files excluded from "largest implementation file": `controller/api/client.gen.go`
(3,141), `server.gen.go` (2,881), `models.gen.go` (1,851).

## Contribution-process traps (verified; details in `PROJECT-FACTS.md`)

- **Fork-only**: PRs from `yuzhiquan/nvke`, never from a branch on `dsx-ai-factory/nvke`.
- **DCO on every commit** (`git commit -s`) **and verified signatures** (`required_signatures`
  ruleset). Signing is **not configured on this machine yet.**
- **PR title is the squash commit subject**; regex enforced on `main`:
  `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9/_.-]+\))?!?: .+`.
- **AI-assistance disclosure is required** (plain sentence, written by you); **no** agent
  `Co-Authored-By` trailer, **no** "Generated with" footer.
- **`make preflight` needs GNU Make ≥ 4** (macOS ships 3.81). Per-module `make -C <m> lint test`
  works and was verified on `auth/`.
- First-time / unvetted authors need a maintainer's `/ok to test`; many checks (golangci-lint,
  CodeQL, govulncheck, gitleaks…) only run once copy-pr-bot mirrors the head — check they are
  **present**, not just green.
- No JIRA prefix; branch `<type>/<short-description>`.

## Contribution candidates (round 1 — 17 of 110 unassigned issues screened)

**No candidate is verified actionable for code yet.** 15 of 17 screened issues already had a PR or
a claim. Deliverables:

| Issue | State | Screens run | Deliverable |
|---|---|---|---|
| [#2022](https://github.com/dsx-ai-factory/nvke/issues/2022) `dsx.Decode accepts two datahalls sharing one API endpoint` | **Entangled (light)** with open PR #2072 — #2072 renames `datahall`→`site-N` and adds **no** duplicate check | R1–R4 + `pr-index --grep` + #2072 diff read | **comment**: ask whether the check goes into #2072; else take it as a follow-up after #2072 merges (code is ~10 lines + a table test) |
| [#1177](https://github.com/dsx-ai-factory/nvke/issues/1177) providers: CONFIGURED doesn't prove the provider works | **Needs Product ruling** | R1–R4 + `pr-index --grep` | **comment** only if useful; code waits for a Product answer |

Ruled out (taken / adjacent PR): #609 #707 #1369 #1957 #2002 #2058 #2067 #2264 #2268 #2248 #2136;
unverified-adjacent: #1242 #2263 #2265 #2021. Reasons in [`tools/known-taken.txt`](tools/known-taken.txt).

Not yet screened — see [`COVERAGE.md`](COVERAGE.md) for the ordered list (starts with the
`mchmarny` Oct-2 batch and the 28-issue `os-image` epic).

## Layout

| Path | What |
|---|---|
| `PROJECT-FACTS.md` | probed facts + hand-verified PR mechanics |
| `RESEARCH-WORKFLOW.md` | the method, tuned to nvke's speed |
| `COVERAGE.md` | honest ledger of what was and wasn't screened |
| `HANDOFF.md` | state, next steps, gotchas |
| `plans/`, `drafts/` | ranked plans; unposted comments |
| `tools/` | `profile-repo.sh`, `pr-index.sh`, `screen-issues.sh`, `claims.sh`, `review-plan.sh`, `profiles/nvke.conf` |
#!/usr/bin/env bash
#
# review-plan.sh — run adversarial review passes over a plan file until the
# reviewers stop finding substantive problems, then stop.
#
# This mechanises the loop used on plans/issue-1214-preempt-warm-pods.md, which
# took five manual passes and produced 22 findings. What that loop taught, and
# what this script therefore does:
#
#   * Reviewers must READ THE CODE, not just the plan. The highest-value finding
#     in five passes ("isSandboxStale returns early on a template-hash match, so
#     your drift will never roll out") was only findable in the repo.
#   * Reviewers legitimately CONTRADICT each other, and later passes can be
#     right. Validation flipped three times (add a pattern -> no, it rejects "" ->
#     yes, as ^$|...). So each pass is told what previous passes concluded.
#   * Findings must be VERIFIED before acceptance. Roughly one in six was wrong
#     or wrong-in-form. This script never edits the plan; it produces reviews for
#     a human (or the parent agent) to verify and fold in.
#   * Know when to STOP. By pass 5 findings had moved to edge paths in
#     already-read code. Convergence is detected here as: no High/Medium findings
#     for --consecutive-clean passes in a row.
#
# It deliberately does NOT auto-apply findings. Every manual pass turned up at
# least one finding that was wrong on the facts; auto-applying would bake those in.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$PWD}"
PROJECT_DESC="${PROJECT_DESC:-}"
MAX_PASSES="${MAX_PASSES:-5}"
CONSECUTIVE_CLEAN="${CONSECUTIVE_CLEAN:-2}"
REVIEWERS="${REVIEWERS:-codex}"
MODEL="${MODEL:-}"
TIMEOUT_SECS="${TIMEOUT_SECS:-900}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; BLU=$'\033[0;34m'
DIM=$'\033[2m'; BLD=$'\033[1m'; NC=$'\033[0m'
[[ -t 1 ]] || { RED=""; GRN=""; YLW=""; BLU=""; DIM=""; BLD=""; NC=""; }

log_info()  { printf '%s[info]%s %s\n'  "$BLU" "$NC" "$*" >&2; }
log_ok()    { printf '%s[ok]%s %s\n'    "$GRN" "$NC" "$*" >&2; }
log_warn()  { printf '%s[warn]%s %s\n'  "$YLW" "$NC" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n' "$RED" "$NC" "$*" >&2; }
die() { log_error "$*"; exit 2; }

usage() {
  cat <<'EOF'
Usage: review-plan.sh [options] <plan-file.md>

Runs adversarial review passes over an implementation plan until reviewers stop
finding High/Medium problems, then stops. Appends each review to the plan file as
a new numbered section; never rewrites the plan's live content.

Options:
  --max-passes N        Hard cap on passes (default 5)
  --consecutive-clean N Stop after N passes with no High/Medium findings (default 2)
  --reviewers LIST      Comma list: codex,claude (default codex)
  --repo-dir DIR        Repo the reviewer reads for verification
                        (default: current directory)
  --project-desc TEXT   How to describe the project to the reviewer, e.g.
                        "dsx-ai-factory/nvke GPU Kubernetes management plane (Go monorepo)"
  --model NAME          Model override passed to the reviewer CLI
  --timeout SECS        Per-pass timeout (default 900)
  --dry-run             Print the prompt that would be sent, then exit
  -h, --help            This help

Environment: REPO_DIR, MAX_PASSES, CONSECUTIVE_CLEAN, REVIEWERS, MODEL, TIMEOUT_SECS

Exit status: 0 converged, 3 hit --max-passes without converging, 2 usage/tooling error.

Examples:
  review-plan.sh plans/issue-1214-preempt-warm-pods.md
  review-plan.sh --reviewers codex,claude --max-passes 3 plans/issue-949-portable-oci-snapshot.md
  review-plan.sh --dry-run plans/issue-643-network-class.md
EOF
}

# --------------------------------------------------------------- prompt builder

# The prompt encodes the standards that made the manual loop work. In particular
# it demands file:line verification and forbids the two failure modes actually
# observed: findings that restate the plan, and findings invented without
# checking the repo.
build_prompt() {
  local plan="$1" pass="$2" prior="$3"
  # The reviewer runs with cwd = REPO_DIR (so it can read the code it must
  # verify against), which means the plan path MUST be absolute — a relative
  # path resolves inside the wrong tree and the reviewer correctly reports
  # "plan not found" instead of reviewing anything. Caught on the first live run.
  local plan_abs; plan_abs="$(cd "$(dirname "$plan")" && pwd)/$(basename "$plan")"
  cat <<PROMPT
You are reviewing an implementation plan for a contribution to the
${PROJECT_DESC:-open-source project at ${REPO_DIR}}. This is review pass ${pass}.

The plan file is at this ABSOLUTE path, which is OUTSIDE the repository you are
reading code from — read it first, in full:
    ${plan_abs}

The repository the plan targets is checked out at: ${REPO_DIR}
Your shell starts in ${REPO_DIR}. Use the absolute path above for the plan.

YOUR JOB: find substantive problems that would cause the implementation to be
wrong, rejected in review, or silently broken at runtime. Be adversarial. A pass
that finds nothing is an acceptable and useful outcome — do not invent findings
to seem productive.

NON-NEGOTIABLE RULES:

1. VERIFY AGAINST THE CODE. Read the actual files in ${REPO_DIR} before making
   any claim about them. Cite file:line. Do not trust the plan's own citations —
   they drift, and past reviews have caught stale ones (e.g. a k8s.io/api version
   cited from a stale module cache when go.mod pinned a different version).
2. TRACE WHOLE CODE PATHS, not single functions. The single most valuable finding
   in this plan's history was that an early \`return\` in a caller made an entire
   downstream design unreachable. Look for early returns, fall-through else
   branches, and memoisation caches that can return a stale verdict.
3. CHECK GENERATED ARTIFACTS AND PRECEDENT. If the plan touches anything
   generated (schemas, API types, codegen output, migrations, lockfiles, docs):
   does the repo already do this somewhere, and would the GENERATED file actually
   say what the plan assumes? Read the generated artifact, not just the source
   annotation. Watch for language-specific escaping traps (e.g. in Go, a regex in
   a backtick string needs single backslashes, not the doubled ones a quoted
   string would need). If the plan introduces a pattern with no precedent in the
   repo, say so — that is a maintainer decision, not a drive-by.
4. SEVERITY IS REQUIRED. Label each finding High / Medium / Low.
   - High: the implementation would be functionally wrong, or a reviewer would
     block the PR.
   - Medium: a real defect, gap, or contradiction worth fixing before coding.
   - Low: docs/wording/hygiene.
5. NO RESTATEMENT. Do not summarise the plan back. Only report problems.
6. IF YOU DISAGREE WITH A PREVIOUS PASS, SAY SO EXPLICITLY and give the reason.
   Earlier passes have been wrong, and reversing them has been correct.

${prior}

OUTPUT FORMAT — markdown, exactly this shape:

### Findings and Suggested Fixes

- **<Severity>: <one-line problem statement>.** <Explanation citing file:line
  evidence you actually read.>

  **Suggested fix:** <concrete change, with a code block if it helps.>

(Repeat per finding. If you find nothing substantive, write exactly:
"No High or Medium findings this pass." followed by any Low items.)

### Recommended Plan Edits Before Coding

- <short actionable bullets, or "None.">
PROMPT
}

# Summarise what earlier passes already settled, so a new pass neither repeats
# them nor silently contradicts them without argument.
build_prior_context() {
  local plan="$1"
  local prior_sections
  prior_sections="$(grep -nE '^## [0-9]+\. (Codex |Automated )?Review' "$plan" 2>/dev/null | tail -6 || true)"
  [[ -z "$prior_sections" ]] && { printf 'This is the first review pass; there is no prior review context.\n'; return; }

  printf 'PREVIOUS REVIEW PASSES ALREADY EXIST IN THIS FILE:\n\n'
  printf '%s\n\n' "$prior_sections"
  printf 'Read those sections in the plan file before starting. Rules:\n'
  printf '  - Do NOT re-report a finding already marked accepted and applied.\n'
  printf '  - DO report it again if you believe the applied fix is wrong or incomplete.\n'
  printf '  - DO explicitly reverse an earlier conclusion if the evidence supports it,\n'
  printf '    stating which pass you disagree with and why.\n'
  printf '  - Findings should get progressively narrower. If you are only finding Low\n'
  printf '    items in already-reviewed code, say the plan has converged.\n'
}

# ------------------------------------------------------------------- reviewers

run_codex() {
  local prompt="$1" out="$2"
  # read-only sandbox: the reviewer must not mutate the repo. disk-full-read-access
  # is required because the plan file lives outside REPO_DIR (in the study repo)
  # and the default read-only policy scopes reads to the workspace.
  local -a args=(exec -s read-only -C "$REPO_DIR"
                 -c 'sandbox_permissions=["disk-full-read-access"]'
                 -o "$out")
  [[ -n "$MODEL" ]] && args+=(-m "$MODEL")
  timeout "$TIMEOUT_SECS" codex "${args[@]}" "$prompt" >/dev/null 2>&1
}

run_claude() {
  local prompt="$1" out="$2"
  local -a args=(-p --permission-mode plan)
  [[ -n "$MODEL" ]] && args+=(--model "$MODEL")
  ( cd "$REPO_DIR" && timeout "$TIMEOUT_SECS" claude "${args[@]}" "$prompt" ) > "$out" 2>/dev/null
}

# Count High/Medium findings in a review to decide convergence.
count_substantive() {
  local file="$1"
  grep -icE '^[[:space:]]*[-*][[:space:]]*\*\*(High|Medium)' "$file" 2>/dev/null || true
}

count_all_findings() {
  local file="$1"
  grep -icE '^[[:space:]]*[-*][[:space:]]*\*\*(High|Medium|Low)' "$file" 2>/dev/null || true
}

next_section_number() {
  local plan="$1" last
  last="$(grep -oE '^## ([0-9]+)\.' "$plan" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true)"
  printf '%d' "$(( ${last:-0} + 1 ))"
}

# ----------------------------------------------------------------------- main

main() {
  local plan="" dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-passes)        MAX_PASSES="${2:?}"; shift 2 ;;
      --consecutive-clean) CONSECUTIVE_CLEAN="${2:?}"; shift 2 ;;
      --reviewers)         REVIEWERS="${2:?}"; shift 2 ;;
      --repo-dir)          REPO_DIR="${2:?}"; shift 2 ;;
      --project-desc)      PROJECT_DESC="${2:?}"; shift 2 ;;
      --model)             MODEL="${2:?}"; shift 2 ;;
      --timeout)           TIMEOUT_SECS="${2:?}"; shift 2 ;;
      --dry-run)           dry_run=1; shift ;;
      -h|--help)           usage; exit 0 ;;
      -*)                  die "unknown option: $1 (try --help)" ;;
      *)                   plan="$1"; shift ;;
    esac
  done

  [[ -n "$plan" ]] || { usage; die "no plan file given"; }
  [[ -f "$plan" ]] || die "plan file not found: $plan"
  [[ -d "$REPO_DIR" ]] || die "repo dir not found: $REPO_DIR (set --repo-dir)"

  for r in ${REVIEWERS//,/ }; do
    command -v "$r" >/dev/null 2>&1 || die "reviewer CLI not found: $r"
  done

  if [[ "$dry_run" == "1" ]]; then
    build_prompt "$plan" 1 "$(build_prior_context "$plan")"
    exit 0
  fi

  # Research must not mutate the target repo. Warn loudly if it is dirty, since a
  # read-only reviewer plus a dirty tree makes findings hard to reproduce.
  if ! git -C "$REPO_DIR" diff --quiet 2>/dev/null; then
    log_warn "$REPO_DIR has uncommitted changes — reviewers will read them as current state"
  fi
  log_info "repo under review: $REPO_DIR @ $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  log_info "plan: $plan"
  log_info "reviewers: $REVIEWERS · max passes: $MAX_PASSES · stop after $CONSECUTIVE_CLEAN clean"

  local pass=1 clean_streak=0 total_findings=0
  local workdir; workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  while (( pass <= MAX_PASSES )); do
    printf '\n%s%s══ pass %d/%d ══%s\n' "$BLD" "$BLU" "$pass" "$MAX_PASSES" "$NC" >&2

    local prior prompt pass_sub=0 pass_all=0
    prior="$(build_prior_context "$plan")"
    prompt="$(build_prompt "$plan" "$pass" "$prior")"

    local -a pass_outputs=()
    for reviewer in ${REVIEWERS//,/ }; do
      local out="$workdir/pass${pass}-${reviewer}.md"
      log_info "running $reviewer …"
      if ! "run_${reviewer}" "$prompt" "$out"; then
        log_warn "$reviewer failed or timed out on pass $pass — skipping it"
        continue
      fi
      if [[ ! -s "$out" ]]; then
        log_warn "$reviewer produced no output on pass $pass"
        continue
      fi
      local sub all
      sub="$(count_substantive "$out")"; all="$(count_all_findings "$out")"
      log_info "$reviewer: $all finding(s), $sub High/Medium"
      pass_sub=$(( pass_sub + sub )); pass_all=$(( pass_all + all ))
      pass_outputs+=("$out")
    done

    if [[ ${#pass_outputs[@]} -eq 0 ]]; then
      log_error "no reviewer produced output on pass $pass — aborting"
      exit 2
    fi

    # Append the review to the plan as a new numbered section (audit record).
    local secnum; secnum="$(next_section_number "$plan")"
    {
      printf '\n## %s. Automated Review Pass %s (%s)\n' "$secnum" "$pass" "$(git -C "$REPO_DIR" log -1 --format=%cs 2>/dev/null || echo 'unknown date')"
      printf '\n> Produced by `tools/review-plan.sh` against `%s` @ `%s`.\n' \
        "$REPO_DIR" "$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
      printf '> Reviewer(s): %s. **Findings are UNVERIFIED** — verify each against the code\n' "$REVIEWERS"
      printf '> before accepting, then record the verdict. Roughly 1 in 6 findings in this\n'
      printf '> plan'"'"'s manual history was wrong or wrong-in-form.\n'
      for out in "${pass_outputs[@]}"; do
        printf '\n<!-- reviewer: %s -->\n\n' "$(basename "$out" .md)"
        cat "$out"
        printf '\n'
      done
    } >> "$plan"

    total_findings=$(( total_findings + pass_all ))
    log_ok "appended section $secnum to $plan"

    if (( pass_sub == 0 )); then
      clean_streak=$(( clean_streak + 1 ))
      log_ok "no High/Medium findings — clean streak $clean_streak/$CONSECUTIVE_CLEAN"
    else
      clean_streak=0
      log_warn "$pass_sub High/Medium finding(s) — streak reset"
    fi

    if (( clean_streak >= CONSECUTIVE_CLEAN )); then
      printf '\n%s%sCONVERGED%s after %d pass(es); %d finding(s) total.\n' \
        "$BLD" "$GRN" "$NC" "$pass" "$total_findings" >&2
      printf '%sNext: verify each finding against the code, fold the accepted ones into the\nlive plan sections, and record a per-pass audit table.%s\n' "$DIM" "$NC" >&2
      exit 0
    fi

    pass=$(( pass + 1 ))
  done

  printf '\n%shit --max-passes (%d) without converging; %d finding(s) total.%s\n' \
    "$YLW" "$MAX_PASSES" "$total_findings" "$NC" >&2
  printf '%sStill finding High/Medium issues — worth another run, or the plan may need reworking.%s\n' "$DIM" "$NC" >&2
  exit 3
}

main "$@"

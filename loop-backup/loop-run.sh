#!/usr/bin/env bash

# loop-kit runner for dsx-ai-factory/nvke — runs ONE triage round.
#
# Repo facts come from <repo>/loop.config.yaml. The plugin supplies the machinery
# + §09 guardrails (token caps, human checkpoint, writes to .loop/ NOT .claude/ —
# the harness blocks unattended writes under .claude/).
#
# This repo adds a screening step the generic runner lacks: nvke has 24 of 82 open
# PRs that reference no issue and merges ~11 PRs/day, so `closedByPullRequestsReferences`
# is not a sufficient availability screen and any verdict is stale within a day or two.
# See ~/source/nvke-study/RESEARCH-WORKFLOW.md.
#
# Scheduled every 6h via CronCreate (cron: 0 */6 * * *).
set -euo pipefail

# Repo root: prefer the harness-provided project dir, else git, else cwd.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

log_info()    { printf '\033[0;32m[INFO]\033[0m  %s\n' "$*"; }
log_warning() { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }
log_error()   { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: loop-run.sh [--dry-run]
Runs one loop-kit triage round (triage + propose only; never edits code).
Reads ./loop.config.yaml. Env: CLAUDE_BIN=claude
EOF
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
DRY_RUN=false; [[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

CONFIG="$REPO_ROOT/loop.config.yaml"
STATE="$REPO_ROOT/.loop/state.md"
STUDY="${STUDY_DIR:-$HOME/source/nvke-study}"

# ---- preflight: fail fast before burning tokens -----------------------------
[[ -f "$CONFIG" ]] || { log_error "loop.config.yaml missing"; exit 1; }
[[ -f "$STATE"  ]] || { log_error ".loop/state.md missing"; exit 1; }

# Tiny YAML readers (flat keys / one nested level — enough for our schema).
clean() { sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'; }
yget()  { sed -n "s/^$1:[[:space:]]*//p" "$CONFIG" | head -1 | clean; }
ynest() { awk -v p="$1" -v k="$2" '
  $0 ~ "^"p":" {inb=1; next}
  inb && /^[^[:space:]]/ {inb=0}
  inb && $0 ~ "^[[:space:]]+"k":" {sub("^[[:space:]]+"k":[[:space:]]*","");print;exit}
' "$CONFIG" | clean; }

REPO="$(yget repo)"
DISCOVERY="$(yget discovery)"
ISSUES_TO_CHECK="$(yget issues_to_check)"; ISSUES_TO_CHECK="${ISSUES_TO_CHECK:-40}"
CANDIDATES="$(yget candidates_per_round)"; CANDIDATES="${CANDIDATES:-3}"
MAX_TURNS="$(ynest caps max_turns)";        MAX_TURNS="${MAX_TURNS:-30}"
MAX_RUNS="$(ynest caps max_runs_per_day)";  MAX_RUNS="${MAX_RUNS:-6}"

[[ -n "$REPO" && "$REPO" != "OWNER/NAME" ]] || { log_error "config 'repo' not set"; exit 1; }
command -v gh >/dev/null || { log_error "gh CLI not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { log_error "gh not authenticated (gh auth login)"; exit 1; }

# ---- account must match directory (RESEARCH-WORKFLOW §6) --------------------
# ~/tubi/** -> yuzhiquantubi, everywhere else -> yuzhiquan. This repo is NOT
# under ~/tubi, and the active account was found drifted to yuzhiquantubi on 2026-11-11.
# gh prints "Logged in to github.com account NAME (keyring)" then "- Active account: true"
# on a following line, so remember the most recent account name and print it when
# the active marker appears. NAME is the field after the literal "account".
ACTIVE_ACCT="$(gh auth status 2>&1 | awk '
  /Logged in to/ { for (i = 1; i < NF; i++) if ($i == "account") prev = $(i+1) }
  /Active account: true/ { print prev; exit }
')"
if [[ -n "$ACTIVE_ACCT" && "$ACTIVE_ACCT" != "yuzhiquan" ]]; then
  log_warning "gh active account is '$ACTIVE_ACCT'; this repo needs 'yuzhiquan'."
  log_warning "Fix: gh auth switch --hostname github.com --user yuzhiquan"
  # Read-only round, so warn rather than abort — but a human should fix it.
fi

# ---- research-system availability screen (this repo's addition) -------------
# The generic loop trusts closedByPullRequestsReferences. Here that misses
# branch refs, prose body refs, and the PRs (24 of 82) referencing no issue at all.
KNOWN_TAKEN="$STUDY/tools/known-taken.txt"
PR_INDEX="$STUDY/tools/pr-index.sh"
SCREEN_NOTE="none — study tools not found at $STUDY"
if [[ -f "$KNOWN_TAKEN" && -x "$PR_INDEX" ]]; then
  SCREEN_NOTE="known-taken.txt ($(grep -cE '^[0-9]+' "$KNOWN_TAKEN") issues) + pr-index.sh"
else
  log_warning "study tools missing at $STUDY — the loop will fall back to gh-only screening,"
  log_warning "which is a KNOWN-INSUFFICIENT screen for this repo (24 of 82 PRs reference no issue)."
fi

# ---- sync with upstream (read-only; RESEARCH-WORKFLOW §8.1) -------------------
# Screening against a stale tree gives false 'still missing' results (round 13
# found local main 402 commits behind on agent-sandbox). `fetch upstream main:main` fast-forwards
# main without touching the checked-out branch, and fails harmlessly if main is
# the current branch or has diverged. Never pushes.
if ! $DRY_RUN; then
  if git remote get-url upstream >/dev/null 2>&1; then
    git fetch upstream --prune --quiet && log_info "fetched upstream" || log_warning "git fetch upstream failed"
    git fetch upstream main:main --quiet 2>/dev/null || log_warning "local main not fast-forwarded (diverged or checked out)"
    UPSTREAM_SHA="$(git rev-parse --short upstream/main 2>/dev/null || echo unknown)"
  else
    log_warning "no 'upstream' remote; screening against whatever is local"
    UPSTREAM_SHA="unknown"
  fi
else
  UPSTREAM_SHA="(dry-run, not fetched)"
fi

# ---- per-day run cap (token-runaway backstop) -------------------------------
COUNT_FILE="$REPO_ROOT/.loop/.run-count"
TODAY="$(date +%Y-%m-%d)"; LAST=""; COUNT=0
[[ -f "$COUNT_FILE" ]] && IFS=' ' read -r LAST COUNT < "$COUNT_FILE" || true
[[ "$LAST" != "$TODAY" ]] && COUNT=0
if (( COUNT >= MAX_RUNS )); then
  log_error "Daily run cap reached ($COUNT/$MAX_RUNS for $TODAY). Refusing."; exit 1
fi

PROMPT="Run the loop-triage skill for this repo (repo=$REPO, discovery=$DISCOVERY,
issues_to_check=$ISSUES_TO_CHECK, candidates_per_round=$CANDIDATES).

Load loop.config.yaml first. Before drafting anything, read
$STUDY/RESEARCH-WORKFLOW.md — it documents this repo's screening rules, and every
rule there exists because a metadata-only check produced a real false positive.

Upstream was synced to $UPSTREAM_SHA before this round; record that SHA in the round log.

Screening additions that are MANDATORY for this repo:
1. Skip every issue listed in $KNOWN_TAKEN (already screened, with reasons).
   Also skip anything under Parked/Done/'Already in flight' in .loop/state.md
   unless its updatedAt is newer than what is recorded.
2a. Run '$STUDY/tools/claims.sh --self yuzhiquan' once. Unassigned is not free: an
   ACTIVE (<=30d) informal claim means taken; AGING (<=90d) means ask the claimant.
2. closedByPullRequestsReferences is NOT a sufficient screen here. Run
   'FORMAT=tsv $PR_INDEX --no-cache' and cross-check every surviving candidate
   against it. Also run '$PR_INDEX --grep <keyword>' for each candidate: open PRs
   that reference no issue at all are invisible to any issue-side check.
3. Apply rules R1-R4: read cross-referenced PRs (not just count them), read the
   LAST comment, read the BODY for author self-implementation, and read EVERY
   comment for PR announcements and maintainer rulings.
4. Distinguish available from actionable. An item can be free but BLOCKED on
   unmerged work — grep the tree for the extension point it claims to plug into.
   Park blocked items as blocked, with the missing symbol named.
5. Weigh evidence by source: body/title refs are strong, branch refs are weak.
6. R5 freshness: nvke merges ~11 PRs/day and maintainers usually file an issue and open
   the fix within hours. An issue under ~3 days old is in-flight maintainer work; Park it
   with a re-look date rather than proposing code. Re-run 'FORMAT=tsv $PR_INDEX --no-cache'
   before quoting ANY verdict from an earlier round.
7. R6 testability: Actionable requires a proof runnable on this machine:
   'make -C <module> test' and 'make -C <module> lint' (GNU Make 3.81 cannot run the root
   Makefile, so 'make preflight' is not available). e2e / image-build / Forge-only changes
   are Parked, say why.
7a. READ each cross-referenced PR's diff before calling an issue taken OR free; a PR without
   a closing keyword is TAKEN? (adjacent), not TAKEN. Batches by one maintainer (e.g. 28
   os-image issues from one author) are one owner's plan: Park the batch, do not screen
   them as 28 free issues.
8. For every issue found taken or parked, append a line to $KNOWN_TAKEN with the
   PR number or re-look condition.

Then draft fix proposals, run the independent skeptic evaluator, and record
results in .loop/state.md. Propose only — do not edit code, run git, open PRs, or
comment on issues. Print the 3-line summary and stop."

if $DRY_RUN; then
  log_info "[dry-run] repo=$REPO discovery=$DISCOVERY issues=$ISSUES_TO_CHECK candidates=$CANDIDATES"
  log_info "[dry-run] max-turns=$MAX_TURNS cap=$MAX_RUNS screen=$SCREEN_NOTE"
  log_info "[dry-run] prompt:"; printf '%s\n' "$PROMPT"; exit 0
fi
command -v "$CLAUDE_BIN" >/dev/null || { log_error "$CLAUDE_BIN not on PATH"; exit 1; }

log_info "Triage round starting for $REPO (run $((COUNT+1))/$MAX_RUNS today, max-turns=$MAX_TURNS)"
log_info "Screen: $SCREEN_NOTE"
# acceptEdits auto-accepts file writes (no prompt); the allowlist permits only
# triage tools + writes. git / PR / issue-mutation tools are explicitly denied.
# pr-index.sh and screen-issues.sh are allowed because they are read-only.
"$CLAUDE_BIN" -p "$PROMPT" \
  --max-turns "$MAX_TURNS" \
  --permission-mode acceptEdits \
  --allowedTools "Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh pr list:*),Bash(gh pr view:*),Bash(gh api:*),Bash(gh run list:*),Bash($PR_INDEX:*),Bash($STUDY/tools/screen-issues.sh:*),Bash($STUDY/tools/claims.sh:*),Grep,Glob,Read,Edit,Write" \
  --disallowedTools "Bash(git:*),Bash(gh pr create:*),Bash(gh pr edit:*),Bash(gh pr comment:*),Bash(gh pr review:*),Bash(gh issue edit:*),Bash(gh issue comment:*),Bash(gh issue create:*),WebFetch"

printf '%s %d\n' "$TODAY" "$((COUNT+1))" > "$COUNT_FILE"
log_info "Round done. Review proposals in .loop/state.md (Actionable section)."

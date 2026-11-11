#!/usr/bin/env bash
#
# screen-issues.sh — apply the four availability rules to GitHub issues and
# report which are genuinely free to work on.
#
# Every rule here exists because a metadata-only check produced a false
# positive on a real issue in kubernetes-sigs/agent-sandbox:
#
#   R1  cross-referenced PRs, regardless of closing keyword or assignee.
#       #968 had FOUR open PRs (incl. the maintainer's own KEP) while looking
#       unassigned and unlinked, because none used "Fixes #".
#   R2  the LAST COMMENT, not the metadata.
#       #225 was OPEN with an assignee and a merged PR — finished work nobody
#       ever closed ("#240 was merged ... we can close this issue").
#   R3  the BODY, for author self-implementation.
#       #1157's author had a finished 14-commit POC on a fork and no PR filed.
#   R4  EVERY comment, for PR announcements and design history.
#       #764 had "Fixed in #1078. PTAL" in a comment. Comments also carry
#       decisions found nowhere else — #764's proposed fix had already been
#       built and REVERTED in #347 for breaking OnReplenish.
#
# The script decides nothing on its own: it emits evidence and a TRIAGE verdict.
# A HUMAN-REVIEW verdict means "read the linked evidence", not "unavailable".

set -euo pipefail

REPO="${REPO:-dsx-ai-factory/nvke}"
CACHE_DIR="${CACHE_DIR:-${TMPDIR:-/tmp}/screen-issues-cache}"
FORMAT="${FORMAT:-text}"
JOBS="${JOBS:-4}"
PROFILE="${PROFILE:-nvke}"   # default so a bare call cannot silently disable the label heuristics
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Label vocabulary. Defaults are Kubernetes/prow conventions for backward
# compatibility; a --profile file overrides them. The FOUR SCREENING RULES are
# ecosystem-independent (they read timelines, bodies and comments, not labels) —
# only these label heuristics need per-project configuration.
SKIP_LABELS="${SKIP_LABELS:-lifecycle/rotten,lifecycle/frozen,lifecycle/stale}"
PROPOSAL_LABELS="${PROPOSAL_LABELS:-priority/awaiting-more-evidence}"
PROCESS_LABELS="${PROCESS_LABELS:-kind/api-change}"
INVITE_LABELS="${INVITE_LABELS:-help wanted,good first issue}"
PRIORITY_PREFIX="${PRIORITY_PREFIX:-priority/}"
PRIORITY_ORDER="${PRIORITY_ORDER:-critical-urgent,important-soon,important-longterm,backlog}"
PROCESS_ARTIFACT="${PROCESS_ARTIFACT:-KEP}"

# Account/directory guard. Both are optional: set ACCOUNT_DIR_PREFIX and
# ACCOUNT_FOR_DIR to warn when the active gh identity does not match where you
# are working. Unset = no check, which is right for anyone but the author.
ACCOUNT_DIR_PREFIX="${ACCOUNT_DIR_PREFIX:-}"
ACCOUNT_FOR_DIR="${ACCOUNT_FOR_DIR:-}"

load_profile() {
  local name="$1" file
  for file in "$name" "$SCRIPT_DIR/profiles/$name.conf" "$SCRIPT_DIR/profiles/$name"; do
    if [[ -r "$file" ]]; then
      # shellcheck disable=SC1090
      source "$file"
      log_info "profile: $(basename "$file")"
      return 0
    fi
  done
  die "profile not found: $name (looked in $SCRIPT_DIR/profiles/)"
}

# Does the comma-joined label list contain any of a comma-list of needles?
labels_match() {
  local labels="$1" needles="$2" n
  [[ -z "$needles" ]] && return 1
  local IFS=,
  for n in $needles; do
    [[ -n "$n" && "$labels" == *"$n"* ]] && return 0
  done
  return 1
}

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; BLU=$'\033[0;34m'
DIM=$'\033[2m'; BLD=$'\033[1m'; NC=$'\033[0m'
[[ -t 1 ]] || { RED=""; GRN=""; YLW=""; BLU=""; DIM=""; BLD=""; NC=""; }

log_info()  { printf '%s[info]%s %s\n'  "$BLU" "$NC" "$*" >&2; }
log_warn()  { printf '%s[warn]%s %s\n'  "$YLW" "$NC" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n' "$RED" "$NC" "$*" >&2; }

usage() {
  cat <<'EOF'
Usage:
  screen-issues.sh [options] <issue-number> [issue-number ...]
  screen-issues.sh [options] --discover

Applies four availability rules to each issue and prints the evidence plus a
triage verdict. Never claims an issue is available without showing why.

Options:
  --discover            Screen open unassigned issues found via search
  --limit N             Max issues to discover (default 40)
  --labels "a,b"        Only discover issues carrying ALL these labels
  --min-priority P      Keep only these priorities; repeatable-ish comma list.
                        e.g. "important-soon,important-longterm"
  --skip-taken FILE     Newline-separated issue numbers to skip (comments with #)
  --profile NAME        Label vocabulary profile: kubernetes | github-generic |
                        area-component | /path/to/custom.conf
                        (default: Kubernetes/prow conventions)
  --format text|md|json Output format (default text)
  --repo OWNER/NAME     Target repo (default dsx-ai-factory/nvke)
  --no-cache            Bypass the API response cache
  --jobs N              Parallel issue fetches (default 4)
  -h, --help            This help

Verdicts:
  AVAILABLE      no blocking signal found on any rule
  HUMAN-REVIEW   a signal needs a human read (evidence is printed)
  TAKEN          an open PR, assignee, or explicit claim was found
  DONE-UNCLOSED  a merged PR plus closing language in the last comments

Exit status: 0 if any issue is AVAILABLE, 1 if none are, 2 on usage/tooling error.

Examples:
  screen-issues.sh 1214 949 643
  screen-issues.sh --discover --min-priority important-soon --limit 20
  FORMAT=md screen-issues.sh --discover --skip-taken taken.txt > report.md
EOF
}

die() { log_error "$*"; exit 2; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

# ---------------------------------------------------------------- API plumbing

# Cache API responses so re-runs during a research session are cheap and so a
# rate-limit mid-run does not lose earlier work.
api() {
  local path="$1"
  local key file
  key="$(printf '%s' "$path" | tr -c 'a-zA-Z0-9._-' '_')"
  file="$CACHE_DIR/$key.json"

  if [[ "${NO_CACHE:-0}" != "1" && -s "$file" ]]; then
    cat "$file"
    return 0
  fi

  mkdir -p "$CACHE_DIR"
  if ! gh api "$path" --paginate > "$file.tmp" 2>"$file.err"; then
    log_warn "API call failed: $path ($(tr -d '\n' < "$file.err" | cut -c1-160))"
    rm -f "$file.tmp" "$file.err"
    return 1
  fi
  rm -f "$file.err"
  mv "$file.tmp" "$file"
  cat "$file"
}

check_auth() {
  local active
  if ! active="$(gh auth status 2>&1 | grep -B1 'Active account: true' | grep -oE 'account [A-Za-z0-9-]+' | awk '{print $2}' | head -1)"; then
    die "gh not authenticated — run: gh auth login"
  fi
  [[ -n "$active" ]] || die "could not determine active gh account"
  log_info "gh active account: ${BLD}${active}${NC}"
  # Optional multi-account guard: a wrong-account `/assign` has happened before.
  # Configure via ACCOUNT_DIR_PREFIX + ACCOUNT_FOR_DIR (both unset = no check).
  if [[ -n "$ACCOUNT_DIR_PREFIX" && -n "$ACCOUNT_FOR_DIR" ]]; then
    if [[ "$PWD" == "$ACCOUNT_DIR_PREFIX"* ]]; then
      [[ "$active" == "$ACCOUNT_FOR_DIR" ]] || \
        log_warn "under $ACCOUNT_DIR_PREFIX but active account is '$active' (expected $ACCOUNT_FOR_DIR)"
    else
      [[ "$active" != "$ACCOUNT_FOR_DIR" ]] || \
        log_warn "outside $ACCOUNT_DIR_PREFIX but active account is '$ACCOUNT_FOR_DIR' — writes would use the wrong identity"
    fi
  fi
}

# ---------------------------------------------------------------- the 4 rules

# R1: cross-referenced PRs. Read them — an issue can carry both a fixing PR and
# unrelated ones — so emit number+state+author+title for a human to judge.
rule1_xref_prs() {
  local n="$1"
  # MUST filter on repository_url: cross-references can come from FORKS and other
  # repos entirely. On pallets/flask#6065 the timeline lists "PR #1" from
  # AdarshJ173/flask (a fork) alongside the two real pallets/flask PRs — reporting
  # a fork's PR #1 as if it were upstream #1 is badly misleading. Found only by
  # testing the tool against a second repository.
  api "repos/$REPO/issues/$n/timeline?per_page=100" 2>/dev/null | jq -s --arg repo "$REPO" '
    [ .[] | .[]?
      | select(.event == "cross-referenced")
      | select(.source.issue.pull_request != null)
      | select(((.source.issue.repository_url // "") | split("/") | .[-2:] | join("/")) == $repo)
      | { num: .source.issue.number,
          state: (if .source.issue.pull_request.merged_at != null then "merged" else .source.issue.state end),
          author: .source.issue.user.login,
          title: .source.issue.title }
    ] | unique_by(.num)' 2>/dev/null || echo '[]'
}

# R2 + R4: all comments. Returns author/date/body so downstream can scan for
# claims, PR announcements, closing language, and maintainer rulings.
rule2_4_comments() {
  local n="$1"
  api "repos/$REPO/issues/$n/comments?per_page=100" 2>/dev/null | jq -s '
    [ .[] | .[]?
      | select((.user.login // "") | test("bot$|^k8s-ci-robot$|^netlify|coderabbit|copilot"; "i") | not)
      | { author: .user.login, date: (.created_at[0:10]), body: .body }
    ]' 2>/dev/null || echo '[]'
}

CLAIM_RE='(fixed|fixes|resolved|addressed|implemented) (in|by|via) *#?[0-9]{2,5}|(^|[^a-z])PTAL|I(.| )?(ll|will|m going to| am going to| have|ve) (work|take|pick|open|submit|start)|working on (this|it)|assign (me|this to me)|/assign|took? this on|mine now'
CLOSED_RE='can (be )?close|should (be )?close|closing this|this is (now )?(done|complete|fixed|resolved)|no longer needed|already (done|fixed|implemented|merged)|was merged'
# Two families here, both learned the hard way:
#   (a) the author ALREADY has code (#1157: finished POC on a fork, no PR filed)
#   (b) the author OFFERS to write it, conditional on maintainer buy-in
#       (#802: "Happy to write a small KEP and the implementation PR if the
#       direction is endorsed" — missed by the original regex, which only matched
#       the exact phrase "happy to open a pr")
# (b) is not a hard claim, but it means "coordinate before starting", so it must
# surface rather than being reported as clean AVAILABLE.
SELFIMPL_RE='I have a (working )?(POC|proof.of.concept|prototype|implementation|branch)|on (a|my) fork|fork branch|I.ve been working on|my (POC|branch|fork)|draft (PR|branch) (is|at)|(happy|glad|willing|would be happy)( and \w+)? to (write|open|submit|implement|contribute|do|take|pick up|help with)|I ((can|could|will|would|plan to|intend to)( also)? (write|open|submit|implement|contribute|take|pick up|start))|if the direction is endorsed'

# R3: body self-implementation signals.
rule3_body_signals() {
  local n="$1"
  api "repos/$REPO/issues/$n" 2>/dev/null | jq -r '.body // ""' 2>/dev/null \
    | grep -oiE "$SELFIMPL_RE" | sort -u | head -5 || true
}

issue_meta() {
  local n="$1"
  # Delimiter is US (0x1f), NOT tab: tab is an IFS *whitespace* character, so
  # bash `read` collapses runs of tabs and an empty field (e.g. no assignees)
  # silently shifts every later field left. Cost me a wrong "assigned to:
  # kind/feature" on the first test run.
  api "repos/$REPO/issues/$n" 2>/dev/null | jq -r '
    [ (.state // "?"),
      ((.assignees // []) | map(.login) | join(",")),
      ((.labels // []) | map(.name) | join(",")),
      (.user.login // "?"),
      (.created_at[0:10] // "?"),
      (.updated_at[0:10] // "?"),
      (.title // "?"),
      (if .pull_request then "IS_PR" else "ISSUE" end)
    ] | join("")' 2>/dev/null || return 1
}

# ------------------------------------------------------------------- screening

# Emits one JSON object per issue: metadata + per-rule evidence + verdict.
screen_one() {
  local n="$1" meta
  if ! meta="$(issue_meta "$n")" || [[ -z "$meta" ]]; then
    jq -cn --arg n "$n" '{number:($n|tonumber), verdict:"ERROR", reasons:["could not fetch issue"]}'
    return
  fi

  local state assignees labels author created updated title kind
  IFS=$'\x1f' read -r state assignees labels author created updated title kind <<<"$meta"

  if [[ "$kind" == "IS_PR" ]]; then
    jq -cn --arg n "$n" '{number:($n|tonumber), verdict:"ERROR", reasons:["this is a PR, not an issue"]}'
    return
  fi

  local xrefs comments body_sig
  xrefs="$(rule1_xref_prs "$n")"
  comments="$(rule2_4_comments "$n")"
  body_sig="$(rule3_body_signals "$n" | paste -sd'; ' -)"

  local open_prs merged_prs
  open_prs="$(jq -r '[.[] | select(.state=="open")] | length' <<<"$xrefs")"
  merged_prs="$(jq -r '[.[] | select(.state=="merged")] | length' <<<"$xrefs")"

  # R4: scan comment bodies for claims / PR refs / closing language.
  # Volunteer offers must be scanned in COMMENTS too, not just the body (R3's
  # domain). #1140's author wrote "I'll be happy to implement if maintainers find
  # this issue useful" as a comment — the R3 regex matched the phrasing fine, but
  # R3 only ever read the body, so the offer was invisible and the issue screened
  # clean. Found by reading, not by the tool.
  local claim_hits closing_hits pr_refs last_author last_date volunteer_hits
  claim_hits="$(jq -r '.[] | .author + ": " + .body' <<<"$comments" | grep -oiE "$CLAIM_RE" | sort -u | paste -sd'; ' - || true)"
  volunteer_hits="$(jq -r '.[] | .body' <<<"$comments" | grep -oiE "$SELFIMPL_RE" | sort -u | paste -sd'; ' - || true)"
  closing_hits="$(jq -r '.[-2:] | .[]? | .body' <<<"$comments" | grep -oiE "$CLOSED_RE" | sort -u | paste -sd'; ' - || true)"
  pr_refs="$(jq -r '.[] | .body' <<<"$comments" | grep -oE 'pull/[0-9]+|#[0-9]{2,5}' | sed 's|pull/|#|' | sort -u | paste -sd' ' - || true)"
  last_author="$(jq -r '.[-1].author // ""' <<<"$comments")"
  last_date="$(jq -r '.[-1].date // ""' <<<"$comments")"

  local -a reasons=() verdict="AVAILABLE"

  [[ "$state" != "open" ]] && { verdict="TAKEN"; reasons+=("issue state is $state"); }

  if [[ -n "$assignees" ]]; then
    verdict="TAKEN"; reasons+=("assigned to: $assignees")
  fi

  if [[ "$open_prs" -gt 0 ]]; then
    verdict="TAKEN"
    reasons+=("R1: $open_prs open cross-referenced PR(s) — READ them, some may be unrelated: $(jq -r '[.[]|select(.state=="open")|"#\(.num) by \(.author)"]|join(", ")' <<<"$xrefs")")
  fi

  if [[ -n "$claim_hits" ]]; then
    verdict="TAKEN"; reasons+=("R4: claim/announcement language in comments: $claim_hits")
  fi

  if [[ "$merged_prs" -gt 0 && -n "$closing_hits" ]]; then
    verdict="DONE-UNCLOSED"
    reasons+=("R2: merged PR(s) $(jq -r '[.[]|select(.state=="merged")|"#\(.num)"]|join(",")' <<<"$xrefs") + closing language in last comments: $closing_hits")
  elif [[ "$merged_prs" -gt 0 && "$verdict" == "AVAILABLE" ]]; then
    verdict="HUMAN-REVIEW"
    reasons+=("R2: $merged_prs merged cross-referenced PR(s) — confirm they did not already resolve this: $(jq -r '[.[]|select(.state=="merged")|"#\(.num)"]|join(",")' <<<"$xrefs")")
  fi

  if [[ -n "$body_sig" ]]; then
    verdict="TAKEN"; reasons+=("R3: author self-implementation signal in body: $body_sig")
  fi

  if [[ -n "$volunteer_hits" ]]; then
    verdict="TAKEN"; reasons+=("R3/R4: volunteer or self-implementation signal in COMMENTS: $volunteer_hits")
  fi

  # Non-blocking things a human still must read.
  local -a notes=()
  [[ -n "$pr_refs" ]] && notes+=("PR/issue refs mentioned in comments: $pr_refs")
  [[ "$(jq 'length' <<<"$comments")" -gt 0 ]] && notes+=("last comment: @$last_author on $last_date — R2/R4 require reading it")
  labels_match "$labels" "$SKIP_LABELS"     && notes+=("stale/closed-ish label — likely not worth planning")
  labels_match "$labels" "$PROPOSAL_LABELS" && notes+=("proposal-stage label — expect a design/${PROCESS_ARTIFACT}, not code")
  labels_match "$labels" "$PROCESS_LABELS"  && notes+=("process label — ask about ${PROCESS_ARTIFACT} requirement before coding")
  labels_match "$labels" "$INVITE_LABELS"   && notes+=("⭐ maintainers invited help on this one")

  if [[ "$verdict" == "AVAILABLE" && "$(jq 'length' <<<"$comments")" -gt 0 ]]; then
    verdict="HUMAN-REVIEW"
    reasons+=("has $(jq 'length' <<<"$comments") comment(s); rules R2+R4 cannot be fully automated — read them")
  fi

  jq -cn \
    --arg n "$n" --arg state "$state" --arg asg "$assignees" --arg labels "$labels" \
    --arg author "$author" --arg created "$created" --arg updated "$updated" \
    --arg title "$title" --arg verdict "$verdict" \
    --argjson xrefs "$xrefs" \
    --argjson ncomments "$(jq 'length' <<<"$comments")" \
    --arg reasons "$(printf '%s\n' "${reasons[@]:-}")" \
    --arg notes "$(printf '%s\n' "${notes[@]:-}")" \
    '{
      number: ($n|tonumber), title: $title, state: $state, author: $author,
      created: $created, updated: $updated,
      assignees: ($asg | if . == "" then [] else split(",") end),
      labels: ($labels | if . == "" then [] else split(",") end),
      comments: $ncomments, xref_prs: $xrefs, verdict: $verdict,
      reasons: ($reasons | split("\n") | map(select(length>0))),
      notes: ($notes | split("\n") | map(select(length>0))),
      url: ("https://github.com/'"$REPO"'/issues/" + $n)
    }'
}

# ------------------------------------------------------------------- discovery

discover() {
  local limit="${1:-40}"
  local q="repo:$REPO is:issue is:open no:assignee"
  [[ -n "${LABELS:-}" ]] && for l in ${LABELS//,/ }; do q+=" label:$l"; done
  log_info "searching: $q"
  # Do NOT swallow stderr here: a secondary-rate-limit 403 otherwise looks exactly
  # like "this repo has no open unassigned issues", which sent me debugging a
  # non-existent tool bug on prometheus/prometheus.
  local rows err
  err="$(mktemp)"
  rows="$(gh api -X GET "search/issues" -f q="$q" -F per_page=100 --paginate \
    --jq '.items[] | [(.number|tostring), ((.labels//[])|map(.name)|join(","))] | @tsv' 2>"$err")" || {
      log_error "issue search failed: $(tr -d '\n' < "$err" | cut -c1-200)"
      rm -f "$err"
      die "cannot discover issues (rate limit? auth? wrong --repo?)"
    }
  if [[ -s "$err" ]] && grep -qi "rate limit" "$err"; then
    log_warn "search hit a rate limit; results may be incomplete: $(tr -d '\n' < "$err" | cut -c1-140)"
  fi
  rm -f "$err"
  if [[ -z "$rows" ]]; then
    log_warn "search returned no open unassigned issues for $REPO — verify the repo name and that this is expected"
  fi

  # Priority filter: only when the profile defines a prefix AND the caller asked.
  if [[ -n "${MIN_PRIORITY:-}" ]]; then
    if [[ -n "$PRIORITY_PREFIX" ]]; then
      rows="$(grep -E "${PRIORITY_PREFIX}(${MIN_PRIORITY//,/|})" <<<"$rows" || true)"
    else
      log_warn "--min-priority ignored: profile defines no PRIORITY_PREFIX (this project has no priority labels)"
    fi
  fi

  # Drop skip-labelled issues, honouring the profile's vocabulary.
  local out="" num lbls
  while IFS=$'\t' read -r num lbls; do
    [[ -z "$num" ]] && continue
    labels_match "$lbls" "$SKIP_LABELS" && continue
    out+="$num"$'\n'
  done <<<"$rows"
  printf '%s' "$out" | grep -c . >/dev/null && printf '%s' "$out" | head -"$limit"
}

# --------------------------------------------------------------------- output

emit_text() {
  local json="$1" any=0
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local v n t
    v="$(jq -r '.verdict' <<<"$row")"; n="$(jq -r '.number' <<<"$row")"; t="$(jq -r '.title' <<<"$row")"
    local color="$DIM"
    case "$v" in
      AVAILABLE)     color="$GRN"; any=1 ;;
      HUMAN-REVIEW)  color="$YLW"; any=1 ;;
      TAKEN)         color="$RED" ;;
      DONE-UNCLOSED) color="$RED" ;;
    esac
    printf '\n%s%s#%-5s %-13s%s %s\n' "$BLD" "$color" "$n" "$v" "$NC" "$t"
    printf '  %s%s%s\n' "$DIM" "$(jq -r '.url' <<<"$row")" "$NC"
    printf '  labels: %s\n' "$(jq -r '(.labels|join(", ")) // "-"' <<<"$row")"
    printf '  opened %s by @%s · updated %s · %s comment(s)\n' \
      "$(jq -r .created <<<"$row")" "$(jq -r .author <<<"$row")" \
      "$(jq -r .updated <<<"$row")" "$(jq -r .comments <<<"$row")"
    jq -r '.reasons[]? | "  ✗ " + .' <<<"$row"
    jq -r '.notes[]?   | "  · " + .' <<<"$row"
    jq -r '.xref_prs[]? | "  → PR #\(.num) [\(.state)] by \(.author): \(.title)"' <<<"$row"
  done <<<"$json"
  printf '\n'
  return $(( any == 1 ? 0 : 1 ))
}

emit_md() {
  local json="$1"
  printf '# Availability screen — %s\n\n' "$REPO"
  printf 'Screened %s issue(s). Verdicts are triage, not conclusions: `HUMAN-REVIEW` means read the evidence.\n\n' "$(grep -c . <<<"$json")"
  printf '| Issue | Verdict | Labels | Comments | Evidence |\n|---|---|---|---|---|\n'
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    printf '| [#%s](%s) | %s | %s | %s | %s |\n' \
      "$(jq -r .number <<<"$row")" "$(jq -r .url <<<"$row")" "$(jq -r .verdict <<<"$row")" \
      "$(jq -r '.labels|join(", ")' <<<"$row")" "$(jq -r .comments <<<"$row")" \
      "$(jq -r '[(.reasons[]?),(.notes[]?)] | join("<br>") | gsub("\\|";"\\\\|")' <<<"$row")"
  done <<<"$json"
  printf '\n## Titles\n\n'
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    printf -- '- **#%s** %s\n' "$(jq -r .number <<<"$row")" "$(jq -r .title <<<"$row")"
  done <<<"$json"
}

# ----------------------------------------------------------------------- main

main() {
  need gh; need jq

  local -a issues=()
  local do_discover=0 limit=40 skip_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --discover)     do_discover=1; shift ;;
      --limit)        limit="${2:?}"; shift 2 ;;
      --labels)       LABELS="${2:?}"; shift 2 ;;
      --min-priority) MIN_PRIORITY="${2:?}"; shift 2 ;;
      --profile)      PROFILE="${2:?}"; shift 2 ;;
      --skip-taken)   skip_file="${2:?}"; shift 2 ;;
      --format)       FORMAT="${2:?}"; shift 2 ;;
      --repo)         REPO="${2:?}"; shift 2 ;;
      --no-cache)     NO_CACHE=1; shift ;;
      --jobs)         JOBS="${2:?}"; shift 2 ;;
      -h|--help)      usage; exit 0 ;;
      -*)             die "unknown option: $1 (try --help)" ;;
      *)              issues+=("$1"); shift ;;
    esac
  done

  [[ -n "$PROFILE" ]] && load_profile "$PROFILE"

  check_auth

  if [[ "$do_discover" == "1" ]]; then
    log_info "discovering open unassigned issues (limit $limit)"
    mapfile -t issues < <(discover "$limit")
  fi

  [[ ${#issues[@]} -gt 0 ]] || die "no issues to screen (pass numbers or --discover)"

  if [[ -n "$skip_file" ]]; then
    [[ -r "$skip_file" ]] || die "cannot read --skip-taken file: $skip_file"
    local -a keep=()
    for n in "${issues[@]}"; do
      grep -qE "^[[:space:]]*${n}([[:space:]]|#|$)" "$skip_file" || keep+=("$n")
    done
    log_info "skipped $(( ${#issues[@]} - ${#keep[@]} )) known-taken issue(s)"
    issues=("${keep[@]}")
  fi

  log_info "screening ${#issues[@]} issue(s) with ${JOBS} parallel fetches"

  local results
  results="$(printf '%s\n' "${issues[@]}" \
    | xargs -P "$JOBS" -I{} bash -c 'screen_one "$@"' _ {} 2>/dev/null \
    | jq -c '.' 2>/dev/null || true)"

  # xargs cannot see shell functions; re-run serially if the parallel path
  # produced nothing usable.
  if [[ -z "$results" ]]; then
    results=""
    for n in "${issues[@]}"; do
      results+="$(screen_one "$n")"$'\n'
    done
  fi

  results="$(grep -c . <<<"$results" >/dev/null && printf '%s' "$results" | sort -t: -k2 -n)"
  results="$(printf '%s\n' "$results" | jq -c -s 'sort_by(
      (if .verdict=="AVAILABLE" then 0 elif .verdict=="HUMAN-REVIEW" then 1 elif .verdict=="DONE-UNCLOSED" then 2 elif .verdict=="TAKEN" then 3 else 4 end),
      .number) | .[]' 2>/dev/null || printf '%s\n' "$results")"

  case "$FORMAT" in
    json) jq -c -s '.' <<<"$results" ;;
    md)   emit_md "$results" ;;
    text) emit_text "$results" ;;
    *)    die "unknown --format: $FORMAT" ;;
  esac
}

export -f api rule1_xref_prs rule2_4_comments rule3_body_signals issue_meta screen_one
export REPO CACHE_DIR CLAIM_RE CLOSED_RE SELFIMPL_RE

main "$@"

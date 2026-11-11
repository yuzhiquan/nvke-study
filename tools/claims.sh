#!/usr/bin/env bash
#
# claims.sh — bulk sweep of open issues for informal claims ("I'll take this",
# "happy to implement", "/assign", "I have a branch on my fork").
#
# WHY THIS EXISTS
#
# "Unassigned" is not "free". On 2026-11-01, 30 of 80 unassigned issues in
# kubernetes-sigs/agent-sandbox were already in flight: 14 had a PR, 9 had only a
# spoken claim, 7 had both. screen-issues.sh catches these one issue at a time
# (R3/R4) but prints no dates, so a claim made yesterday looks the same as one made
# three months ago and then abandoned. pr-index.sh sees PRs, never claims.
#
# This tool answers, in ONE `gh issue list` call:
#   * who claimed which issue, with what words, and when
#   * how old is the claim (ACTIVE / AGING / LAPSED)
#   * does the issue also have an open PR (via pr-index.sh, if next to this file)
#
# It is a heuristic: it emits evidence for a human, it never decides. Known false
# positives are handled by labelling, not hiding: a bot echo of /assign is dropped by
# author, and your own claims are shown as SELF so you can see them but not mistake
# them for competition.

set -euo pipefail

REPO="${REPO:-dsx-ai-factory/nvke}"
SELF_LOGIN="${SELF_LOGIN:-}"
ACTIVE_DAYS="${ACTIVE_DAYS:-30}"
LAPSED_DAYS="${LAPSED_DAYS:-90}"
FORMAT="${FORMAT:-text}"
INCLUDE_ASSIGNED=0
LIMIT="${LIMIT:-500}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; BLU=$'\033[0;34m'
DIM=$'\033[2m'; BLD=$'\033[1m'; NC=$'\033[0m'
[[ -t 1 ]] || { RED=""; GRN=""; YLW=""; BLU=""; DIM=""; BLD=""; NC=""; }

log_info()  { printf '%s[info]%s %s\n'  "$BLU" "$NC" "$*" >&2; }
log_warn()  { printf '%s[warn]%s %s\n'  "$YLW" "$NC" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n' "$RED" "$NC" "$*" >&2; }
die() { log_error "$*"; exit 2; }

usage() {
  cat <<'EOF'
Usage: claims.sh [options]

Sweeps open issues for informal claims and reports claimant, date, and age.

Options:
  --repo OWNER/NAME     Target repo (default dsx-ai-factory/nvke)
  --self LOGIN          Your login; your own claims are shown as SELF
  --active-days N       A claim newer than N days is ACTIVE (default 30)
  --lapsed-days N       A claim older than N days is LAPSED (default 90)
  --include-assigned    Also scan issues that already have an assignee
  --format FMT          text | tsv (default text)
  --issue N             Only this issue
  -h, --help            This help

Age buckets, by the NEWEST claim on the issue:
  ACTIVE   treat as taken; coordinate before starting
  AGING    ask the claimant whether they are still on it
  LAPSED   probably released, but say so on the issue before you start

Environment: REPO, SELF_LOGIN, ACTIVE_DAYS, LAPSED_DAYS, FORMAT, LIMIT.
Requires gh (authenticated) and jq.
EOF
}

# Claim phrasing. Two families, same as screen-issues.sh:
#   (a) the author already has code (POC / branch / fork)
#   (b) someone offers or announces they will take it
CLAIM_RE="\\b(i('|’)?ll|i will|i can|i could|i would|i'?d|i am going to|i'?m going to) (like to |love to |be happy to |also )?(take|work|pick|implement|open|submit|start|write|contribute)|\\b(happy|glad|willing|keen)( and \\w+)? to (take|work|pick|implement|open|submit|start|write|contribute|do)|working on (this|it)|taking this|i'?m (working|implementing)|started (working|implementing)|can i (take|work|pick)|assign (me|this to me)|(^|[[:space:]])/assign([[:space:]]|\$)|i have a (working )?(poc|prototype|branch|fork|implementation)|on (a|my) fork|my (poc|branch|fork)"
BOT_RE="bot\$|^k8s-ci-robot\$|^netlify|coderabbit|copilot|^k8s-triage-robot\$|^kubernetes-prow"

main() {
  local only_issue="" a
  while [[ $# -gt 0 ]]; do
    a="$1"
    case "$a" in
      --repo)             REPO="${2:?}"; shift 2 ;;
      --self)             SELF_LOGIN="${2:?}"; shift 2 ;;
      --active-days)      ACTIVE_DAYS="${2:?}"; shift 2 ;;
      --lapsed-days)      LAPSED_DAYS="${2:?}"; shift 2 ;;
      --include-assigned) INCLUDE_ASSIGNED=1; shift ;;
      --format)           FORMAT="${2:?}"; shift 2 ;;
      --issue)            only_issue="${2:?}"; shift 2 ;;
      -h|--help)          usage; exit 0 ;;
      *)                  die "unknown option: $a (try --help)" ;;
    esac
  done
  command -v gh >/dev/null || die "missing required tool: gh"
  command -v jq >/dev/null || die "missing required tool: jq"

  local issues pr_refd="" now
  log_info "fetching open issues from $REPO"
  issues="$(gh issue list -R "$REPO" --state open --limit "$LIMIT" \
    --json number,title,assignees,author,body,createdAt,comments)" \
    || die "gh issue list failed (rate limit or auth?)"

  # PRs: reuse pr-index.sh when it sits next to this file. Strong refs only; a
  # number in a branch name is too weak to say "has a PR".
  if [[ -x "$HERE/pr-index.sh" ]]; then
    pr_refd="$(REPO="$REPO" FORMAT=tsv "$HERE/pr-index.sh" --no-cache 2>/dev/null \
      | awk -F'\t' 'NR>1 && $3!="branch"{print $1":"$2}' | sort -u | paste -sd, - || true)"
  else
    log_warn "pr-index.sh not found next to claims.sh; PR column will be empty"
  fi
  now="$(date -u +%s)"

  local rows
  rows="$(jq -r \
    --arg re "$CLAIM_RE" --arg bots "$BOT_RE" --arg self "$SELF_LOGIN" \
    --arg prs "$pr_refd" --argjson now "$now" \
    --argjson active "$ACTIVE_DAYS" --argjson lapsed "$LAPSED_DAYS" \
    --argjson inc "$INCLUDE_ASSIGNED" --arg only "$only_issue" '
    ($prs | split(",") | map(select(length>0) | split(":") | {k: .[0], v: .[1]})
          | group_by(.k) | map({key: .[0].k, value: map(.v)}) | from_entries) as $prmap
    | .[]
    | select($only == "" or (.number|tostring) == $only)
    | select($inc == 1 or (.assignees|length) == 0)
    | . as $i
    | ( [ { who: $i.author.login, date: $i.createdAt, text: ($i.body // ""), src: "body" } ]
        + [ $i.comments[] | { who: .author.login, date: .createdAt, text: .body, src: "comment" } ]
      )
    | map(select((.who // "") | test($bots; "i") | not))
    | map(select(.text | test($re; "i")))
    | map(. + { hit: (.text | [match($re; "gi").string] | first) })
    | select(length > 0)
    | sort_by(.date) | last as $c
    | (($now - ($c.date | fromdateiso8601)) / 86400 | floor) as $age
    | [ $i.number,
        (if $age <= $active then "ACTIVE" elif $age <= $lapsed then "AGING" else "LAPSED" end),
        $age,
        ($c.who + (if $c.who == $self then " (SELF)" else "" end)),
        $c.src,
        ($c.hit | gsub("[\t\n]"; " ")),
        (($prmap[($i.number|tostring)] // []) | map("#" + .) | join(" ")),
        ($i.title | .[0:60])
      ] | @tsv' <<<"$issues")"

  if [[ -z "$rows" ]]; then
    log_info "no informal claims found"
    exit 0
  fi

  # Sort: bucket order, then newest claim first.
  rows="$(awk -F'\t' 'BEGIN{o["ACTIVE"]=1;o["AGING"]=2;o["LAPSED"]=3}
                      {print o[$2] "\t" $0}' <<<"$rows" | sort -t$'\t' -k1,1n -k4,4n | cut -f2-)"

  if [[ "$FORMAT" == "tsv" ]]; then
    printf 'issue\tbucket\tage_days\tclaimant\tsource\tphrase\topen_prs\ttitle\n'
    printf '%s\n' "$rows"
    exit 0
  fi

  local n bucket age who src hit prs title col total=0
  printf '\n%s%sInformal claims on open issues (%s)%s\n' "$BLD" "$BLU" "$REPO" "$NC"
  printf '%sACTIVE <=%sd, AGING <=%sd, LAPSED beyond. Claims are heuristic; read the thread.%s\n\n' \
    "$DIM" "$ACTIVE_DAYS" "$LAPSED_DAYS" "$NC"
  # US (0x1f) as the delimiter, NOT tab: tab is IFS whitespace, so an empty open_prs
  # field would collapse and shift the title into the PR column.
  while IFS=$'\037' read -r n bucket age who src hit prs title; do
    case "$bucket" in ACTIVE) col="$RED" ;; AGING) col="$YLW" ;; *) col="$GRN" ;; esac
    printf '%s#%-5s%s %s%-6s%s %4sd  %-22s %-7s "%s"\n' "$BLD" "$n" "$NC" "$col" "$bucket" "$NC" "$age" "$who" "$src" "$hit"
    printf '        %s%s%s%s\n' "$DIM" "$title" "$NC" "${prs:+   PRs: $prs}"
    total=$((total+1))
  done < <(tr '\t' '\037' <<<"$rows")
  printf '\n%s%d issue(s) with an informal claim.%s\n' "$DIM" "$total" "$NC"
}

main "$@"
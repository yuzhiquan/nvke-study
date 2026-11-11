#!/usr/bin/env bash
#
# pr-index.sh — build a reverse index from issue number -> open PRs that touch it.
#
# WHY THIS EXISTS
#
# screen-issues.sh applies rule 1 per issue by walking that issue's timeline. That
# works, but it is one API round-trip per issue and it only sees PRs GitHub decided
# to cross-reference. It misses:
#
#   * PRs that name an issue only in the branch name (head=fix/1306-warmpool-...)
#   * PRs whose body references an issue in prose without creating a timeline event
#   * the whole population of open PRs that reference NO issue at all — work in
#     flight that no issue-side screen can ever surface
#
# One paginated sweep over open PRs gives all of it, and inverts the question from
# "does this issue have a PR?" (asked 68 times) to "which issues do the 118 open PRs
# claim?" (asked once). #1306 was found this way: two open PRs, and it was sitting
# on the never-screened list.
#
# Output is a lookup table other tools and humans can consult, plus a list of
# unreferenced PRs, which is where undocumented in-flight work hides.

set -euo pipefail

REPO="${REPO:-dsx-ai-factory/nvke}"
CACHE_DIR="${CACHE_DIR:-${TMPDIR:-/tmp}/pr-index-cache}"
FORMAT="${FORMAT:-text}"
# A stale cache silently hides PRs opened since the last sweep. Entries older than
# this many seconds are refetched; 0 disables caching.
CACHE_TTL="${CACHE_TTL:-900}"
STATE="${STATE:-open}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; BLU=$'\033[0;34m'
DIM=$'\033[2m'; BLD=$'\033[1m'; NC=$'\033[0m'
[[ -t 1 ]] || { RED=""; GRN=""; YLW=""; BLU=""; DIM=""; BLD=""; NC=""; }

log_info()  { printf '%s[info]%s %s\n'  "$BLU" "$NC" "$*" >&2; }
log_warn()  { printf '%s[warn]%s %s\n'  "$YLW" "$NC" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n' "$RED" "$NC" "$*" >&2; }
die() { log_error "$*"; exit 2; }

usage() {
  cat <<'EOF'
Usage: pr-index.sh [options]

Builds a reverse index: issue number -> open PRs referencing it. Also reports PRs
that reference no issue (undocumented in-flight work).

Options:
  --issue N         Show only PRs referencing issue N (exit 0 if any, 1 if none)
  --state STATE     open | closed | all (default open)
  --format FMT      text | json | tsv (default text)
  --unreferenced    List only PRs that reference no issue
  --repo OWNER/NAME Target repo (default dsx-ai-factory/nvke)
  --grep REGEX      List PRs whose title/body/branch match REGEX (case-insensitive).
                    For roadmap items and issues nobody has filed yet.
  --no-cache        Bypass the response cache (default TTL: CACHE_TTL=900s)
  -h, --help        This help

Reference sources scanned, in this order of reliability:
  1. body    "#NNNN" or "pull/NNNN"-style refs in the PR description
  2. title   "#NNNN" in the PR title
  3. branch  a bare number in the head branch name (fix/1306-foo -> 1306)

Branch-derived refs are the weakest signal (a number in a branch name may be a
ticket in another system), so they are labelled and should be confirmed by reading.

Examples:
  pr-index.sh --issue 1306
  pr-index.sh --unreferenced
  FORMAT=tsv pr-index.sh > /tmp/pr-index.tsv
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

# True if $1 was modified within CACHE_TTL seconds (BSD and GNU stat both handled).
cache_fresh() {
  local mtime now
  mtime="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)" || return 1
  now="$(date +%s)"
  (( now - mtime < CACHE_TTL ))
}

fetch_prs() {
  # The key MUST include the repo: without it a sweep of one project is served
  # as another project's PR list, with no error (found porting to agent-router).
  local slug; slug="$(printf '%s' "$REPO" | tr -c 'a-zA-Z0-9._-' '_')"
  local file="$CACHE_DIR/prs-$slug-$STATE.json"
  if [[ "${NO_CACHE:-0}" != "1" && -s "$file" ]] && cache_fresh "$file"; then cat "$file"; return 0; fi
  mkdir -p "$CACHE_DIR"
  log_info "fetching $STATE PRs from $REPO (paginated)…"
  if ! gh api "repos/$REPO/pulls?state=$STATE&per_page=100" --paginate \
        --jq '.[] | {num: .number, title: .title, body: (.body // ""), head: .head.ref, author: .user.login, draft: .draft, updated: .updated_at}' \
        > "$file.tmp" 2>/dev/null; then
    rm -f "$file.tmp"; die "failed to fetch PRs"
  fi
  mv "$file.tmp" "$file"
  cat "$file"
}

# Emit one "issue<TAB>pr<TAB>source<TAB>author<TAB>draft<TAB>title" row per (issue,PR) pair.
# Self-references are dropped: a PR body saying "#1309" inside PR 1309 is noise.
build_pairs() {
  fetch_prs | jq -r '
    . as $pr
    | ( [ ($pr.body  | [scan("(?:#|pull/)([0-9]{2,5})")] | flatten | .[] | {n: ., src: "body"}) ]
      + [ ($pr.title | [scan("#([0-9]{2,5})")]           | flatten | .[] | {n: ., src: "title"}) ]
      + [ ($pr.head  | [scan("(?:^|[^0-9])([0-9]{2,5})(?:[^0-9]|$)")] | flatten | .[] | {n: ., src: "branch"}) ]
      )
    | unique_by(.n + .src)
    | .[]
    | select((.n | tonumber) != $pr.num)
    | [ .n, ($pr.num|tostring), .src, $pr.author,
        (if $pr.draft then "draft" else "ready" end),
        ($pr.title | gsub("\t"; " ")) ]
    | @tsv' 2>/dev/null | sort -t$'\t' -k1,1n -k2,2n -u
}

emit_text() {
  local pairs="$1" cur="" n pr src author draft title
  printf '\n%s%sIssue -> open PRs (%s)%s\n\n' "$BLD" "$BLU" "$REPO" "$NC"
  while IFS=$'\t' read -r n pr src author draft title; do
    [[ -z "$n" ]] && continue
    if [[ "$n" != "$cur" ]]; then
      printf '%s#%s%s\n' "$BLD" "$n" "$NC"
      cur="$n"
    fi
    local srccol="$GRN"
    [[ "$src" == "branch" ]] && srccol="$YLW"
    printf '   → PR #%-5s %s[%s]%s %s%-6s%s by %-16s %s\n' \
      "$pr" "$srccol" "$src" "$NC" "$DIM" "$draft" "$NC" "$author" "${title:0:62}"
  done <<<"$pairs"
  printf '\n%s[branch] refs are weak — a number in a branch name may be an external ticket. Confirm by reading.%s\n' "$DIM" "$NC"
}

emit_grep() {
  local re="$1"
  printf '\n%s%sOpen PRs matching /%s/%s\n\n' "$BLD" "$BLU" "$re" "$NC"
  fetch_prs | jq -r --arg re "$re" '
    select((.title + " " + .body + " " + .head) | test($re; "i"))
    | "   → PR #\(.num)\t\(.author)\t\(.title)"' | sort -t'#' -k2,2n
}

emit_unreferenced() {
  local referenced
  referenced="$(build_pairs | cut -f2 | sort -u)"
  printf '\n%s%sOpen PRs referencing NO issue%s — undocumented in-flight work\n\n' "$BLD" "$YLW" "$NC"
  # Materialise to a variable first. Piping fetch_prs into `while` runs the loop in
  # a subshell whose stdout was being lost behind the pipeline, so this silently
  # printed nothing at all — caught only because the count came back 0.
  # NOTE the parens around (.num|tostring). Without them jq parses the whole
  # array as the left side of the pipe — "[.num|tostring, .author, ...]" becomes
  # [.num] | (tostring, .author, ...) — and every row fails with
  # "Cannot index number with string". This printed nothing at all rather than
  # erroring visibly, because stderr was being discarded.
  local rows; rows="$(fetch_prs | jq -r '[(.num|tostring), .author, (if .draft then "draft" else "ready" end), (.updated[0:10]), .title] | @tsv')"
  local count=0 num author draft updated title
  while IFS=$'\t' read -r num author draft updated title; do
    [[ -z "$num" ]] && continue
    grep -qx "$num" <<<"$referenced" && continue
    printf '  PR #%-5s %s%-6s%s %s by %-16s %s\n' "$num" "$DIM" "$draft" "$NC" "$updated" "$author" "${title:0:66}"
    count=$(( count + 1 ))
  done <<<"$rows"
  printf '\n%s%d of %d open PR(s) reference no issue.%s\n' "$DIM" "$count" "$(grep -c . <<<"$rows")" "$NC"
  printf '\n%sThese cannot be found by any issue-side screen. If one implements a feature\nyou are about to plan, you would not learn it from the issue.%s\n' "$DIM" "$NC"
}

main() {
  need gh; need jq
  local only_issue="" unreferenced=0 grep_re=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue)        only_issue="${2:?}"; shift 2 ;;
      --state)        STATE="${2:?}"; shift 2 ;;
      --format)       FORMAT="${2:?}"; shift 2 ;;
      --unreferenced) unreferenced=1; shift ;;
      --repo)         REPO="${2:?}"; shift 2 ;;
      --grep)         grep_re="${2:?}"; shift 2 ;;
      --no-cache)     NO_CACHE=1; shift ;;
      -h|--help)      usage; exit 0 ;;
      *)              die "unknown option: $1 (try --help)" ;;
    esac
  done

  if [[ -n "$grep_re" ]]; then emit_grep "$grep_re"; exit 0; fi
  if [[ "$unreferenced" == "1" ]]; then emit_unreferenced; exit 0; fi

  local pairs; pairs="$(build_pairs)"
  [[ -n "$pairs" ]] || die "no issue references found in $STATE PRs (unexpected)"

  if [[ -n "$only_issue" ]]; then
    local hits; hits="$(awk -F'\t' -v n="$only_issue" '$1==n' <<<"$pairs")"
    if [[ -z "$hits" ]]; then
      printf '%sno %s PRs reference #%s%s\n' "$DIM" "$STATE" "$only_issue" "$NC"
      exit 1
    fi
    emit_text "$hits"
    exit 0
  fi

  case "$FORMAT" in
    tsv)  printf 'issue\tpr\tsource\tauthor\tstate\ttitle\n'; printf '%s\n' "$pairs" ;;
    json) jq -R -s 'split("\n") | map(select(length>0) | split("\t")
            | {issue: .[0]|tonumber, pr: .[1]|tonumber, source: .[2], author: .[3], state: .[4], title: .[5]})' <<<"$pairs" ;;
    text) emit_text "$pairs"
          printf '%s%d issue(s) referenced by %d open PR(s).%s\n' \
            "$DIM" "$(cut -f1 <<<"$pairs" | sort -u | grep -c .)" "$(cut -f2 <<<"$pairs" | sort -u | grep -c .)" "$NC" ;;
    *)    die "unknown --format: $FORMAT" ;;
  esac
}

main "$@"

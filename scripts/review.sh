#!/bin/bash
# Bookkeeping for the architecture, quality and security review that the
# clair-review skill runs (.claude/skills/clair-review/SKILL.md). The skill's
# orchestrator asks this script what to do next, so routing is rules and not
# judgement. Reviewers never run it.
#
#   review.sh check [ref]           every tracked file is in one section or excluded
#   review.sh files <id> [ref]      the files of one section
#   review.sh sizes                 files and lines per section
#   review.sh preflight             is the checkout ready for a review run?
#   review.sh init                  make the run directory for HEAD the current run
#   review.sh next                  the next action for the current run
#   review.sh status                where the current run stands
#   review.sh dispatched <key>...   count an attempt: a section id, verify-<id> or synthesize
#   review.sh retry <key>           forget a key's attempts
#   review.sh skip <id>             leave a section out of this run
#   review.sh approve-pilot         let the run continue past the pilot
#   review.sh set max <n>           reviewers per batch (1 to 8)
#   review.sh rebase-run            accept HEAD as the reviewed commit
#   review.sh timings               per-test durations from a quality job log on stdin
#   review.sh work <report.md>      a report's findings to fix and what became of each
#   review.sh work <report.md> next the next finding for the clair-fix skill
#   review.sh work <report.md> set <id> <state> [detail]   record a finding's state
#
# "next" prints one line: preflight, blocked <key>,
# pilot <id>:<model>, await-pilot-approval, sections <id>:<model>...,
# verify <id>..., synthesize or done.
#
# A run lives in build/review/<date>-<commit>/, which git ignores: the
# repository is public and the reports hold unfixed security findings. The
# run's state is the files in it, so there is no state file to fall out of
# step. The clair-fix skill's records of what became of each finding are
# separate: see "findings to fix" below. CLAIR_ENGINE_WORKSPACE names the
# engine build's workspace (the runner's _work/clair/clair, shared read-only)
# when it is not at the default path.

set -euo pipefail

die() {
  echo "review: $1" >&2
  exit 1
}

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo" || die "repository not found: $repo"

skill=".claude/skills/clair-review"
sections_file="$skill/sections.txt"
scope_file="$skill/scope.txt"
review_root="build/review"
engine_ws="${CLAIR_ENGINE_WORKSPACE:-/Volumes/My Shared Files/clair}"
max_attempts=2
tab="$(printf '\t')"

sec_ids=()
sec_slugs=()
sec_models=()
rule_ids=()
rule_pats=()
run=""
problems=0

# --- sections and scope -----------------------------------------------------

# sections.txt: "<id> <slug> <model>" in dispatch order; the first is the pilot.
load_sections() {
  local id slug model
  [[ -f "$sections_file" ]] || die "missing $sections_file"
  sec_ids=()
  sec_slugs=()
  sec_models=()
  while read -r id slug model _; do
    case "$id" in '' | '#'*) continue ;; esac
    [[ "$id" =~ ^[0-9][0-9]$ ]] || die "bad section id in $sections_file: $id"
    [[ "$slug" =~ ^[a-z0-9-]+$ ]] || die "bad slug for section $id in $sections_file"
    case "$model" in
      fable | opus) ;;
      *) die "section $id needs the model fable or opus in $sections_file" ;;
    esac
    sec_ids+=("$id")
    sec_slugs+=("$slug")
    sec_models+=("$model")
  done <"$sections_file"
  [[ ${#sec_ids[@]} -gt 0 ]] || die "no sections in $sections_file"
}

# section_field <id> slug|model
section_field() {
  local i=0
  while [[ $i -lt ${#sec_ids[@]} ]]; do
    if [[ "${sec_ids[$i]}" == "$1" ]]; then
      if [[ "$2" == slug ]]; then
        echo "${sec_slugs[$i]}"
      else
        echo "${sec_models[$i]}"
      fi
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

need_section() {
  section_field "${1-}" slug >/dev/null || die "unknown section: ${1-}"
}

# scope.txt: "<id or -> <glob>". The first rule that matches a path wins, "-"
# excludes it, and "*" also matches "/".
load_scope() {
  local id pat
  [[ -f "$scope_file" ]] || die "missing $scope_file"
  rule_ids=()
  rule_pats=()
  while read -r id pat; do
    case "$id" in '' | '#'*) continue ;; esac
    [[ -n "$pat" ]] || die "rule without a pattern in $scope_file: $id"
    rule_ids+=("$id")
    rule_pats+=("$pat")
  done <"$scope_file"
  [[ ${#rule_ids[@]} -gt 0 ]] || die "no rules in $scope_file"
}

# Reads paths on stdin and prints "<id>\t<rule index>\t<path>" for each, with
# the id "?" when no rule matches.
classify() {
  local path i id n=${#rule_ids[@]}
  while IFS= read -r path; do
    id="?"
    i=0
    while [[ $i -lt $n ]]; do
      # The pattern is a glob on purpose.
      # shellcheck disable=SC2254
      case "$path" in
        ${rule_pats[$i]})
          id="${rule_ids[$i]}"
          break
          ;;
      esac
      i=$((i + 1))
    done
    printf '%s\t%s\t%s\n' "$id" "$i" "$path"
  done
}

tracked() {
  if [[ -n "${1-}" ]]; then
    git -c core.quotepath=off ls-tree -r --name-only "$1"
  else
    git -c core.quotepath=off ls-files
  fi
}

# Reads a listing from classify on stdin and prints one section's paths.
paths_of() {
  awk -F "$tab" -v id="$1" '$1 == id { print $3 }'
}

# Reads paths on stdin and prints how many lines their text files hold.
count_lines() {
  local path n total=0
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    if grep -Iq . "$path" 2>/dev/null; then
      n="$(wc -l <"$path")"
      total=$((total + n))
    fi
  done
  echo "$total"
}

cmd_check() {
  local id listing unassigned used i=0 status=0
  load_sections
  load_scope
  for id in "${rule_ids[@]}"; do
    [[ "$id" == "-" ]] || section_field "$id" slug >/dev/null ||
      die "$scope_file names an unknown section: $id"
  done
  listing="$(tracked "${1-}" | classify)"
  unassigned="$(awk -F "$tab" '$1 == "?" { print $3 }' <<<"$listing")"
  if [[ -n "$unassigned" ]]; then
    echo "Tracked files that no rule in $scope_file covers:"
    sed 's/^/  /' <<<"$unassigned"
    status=1
  fi
  used="$(cut -f 2 <<<"$listing" | sort -u)"
  while [[ $i -lt ${#rule_ids[@]} ]]; do
    if ! grep -qx "$i" <<<"$used"; then
      echo "review: rule matches no file: ${rule_ids[$i]} ${rule_pats[$i]}" >&2
    fi
    i=$((i + 1))
  done
  if [[ $status -eq 0 ]]; then
    echo "scope: every tracked file is assigned or excluded"
  fi
  return $status
}

cmd_files() {
  load_sections
  load_scope
  need_section "${1-}"
  tracked "${2-}" | classify | paths_of "$1"
}

cmd_sizes() {
  local listing id files count i=0
  load_sections
  load_scope
  listing="$(tracked | classify)"
  printf '%-3s %-18s %-6s %6s %8s\n' id section model files lines
  while [[ $i -lt ${#sec_ids[@]} ]]; do
    id="${sec_ids[$i]}"
    files="$(paths_of "$id" <<<"$listing")"
    count="$(grep -c . <<<"$files" || true)"
    printf '%-3s %-18s %-6s %6s %8s\n' "$id" "${sec_slugs[$i]}" "${sec_models[$i]}" \
      "$count" "$(count_lines <<<"$files")"
    i=$((i + 1))
  done
}

# --- preflight --------------------------------------------------------------

pass() {
  echo "ok    $1"
}

fail() {
  echo "FAIL  $1"
  problems=$((problems + 1))
}

clean_tree() {
  [[ -z "$(git status --porcelain --untracked-files=no)" ]]
}

chromium_version() {
  awk -F = '{ v[$1] = $2 } END { print v["MAJOR"] "." v["MINOR"] "." v["BUILD"] "." v["PATCH"] }' \
    "$engine_ws/build/src/chrome/VERSION"
}

built_engine_key() {
  cat "$engine_ws/build/engine_key" 2>/dev/null || true
}

cmd_preflight() {
  local branch key built state open src="$engine_ws/build/src"

  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$branch" == main ]]; then
    pass "on main"
  else
    fail "on $branch, not main"
  fi
  if clean_tree; then
    pass "no uncommitted changes to tracked files"
  else
    fail "tracked files have uncommitted changes"
  fi
  if git rev-parse -q --verify origin/main >/dev/null; then
    if [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]]; then
      pass "HEAD is origin/main"
    else
      fail "HEAD is not origin/main: fetch and pull first"
    fi
  fi

  # Not a failure: a change can be open because its work has not started. One
  # whose code has merged leaves the specs behind the code until it is archived.
  open="$(find openspec/changes -mindepth 1 -maxdepth 1 -type d ! -name archive 2>/dev/null |
    sed 's|.*/||' | sort | tr '\n' ' ')"
  if [[ -n "$open" ]]; then
    echo "note  open OpenSpec changes: $open"
    echo "      archive any whose code has merged, so the specs match the code under review"
  fi

  if (cmd_check >/dev/null 2>&1); then
    pass "the scope covers every tracked file"
  else
    fail "the scope leaves files unassigned: run scripts/review.sh check"
  fi

  if [[ -r "$src/chrome/VERSION" ]]; then
    pass "engine tree is readable: $src"
    built="$(built_engine_key)"
    key="$("$repo/scripts/engine-key.sh" 2>/dev/null || true)"
    if [[ -n "$key" && "$key" == "$built" ]]; then
      pass "engine tree was built from this commit's engine key ($key)"
    else
      fail "engine tree has key ${built:-unknown} but this commit's is ${key:-unknown}: build the engine first"
    fi
    state="$(cat "$engine_ws/build/compile_status" 2>/dev/null || true)"
    if [[ "$state" == finished ]]; then
      pass "engine build is finished"
    else
      fail "engine build is not finished (compile_status: ${state:-missing})"
    fi
  else
    fail "engine tree is not readable at $src (set CLAIR_ENGINE_WORKSPACE)"
  fi

  [[ $problems -eq 0 ]]
}

# --- the run directory ------------------------------------------------------

current_run() {
  local name
  [[ -f "$review_root/current" ]] || return 1
  name="$(cat "$review_root/current")"
  [[ -n "$name" && -f "$review_root/$name/run.md" ]] || return 1
  echo "$review_root/$name"
}

use_run() {
  run="$(current_run)" || die "no review run yet: run scripts/review.sh init"
}

run_get() {
  sed -n "s/^$1: //p" "$run/run.md" | head -n 1
}

run_set() {
  local tmp
  tmp="$(mktemp)"
  grep -v "^$1: " "$run/run.md" >"$tmp" || true
  echo "$1: $2" >>"$tmp"
  mv "$tmp" "$run/run.md"
}

# Writes each section's file list for the working tree.
write_run_files() {
  local listing id files i=0
  listing="$(tracked | classify)"
  mkdir -p "$run/files" "$run/verify"
  while [[ $i -lt ${#sec_ids[@]} ]]; do
    id="${sec_ids[$i]}"
    files="$(paths_of "$id" <<<"$listing")"
    printf '%s\n' "$files" >"$run/files/$id.txt"
    i=$((i + 1))
  done
}

cmd_init() {
  local commit short existing
  load_sections
  load_scope
  commit="$(git rev-parse HEAD)"
  short="$(git rev-parse --short=7 HEAD)"
  mkdir -p "$review_root"
  existing="$(find "$review_root" -mindepth 1 -maxdepth 1 -type d -name "*-$short" | sort | tail -n 1)"
  if [[ -n "$existing" && -f "$existing/run.md" ]]; then
    run="$existing"
  else
    run="$review_root/$(date +%Y-%m-%d)-$short"
    mkdir -p "$run"
    {
      echo "# Review run"
      echo "commit: $commit"
      echo "date: $(date +%Y-%m-%d)"
      echo "engine_src: $engine_ws/build/src"
      echo "ungoogled_src: $engine_ws/ungoogled-chromium"
      echo "engine_key: $(built_engine_key)"
      echo "chromium: $(chromium_version 2>/dev/null || true)"
      echo "max: 2"
    } >"$run/run.md"
    write_run_files
  fi
  basename "$run" >"$review_root/current"
  echo "$run"
}

report_file() {
  echo "$run/$1-$(section_field "$1" slug).md"
}

is_complete() {
  [[ -f "$1" ]] && grep -q '^Status: complete[[:space:]]*$' "$1"
}

# missing, partial, complete or skipped
section_state() {
  local file
  if [[ -f "$run/$1.skipped" ]]; then
    echo skipped
    return 0
  fi
  file="$(report_file "$1")"
  if is_complete "$file"; then
    echo complete
  elif [[ -f "$file" ]]; then
    echo partial
  else
    echo missing
  fi
}

attempts() {
  if [[ -f "$run/$1.attempts" ]]; then
    cat "$run/$1.attempts"
  else
    echo 0
  fi
}

exhausted() {
  [[ "$(attempts "$1")" -ge $max_attempts ]]
}

# A report needs verifying when it has a Critical or High finding, or a Medium
# one whose Chromium dependency nobody checked.
needs_verify() {
  awk '
    /^### S[0-9]+-[0-9]+ \[/ {
      severity = $0
      sub(/^[^[]*\[/, "", severity)
      sub(/\].*$/, "", severity)
      if (severity == "Critical" || severity == "High") need = 1
    }
    /^- Chromium: unverified/ { if (severity == "Medium") need = 1 }
    END { exit need ? 0 : 1 }
  ' "$(report_file "$1")"
}

verify_pending() {
  [[ "$(section_state "$1")" == complete ]] && needs_verify "$1" &&
    ! is_complete "$run/verify/$1.md"
}

count_findings() {
  grep -c "^### S[0-9]*-[0-9]* \[$2\]" "$(report_file "$1")" 2>/dev/null || true
}

cmd_next() {
  local max pilot id state batch count i
  load_sections
  if ! run="$(current_run)"; then
    echo preflight
    return 0
  fi

  # Commits made after the run started are not checked: reviewers read the
  # checkout as it stands, and rebase-run is there to re-review changed
  # sections when the owner wants that.

  # Anything out of attempts stops the run until the owner retries or skips it.
  for id in "${sec_ids[@]}"; do
    state="$(section_state "$id")"
    if [[ "$state" == missing || "$state" == partial ]] && exhausted "$id"; then
      echo "blocked $id"
      return 0
    fi
    if verify_pending "$id" && exhausted "verify-$id"; then
      echo "blocked verify-$id"
      return 0
    fi
  done

  max="$(run_get max)"
  max="${max:-2}"
  pilot="${sec_ids[0]}"
  state="$(section_state "$pilot")"
  if [[ "$state" == missing || "$state" == partial ]]; then
    echo "pilot $pilot:$(section_field "$pilot" model)"
    return 0
  fi
  if [[ "$state" == complete ]]; then
    if verify_pending "$pilot"; then
      echo "verify $pilot"
      return 0
    fi
    if [[ ! -f "$run/pilot-approved" ]]; then
      echo await-pilot-approval
      return 0
    fi
  fi

  batch=""
  count=0
  i=1
  while [[ $i -lt ${#sec_ids[@]} && $count -lt $max ]]; do
    id="${sec_ids[$i]}"
    state="$(section_state "$id")"
    if [[ "$state" == missing || "$state" == partial ]]; then
      batch="$batch $id:${sec_models[$i]}"
      count=$((count + 1))
    fi
    i=$((i + 1))
  done
  if [[ $count -gt 0 ]]; then
    echo "sections$batch"
    return 0
  fi

  for id in "${sec_ids[@]}"; do
    if [[ $count -lt $max ]] && verify_pending "$id"; then
      batch="$batch $id"
      count=$((count + 1))
    fi
  done
  if [[ $count -gt 0 ]]; then
    echo "verify$batch"
    return 0
  fi

  if is_complete "$run/REPORT.md"; then
    echo "done"
  elif exhausted synthesize; then
    echo "blocked synthesize"
  else
    echo synthesize
  fi
}

cmd_status() {
  local id state verify findings i=0
  load_sections
  use_run
  echo "run:      $run"
  echo "commit:   $(run_get commit)"
  echo "chromium: $(run_get chromium) (engine key $(run_get engine_key))"
  echo "max:      $(run_get max) reviewers per batch"
  echo
  printf '%-3s %-18s %-6s %-9s %-9s %s\n' id section model report verify "C/H/M/L/I"
  while [[ $i -lt ${#sec_ids[@]} ]]; do
    id="${sec_ids[$i]}"
    state="$(section_state "$id")"
    verify="-"
    findings="-"
    if [[ "$state" == complete ]]; then
      findings="$(count_findings "$id" Critical)/$(count_findings "$id" High)/$(count_findings "$id" Medium)/$(count_findings "$id" Low)/$(count_findings "$id" Info)"
      if is_complete "$run/verify/$id.md"; then
        verify=complete
      elif needs_verify "$id"; then
        verify=pending
      else
        verify="not needed"
      fi
    fi
    if [[ "$state" != complete && "$state" != skipped ]] && exhausted "$id"; then
      state=blocked
    fi
    printf '%-3s %-18s %-6s %-9s %-9s %s\n' "$id" "${sec_slugs[$i]}" "${sec_models[$i]}" \
      "$state" "$verify" "$findings"
    i=$((i + 1))
  done
  echo
  if is_complete "$run/REPORT.md"; then
    echo "REPORT.md: complete"
  else
    echo "REPORT.md: not written"
  fi
  echo "next: $(cmd_next)"
}

valid_key() {
  case "$1" in
    synthesize) return 0 ;;
    verify-*) section_field "${1#verify-}" slug >/dev/null ;;
    *) section_field "$1" slug >/dev/null ;;
  esac
}

cmd_dispatched() {
  local key
  load_sections
  use_run
  [[ $# -gt 0 ]] || die "dispatched needs at least one key"
  for key in "$@"; do
    valid_key "$key" || die "unknown key: $key"
    echo $(($(attempts "$key") + 1)) >"$run/$key.attempts"
  done
}

cmd_retry() {
  load_sections
  use_run
  valid_key "${1-}" || die "unknown key: ${1-}"
  rm -f "$run/$1.attempts"
}

cmd_skip() {
  load_sections
  use_run
  need_section "${1-}"
  : >"$run/$1.skipped"
}

cmd_approve_pilot() {
  local pilot
  load_sections
  use_run
  pilot="${sec_ids[0]}"
  [[ "$(section_state "$pilot")" == complete ]] || die "the pilot report for section $pilot is not complete"
  ! verify_pending "$pilot" || die "the pilot's findings are not verified yet"
  : >"$run/pilot-approved"
}

cmd_set() {
  use_run
  case "${1-}" in
    max)
      [[ "${2-}" =~ ^[1-8]$ ]] || die "max must be 1 to 8"
      ;;
    *) die "set takes max" ;;
  esac
  run_set "$1" "$2"
}

# Sets a stale report aside so the section runs again.
set_aside() {
  if [[ -f "$1" ]]; then
    mkdir -p "$run/stale"
    mv "$1" "$run/stale/$2-$(basename "$1")"
  fi
}

cmd_rebase_run() {
  local old new changed id
  load_sections
  load_scope
  use_run
  old="$(run_get commit)"
  new="$(git rev-parse HEAD)"
  [[ "$old" != "$new" ]] || die "HEAD is already the reviewed commit"
  clean_tree || die "tracked files have uncommitted changes"
  git cat-file -e "$old^{commit}" 2>/dev/null || die "the reviewed commit $old is not in this repository"
  changed="$(git -c core.quotepath=off diff --name-only "$old" "$new" | classify |
    awk -F "$tab" '$1 ~ /^[0-9]+$/ { print $1 }' | sort -u)"
  for id in $changed; do
    set_aside "$(report_file "$id")" "${old:0:7}"
    set_aside "$run/verify/$id.md" "${old:0:7}"
    rm -f "$run/$id.attempts" "$run/verify-$id.attempts"
    echo "section $id changed: it runs again"
  done
  if [[ -n "$changed" ]]; then
    set_aside "$run/REPORT.md" "${old:0:7}"
    rm -f "$run/synthesize.attempts"
  fi
  run_set commit "$new"
  run_set engine_key "$(built_engine_key)"
  write_run_files
}

# --- findings to fix --------------------------------------------------------

# The clair-fix skill takes the findings of one section report, named by its
# file name, one at a time, most severe first, and leaves Info findings alone.
# The reports it takes sit directly in build/review/. What became of each
# finding is in <report name>.work.txt beside the report, "<id>\t<state>\t
# <detail>", with no line for a finding nobody has started. A fix is made in a
# linked worktree, whose build/ is empty, so these commands read the main
# checkout's build/review/.

# Sets report and record from a report's file name.
use_work_report() {
  local name="${1-}" main
  [[ -n "$name" ]] || die "work needs a report's file name"
  [[ "$name" =~ ^[A-Za-z0-9._-]+\.md$ ]] || die "not a report file name: $name"
  main="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
  report="${main:-$repo}/build/review/$name"
  [[ -f "$report" ]] || die "no report $report"
  record="${report%.md}.work.txt"
}

# Prints "<id>\t<severity>\t<title>" for each finding below Info in the
# report, most severe first, then by number.
work_items() {
  awk '
    /^### S[0-9][0-9]-[0-9]+ \[(Critical|High|Medium|Low)\] / {
      id = $2
      severity = $3
      gsub(/[][]/, "", severity)
      title = $0
      sub(/^### [^]]*\] +/, "", title)
      gsub(/\t/, " ", title)
      rank = severity == "Critical" ? 1 : severity == "High" ? 2 : severity == "Medium" ? 3 : 4
      split(substr(id, 2), part, "-")
      printf "%d\t%s\t%04d\t%s\t%s\t%s\n", rank, part[1], part[2], id, severity, title
    }
  ' "$report" | sort -t "$tab" -k1,1n -k2,2 -k3,3n | cut -f 4-
}

# Prints "<state>\t<detail>" for a finding, "open" when the record has no line.
work_state() {
  local line=""
  if [[ -f "$record" ]]; then
    line="$(awk -F "$tab" -v id="$1" '$1 == id { line = $2 "\t" $3 } END { print line }' "$record")"
  fi
  if [[ -n "$line" ]]; then
    echo "$line"
  else
    echo "open"
  fi
}

work_list() {
  local items id severity title state detail
  echo "report: $report"
  echo "commit: $(sed -n 's/^- Commit: *//p' "$report" | head -n 1)"
  echo
  items="$(work_items)"
  if [[ -z "$items" ]]; then
    echo "the report has no finding to fix"
    return 0
  fi
  printf '%-7s %-8s %-8s %-22s %s\n' id severity state detail title
  while IFS="$tab" read -r id severity title; do
    IFS="$tab" read -r state detail <<<"$(work_state "$id")"
    printf '%-7s %-8s %-8s %-22s %s\n' "$id" "$severity" "$state" "${detail:--}" "$title"
  done <<<"$items"
  echo
  echo "next: $(work_next)"
}

# Prints one line: no-findings, resume <id> <branch>, fix <id> <severity> or
# done.
work_next() {
  local items id severity title state detail
  items="$(work_items)"
  if [[ -z "$items" ]]; then
    echo no-findings
    return 0
  fi

  # A fix that was started and not finished comes before anything new.
  while IFS="$tab" read -r id severity title; do
    IFS="$tab" read -r state detail <<<"$(work_state "$id")"
    if [[ "$state" == started ]]; then
      echo "resume $id $detail"
      return 0
    fi
  done <<<"$items"

  while IFS="$tab" read -r id severity title; do
    IFS="$tab" read -r state detail <<<"$(work_state "$id")"
    if [[ "$state" == open ]]; then
      echo "fix $id $severity"
      return 0
    fi
  done <<<"$items"
  echo "done"
}

work_set() {
  local id="${1-}" state="${2-}" detail tmp
  [[ $# -ge 2 ]] || die "work set needs a finding id and a state"
  shift 2
  detail="$*"
  work_items | cut -f 1 | grep -qx -- "$id" || die "no finding $id to fix in $report"
  case "$state" in
    open) [[ -z "$detail" ]] || die "open takes no detail" ;;
    fixed | merged) [[ "$detail" =~ ^[0-9]+$ ]] || die "$state needs a pull request number" ;;
    started | dropped | deferred | owner)
      [[ -n "$detail" ]] || die "$state needs a detail: a branch or a reason"
      ;;
    *) die "unknown state: $state (open, started, fixed, merged, dropped, deferred or owner)" ;;
  esac
  case "$detail" in *"$tab"* | *$'\n'*) die "the detail must be one line without tabs" ;; esac
  tmp="$(mktemp)"
  if [[ -f "$record" ]]; then
    awk -F "$tab" -v id="$id" '$1 != id' "$record" >"$tmp"
  fi
  if [[ "$state" != open ]]; then
    printf '%s\t%s\t%s\n' "$id" "$state" "$detail" >>"$tmp"
  fi
  mv "$tmp" "$record"
}

cmd_work() {
  use_work_report "${1-}"
  local action="${2-list}"
  [[ $# -gt 2 ]] && shift 2 || set --
  case "$action" in
    list) work_list ;;
    next) work_next ;;
    set) work_set "$@" ;;
    *) die "usage: review.sh work <report.md> [list|next|set <id> <state> [detail]]" ;;
  esac
}

# --- test timings -----------------------------------------------------------

# Reads an xcodebuild log on stdin: lines such as
# "Test Case '-[Module.Class testName]' passed (12.345 seconds)."
cmd_timings() {
  local rows
  rows="$(awk '
    /Test [Cc]ase .*(passed|failed) \([0-9.]+ seconds\)/ {
      name = $0
      sub(/^.*-\[/, "", name)
      sub(/\].*$/, "", name)
      split(name, part, " ")
      class = part[1]
      sub(/^.*\./, "", class)
      seconds = $0
      sub(/ seconds\).*$/, "", seconds)
      sub(/^.*\(/, "", seconds)
      result = ($0 ~ / failed \(/) ? "failed" : "passed"
      printf "%s\t%s\t%s\t%s\n", seconds, result, class, part[2]
    }
  ' | sort -rn)"
  [[ -n "$rows" ]] || die "no test results in the log on stdin"
  printf '%8s  %-7s %-22s %s\n' seconds result class test
  awk -F "$tab" '{ printf "%8.1f  %-7s %-22s %s\n", $1, $2, $3, $4 }' <<<"$rows"
  echo
  printf '%8s  %5s  %s\n' seconds tests class
  awk -F "$tab" '
    { total[$3] += $1; count[$3]++; all += $1; n++ }
    END {
      for (class in total) printf "%8.1f  %5d  %s\n", total[class], count[class], class
      printf "%8.1f  %5d  %s\n", all, n, "TOTAL"
    }
  ' <<<"$rows" | sort -rn
}

# --- main -------------------------------------------------------------------

action="${1-}"
[[ $# -gt 0 ]] && shift
case "$action" in
  check) cmd_check "$@" ;;
  files) cmd_files "$@" ;;
  sizes) cmd_sizes ;;
  preflight) cmd_preflight ;;
  init) cmd_init ;;
  next) cmd_next ;;
  status) cmd_status ;;
  dispatched) cmd_dispatched "$@" ;;
  retry) cmd_retry "$@" ;;
  skip) cmd_skip "$@" ;;
  approve-pilot) cmd_approve_pilot ;;
  set) cmd_set "$@" ;;
  rebase-run) cmd_rebase_run ;;
  timings) cmd_timings ;;
  work) cmd_work "$@" ;;
  *) die "usage: review.sh check|files|sizes|preflight|init|next|status|dispatched|retry|skip|approve-pilot|set|rebase-run|timings|work" ;;
esac

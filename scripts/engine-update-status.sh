#!/bin/bash
# Follows the patch check on the engine update pull request
# (automate-engine-updates D7). engine-update-status.yml runs it from main
# after each CI run on the branch engine-update; it never checks out or runs
# the pull request's code.
#
#   engine-update-status.sh
#
# For the run's head commit, if it is still the pull request's head: ready for
# review when the Engine key job passed and the Patch check passed or was
# skipped, a draft otherwise. One comment, found by its marker, says which
# Clair patches don't apply (from the Patch check's log) or how to build the
# engine. A cancelled run, or one for an older commit, changes nothing.
#
# Environment:
#   GH_REPO         owner/name of this repository
#   GH_TOKEN        a token that can read Actions runs and write pull requests
#   DRAFT_TOKEN     a token for changing the draft state (default: GH_TOKEN)
#   RUN_ID          the CI run's ID
#   RUN_HEAD_SHA    the commit the run checked
#   RUN_CONCLUSION  the run's conclusion
#   PATCH_CHECK_TIMEOUT_MINUTES  the Patch check job's timeout-minutes in
#                   ci.yml (default 120). A job that times out is reported as
#                   cancelled, so a cancelled one that ran this long timed out.
#
# Everything read from the log is data: only patch paths matching the pattern
# below are used, and they are passed through files, never evaluated.

set -euo pipefail

branch=engine-update
marker='<!-- engine-update-status -->'
patch_pattern='^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*\.patch$'

die() {
  echo "engine-update-status: $1" >&2
  exit 1
}

[[ "${GH_REPO-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GH_REPO must be owner/name"
[[ -n "${GH_TOKEN-}" ]] || die "GH_TOKEN is not set"
[[ "${RUN_ID-}" =~ ^[0-9]+$ ]] || die "RUN_ID must be a run ID"
[[ "${RUN_HEAD_SHA-}" =~ ^[0-9a-f]{40}$ ]] || die "RUN_HEAD_SHA must be a commit"
[[ "${RUN_CONCLUSION-}" =~ ^[a-z_]*$ ]] || die "RUN_CONCLUSION is not a conclusion"
draft_token="${DRAFT_TOKEN:-$GH_TOKEN}"
timeout_minutes="${PATCH_CHECK_TIMEOUT_MINUTES:-120}"
[[ "$timeout_minutes" =~ ^[1-9][0-9]*$ ]] || die "PATCH_CHECK_TIMEOUT_MINUTES must be a number of minutes"
owner="${GH_REPO%%/*}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

api() {
  gh api "$@" || die "the GitHub API call '$*' failed"
}

api "repos/$GH_REPO/pulls?state=open&head=$owner:$branch&per_page=100" >"$work/open.json"
if [[ "$(jq 'length' "$work/open.json")" != 1 ]]; then
  echo "No single open pull request from $branch. Nothing to do."
  exit 0
fi
number="$(jq -r '.[0].number' "$work/open.json")"
head_sha="$(jq -r '.[0].head.sha' "$work/open.json")"
is_draft="$(jq -r '.[0].draft' "$work/open.json")"
[[ "$number" =~ ^[0-9]+$ ]] || die "unexpected pull request number"
if [[ "$head_sha" != "$RUN_HEAD_SHA" ]]; then
  echo "Run $RUN_ID checked ${RUN_HEAD_SHA:0:7}, but #$number's head is now ${head_sha:0:7}. Nothing changes."
  exit 0
fi
short="${RUN_HEAD_SHA:0:7}"

api "repos/$GH_REPO/actions/runs/$RUN_ID/jobs?per_page=100" >"$work/jobs.json"
# job_field <name> <field>: a field of the job with that name, or nothing.
job_field() {
  jq -r --arg name "$1" --arg field "$2" \
    '[.jobs[] | select(.name == $name)] | first | .[$field] // empty' "$work/jobs.json"
}
key_result="$(job_field "Engine key" conclusion)"
key_url="$(job_field "Engine key" html_url)"
patch_result="$(job_field "Patch check" conclusion)"
patch_url="$(job_field "Patch check" html_url)"
patch_id="$(job_field "Patch check" id)"
engine_check_result="$(job_field "Engine check" conclusion)"

# A patch check that hit its timeout counts as a failure, even when the run
# reads as cancelled. Any other cancelled run (a newer push replaced it, or
# someone cancelled it) changes nothing.
if [[ "$patch_result" == cancelled ]]; then
  ran="$(jq -r '[.jobs[] | select(.name == "Patch check")] | first |
    if .started_at and .completed_at
    then (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)
    else 0 end' "$work/jobs.json")"
  if (( ${ran%.*} >= timeout_minutes * 60 )); then
    patch_result=timed_out
  fi
fi
if [[ "$RUN_CONCLUSION" == cancelled && "$patch_result" != timed_out ]]; then
  echo "Run $RUN_ID was cancelled. Nothing changes."
  exit 0
fi

ready=false
{
  echo "$marker"
  if [[ "$key_result" != success ]]; then
    echo "**The engine key could not be worked out** for $short, so the patch check didn't run. See the [Engine key job]($key_url)."
  elif [[ "$patch_result" == success || "$patch_result" == skipped ]]; then
    ready=true
    if [[ "$engine_check_result" == success ]]; then
      echo "**Every Clair patch applies** at $short, and its engine is published: no engine build is needed."
    else
      echo "**Every Clair patch applies** at $short. Build the engine on the owner's Mac. The pin changed, so it compiles Chromium from scratch (about 4 hours):"
      echo
      echo '```sh'
      echo "gh workflow run engine.yml -f ref=$branch"
      echo '```'
      echo
      echo "Ready means the patches apply, not that the engine compiles. The pull request can merge once the engine is published."
    fi
  else
    : >"$work/failed"
    if [[ "$patch_id" =~ ^[0-9]+$ ]] && gh api "repos/$GH_REPO/actions/jobs/$patch_id/logs" >"$work/log" 2>/dev/null; then
      # "<timestamp> clair-patch-failed: <path>" lines, in order, once each.
      { grep -o 'clair-patch-failed: .*$' "$work/log" || true; } |
        sed 's/^clair-patch-failed: //; s/[[:space:]]*$//' |
        { grep -E "$patch_pattern" || true; } |
        awk '!seen[$0]++' >"$work/failed"
    fi
    count="$(wc -l <"$work/failed" | tr -d ' ')"
    if (( count > 0 )); then
      if (( count == 1 )); then
        echo "**1 Clair patch doesn't apply** at $short:"
      else
        echo "**$count Clair patches don't apply** at $short:"
      fi
      echo
      while IFS= read -r path; do
        echo "- \`patches/$path\`"
      done <"$work/failed"
      echo
      echo "Fix them from the top: a skipped patch can make a later one that builds on it fail too. See the [Patch check log]($patch_url). Each push to \`$branch\` runs the check again, and this pull request is marked ready once every patch applies."
    else
      echo "**The patch check failed at another step** at $short (${patch_result:-not run}), not in Clair's patch series: for example while fetching the source, copying the overlay, replacing a logo, in domain substitution, or a timeout. See the [Patch check log]($patch_url)."
    fi
  fi
} >"$work/comment"

# The draft state, only when it differs.
if [[ "$ready" == true && "$is_draft" == true ]]; then
  GH_TOKEN="$draft_token" gh pr ready "$number" >/dev/null || die "could not mark #$number ready for review"
  echo "Marked #$number ready for review."
elif [[ "$ready" != true && "$is_draft" != true ]]; then
  GH_TOKEN="$draft_token" gh pr ready --undo "$number" >/dev/null || die "could not convert #$number to a draft"
  echo "Converted #$number to a draft."
else
  echo "#$number is already $([[ "$is_draft" == true ]] && echo "a draft" || echo "ready for review")."
fi

# One comment, edited in place.
api "repos/$GH_REPO/issues/$number/comments?per_page=100" >"$work/comments.json"
comment_id="$(jq -r --arg marker "$marker" \
  '[.[] | select((.body // "") | startswith($marker))] | first | .id // empty' "$work/comments.json")"
jq -n --rawfile body "$work/comment" '{body: $body}' >"$work/request.json"
if [[ -z "$comment_id" ]]; then
  api -X POST "repos/$GH_REPO/issues/$number/comments" --input "$work/request.json" >/dev/null
  echo "Commented on #$number."
else
  jq -r --arg id "$comment_id" '.[] | select((.id | tostring) == $id) | .body' "$work/comments.json" |
    tr -d '\r' >"$work/comment-old"
  # Compared without trailing newlines, which GitHub may drop.
  if [[ "$(cat "$work/comment-old")" == "$(cat "$work/comment")" ]]; then
    echo "#$number's comment is up to date."
  else
    api -X PATCH "repos/$GH_REPO/issues/comments/$comment_id" --input "$work/request.json" >/dev/null
    echo "Updated #$number's comment."
  fi
fi

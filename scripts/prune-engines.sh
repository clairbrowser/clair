#!/bin/bash
# Deletes old engine releases (chromium-engine-<key>), each several hundred MB,
# with their tags. It keeps the <n> newest (default 5), and any older engine
# that main's head or an open pull request's head still needs. engine.yml runs
# it after each build; a deleted engine is rebuilt by running engine.yml again.
#
#   prune-engines.sh [--keep <n>] [--dry-run]
#
# --dry-run prints what it would delete and deletes nothing. Each needed key
# comes from that commit's own engine-key.sh, as engine.yml would compute it.
# A key that can't be worked out is reported and the prune goes on: the newest
# <n> stay whatever happens. Run it in a checkout of the repository; commits it
# doesn't have are fetched from origin. Uses gh, with GH_TOKEN and GH_REPO from
# the environment.

set -euo pipefail

keep=5 dry_run=false

die() {
  echo "prune-engines: $1" >&2
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --keep) keep="${2-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[[ "$keep" =~ ^[1-9][0-9]{0,2}$ ]] || die "--keep must be a number from 1 to 999"
[[ -n "${GH_REPO-}" ]] || die "GH_REPO is not set"

# Published engines, newest first. Drafts are engines still being uploaded.
tags="$(gh release list --limit 1000 --json tagName,createdAt,isDraft \
  --jq '[.[] | select(.isDraft | not) | select(.tagName | startswith("chromium-engine-"))]
        | sort_by(.createdAt) | reverse | .[].tagName')" || die "could not list the releases"

work="$(mktemp -d)"
cleanup() {
  local dir
  for dir in "$work"/tree-*; do
    [[ -d "$dir" ]] && git worktree remove --force "$dir" >/dev/null 2>&1
  done
  rm -rf "$work"
}
trap cleanup EXIT

# key_of <label> <sha> [<ref>]: prints the engine key at <sha>, fetching <ref>
# (or the commit itself) from origin when the checkout doesn't have it.
key_of() {
  local label="$1" sha="$2" ref="${3-$2}" dir
  if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
    git fetch --quiet --no-tags origin "$ref" 2>/dev/null || true
  fi
  if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "::warning::Could not fetch $label ($sha); its engine isn't protected" >&2
    return 1
  fi
  dir="$(mktemp -d "$work/tree-XXXXXX")"
  git worktree add --detach --quiet "$dir" "$sha" 2>/dev/null || {
    echo "::warning::Could not check out $label ($sha); its engine isn't protected" >&2
    return 1
  }
  if ! "$dir/scripts/engine-key.sh" "$dir" 2>/dev/null; then
    echo "::warning::Could not work out the engine key of $label ($sha); its engine isn't protected" >&2
    git worktree remove --force "$dir" >/dev/null 2>&1 || true
    return 1
  fi
  git worktree remove --force "$dir" >/dev/null 2>&1 || true
}

# "<tag> <who>" lines: the engines main and open pull requests need. Bash 3.2
# has no associative arrays.
needed=""
need() {
  needed+="chromium-engine-$1 $2"$'\n'
}
# needed_by <tag>: prints who needs <tag>, comma-separated, or nothing.
needed_by() {
  awk -v tag="$1" '$1 == tag { out = out (out == "" ? "" : ", ") $2 } END { print out }' <<<"$needed"
}

main_sha="$(gh api "repos/$GH_REPO/branches/main" --jq .commit.sha)" || die "could not read main's head"
if key="$(key_of main "$main_sha" main)"; then
  need "$key" main
fi
prs="$(gh pr list --state open --limit 200 --json number,headRefOid \
  --jq '.[] | "\(.number) \(.headRefOid)"')" || die "could not list the open pull requests"
while read -r number sha; do
  [[ -n "$number" ]] || continue
  if key="$(key_of "#$number" "$sha" "refs/pull/$number/head")"; then
    need "$key" "#$number"
  fi
done <<<"$prs"

kept=0 deleted=0 i=0
while IFS= read -r tag; do
  [[ -n "$tag" ]] || continue
  i=$((i + 1))
  by="$(needed_by "$tag")"
  if (( i <= keep )); then
    echo "keep    $tag (one of the $keep newest${by:+; needed by $by})"
    kept=$((kept + 1))
  elif [[ -n "$by" ]]; then
    echo "keep    $tag (needed by $by)"
    kept=$((kept + 1))
  elif $dry_run; then
    echo "delete  $tag (dry run)"
    deleted=$((deleted + 1))
  else
    echo "delete  $tag"
    gh release delete "$tag" --cleanup-tag --yes
    deleted=$((deleted + 1))
  fi
done <<<"$tags"

if $dry_run; then
  echo "Kept $kept engine(s); would delete $deleted"
else
  echo "Kept $kept engine(s); deleted $deleted"
fi

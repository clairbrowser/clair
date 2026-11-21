#!/bin/bash
# Keeps one engine update pull request open, from the branch engine-update,
# for the newest ungoogled-chromium tag (automate-engine-updates D2 to D5).
# engine-update.yml runs it on a schedule, in a checkout of main.
#
#   engine-update.sh
#
# When a tag newer than main's pin exists, it opens a draft pull request that
# moves the pin to it and adds the release note, or adds that commit on top of
# the open pull request's branch. It leaves the branch alone once the owner has
# started an engine build for its current pin (the pull request is "held"),
# unless TAKE_NEWEST is true. It never force-pushes, rebases or merges, never
# pushes to main, and never starts an engine build.
#
# Environment:
#   GH_REPO           owner/name of this repository
#   GH_TOKEN          the GitHub App's token: pull requests, and git over HTTPS
#   ACTIONS_TOKEN     a token that can read Actions runs (default: GH_TOKEN)
#   BOT_NAME          the App's bot user, the author of its commits
#   BOT_EMAIL         that user's commit email
#   TAKE_NEWEST       true to move a held pull request's pin anyway
#   ENGINE_UPDATE_REMOTE     this repository's git URL (default: GitHub's)
#   ENGINE_UPDATE_MACOS_URL  ungoogled-chromium-macos's git URL (default: GitHub's)
#
# Uses git, gh and jq. The upstream URL comes from .gitmodules.

set -euo pipefail

branch=engine-update
marker_start='<!-- engine-update:start -->'
marker_end='<!-- engine-update:end -->'
fragment_body_prefix='Update the engine to Chromium '

die() {
  echo "engine-update: $1" >&2
  exit 1
}

[[ "${GH_REPO-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GH_REPO must be owner/name"
[[ -n "${GH_TOKEN-}" ]] || die "GH_TOKEN is not set"
[[ -n "${BOT_NAME-}" && "$BOT_NAME" =~ ^[A-Za-z0-9._-]+(\[bot\])?$ ]] || die "BOT_NAME must be the App's bot user"
[[ -n "${BOT_EMAIL-}" && "$BOT_EMAIL" =~ ^[A-Za-z0-9._+-]+(\[bot\])?@[A-Za-z0-9.-]+$ ]] || die "BOT_EMAIL must be the bot user's commit email"
take_newest="${TAKE_NEWEST:-false}"
[[ "$take_newest" == true || "$take_newest" == false ]] || die "TAKE_NEWEST must be true or false"
actions_token="${ACTIONS_TOKEN:-$GH_TOKEN}"
remote="${ENGINE_UPDATE_REMOTE:-https://github.com/$GH_REPO.git}"
macos_url="${ENGINE_UPDATE_MACOS_URL:-https://github.com/ungoogled-software/ungoogled-chromium-macos.git}"
owner="${GH_REPO%%/*}"

upstream_url="$(git config -f .gitmodules --get submodule.ungoogled-chromium.url)" ||
  die "run it at the root of a checkout: .gitmodules names no ungoogled-chromium URL"
upstream_web=""
if [[ "$upstream_url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  upstream_web="${upstream_url%.git}"
fi

work="$(mktemp -d)"
cleanup() {
  rm -rf "$work"
  git update-ref -d refs/engine-update/main 2>/dev/null || true
  git update-ref -d refs/engine-update/branch 2>/dev/null || true
}
trap cleanup EXIT

# Git with the App's token for this repository's remote. The helper reads the
# token from the environment when git asks, so it is never in a command line,
# the log or the checkout's configuration.
remote_git() {
  # shellcheck disable=SC2016 # expanded by the helper's shell, not this one
  git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' \
    "$@"
}

# --- Tags (D2) ---------------------------------------------------------------

# list_tags <url> <file>: writes "<tag> <commit>" lines, oldest first, for the
# tags whose names match the pattern. An annotated tag's commit is its peeled
# ^{} line.
list_tags() {
  git ls-remote --tags "$1" >"$work/ls-remote" || return 1
  awk '
    $1 !~ /^[0-9a-f]+$/ { next }
    {
      name = $2
      sub(/^refs\/tags\//, "", name)
      if (name ~ /\^\{\}$/) {
        sub(/\^\{\}$/, "", name)
        peeled[name] = $1
      } else {
        direct[name] = $1
      }
    }
    END {
      for (name in direct) {
        if (name !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$/) continue
        commit = (name in peeled) ? peeled[name] : direct[name]
        split(name, n, /[.-]/)
        print n[1], n[2], n[3], n[4], n[5], name, commit
      }
    }' "$work/ls-remote" |
    sort -k1,1n -k2,2n -k3,3n -k4,4n -k5,5n |
    awk '{ print $6, $7 }' >"$2"
}

# tag_of <commit>: the newest tag on <commit>, or nothing.
tag_of() {
  awk -v commit="$1" '$2 == commit { tag = $1 } END { if (tag != "") print tag }' "$work/tags"
}

# commit_of <tag>
commit_of() {
  awk -v tag="$1" '$1 == tag { print $2 }' "$work/tags"
}

# tag_newer <a> <b>: true when tag a is newer than tag b.
tag_newer() {
  local a b i
  IFS='.-' read -r -a a <<<"$1"
  IFS='.-' read -r -a b <<<"$2"
  for i in 0 1 2 3 4; do
    if (( 10#${a[i]} != 10#${b[i]} )); then
      (( 10#${a[i]} > 10#${b[i]} ))
      return
    fi
  done
  return 1
}

version_of() { echo "${1%-*}"; }
major_of() { echo "${1%%.*}"; }

# gitlink_of <commit>: the ungoogled-chromium commit pinned at <commit>.
gitlink_of() {
  git ls-tree "$1" ungoogled-chromium | awk '$2 == "commit" { print $3 }'
}

# --- The commit (D4) ---------------------------------------------------------

is_engine_fragment() {
  grep -qx 'kind: Updated' "$1" &&
    grep -Eq "^body: ['\"]?$fragment_body_prefix" "$1"
}

# make_commit <parent>: sets new_commit to a commit on top of <parent> that moves the pin
# to $target and leaves one engine release note: the bot's own fragment on the
# branch is rewritten, and any other engine fragment is deleted.
make_commit() {
  local parent="$1" path own="" name tree blob
  export GIT_INDEX_FILE="$work/index"
  rm -f "$GIT_INDEX_FILE"
  git read-tree "$parent"
  git update-index --cacheinfo "160000,$target_commit,ungoogled-chromium"
  while IFS= read -r path; do
    [[ "$path" == *.yaml ]] || continue
    git show "$parent:$path" >"$work/fragment"
    is_engine_fragment "$work/fragment" || continue
    # The bot's own fragment is one main doesn't have.
    if [[ -z "$own" ]] && ! git cat-file -e "$main_commit:$path" 2>/dev/null; then
      own="$path"
    else
      git update-index --force-remove "$path"
    fi
  done < <(git ls-tree --name-only "$parent" .changes/unreleased/)
  name="${own:-.changes/unreleased/Updated-$(date -u +%Y%m%d-%H%M%S).yaml}"
  blob="$(printf 'kind: Updated\nbody: %s%s (ungoogled-chromium %s)\ntime: %s\n' \
    "$fragment_body_prefix" "$(version_of "$target")" "$target" \
    "$(date -u +%Y-%m-%dT%H:%M:%S.000000+00:00)" | git hash-object -w --stdin)"
  git update-index --add --cacheinfo "100644,$blob,$name"
  tree="$(git write-tree)"
  unset GIT_INDEX_FILE
  new_commit="$(GIT_AUTHOR_NAME="$BOT_NAME" GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
    GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="$BOT_EMAIL" \
    git commit-tree "$tree" -p "$parent" -m "$(title_for "$target")")"
  [[ "$new_commit" =~ ^[0-9a-f]{40}$ ]] || die "could not make the commit"
}

title_for() {
  echo "build(engine): update to ungoogled-chromium $1"
}

push_branch() {
  remote_git push --quiet "$remote" "$1:refs/heads/$branch" ||
    die "pushing $branch was rejected; it may have moved since this run fetched it. The next run tries again."
}

# --- The description (D5) ----------------------------------------------------

# conflicts <head>: true when <head> doesn't merge cleanly into main.
conflicts() {
  local status=0
  git merge-tree --write-tree --quiet "$main_commit" "$1" >/dev/null 2>&1 || status=$?
  (( status == 1 ))
}

# write_block <to tag> <head> [<newer tag held back>]: the bot's part of the
# description, to $work/block.
write_block() {
  local to="$1" head="$2" newer="${3-}" version major from_major macos_tags kind
  version="$(version_of "$to")"
  major="$(major_of "$to")"
  from_major="$(major_of "$current")"
  {
    echo "$marker_start"
    echo "<!-- engine-update-tag: $to -->"
    echo "Moves the engine from ungoogled-chromium \`$current\` to \`$to\`."
    echo
    if [[ "$major" == "$from_major" ]]; then
      kind="patch-level"
      echo "- **Kind:** a patch-level update, within Chromium $major."
    else
      kind="major"
      echo "- **Kind:** a new major, from Chromium $from_major to Chromium $major."
    fi
    if [[ -n "$upstream_web" ]]; then
      echo "- **Upstream changes:** [$current...$to]($upstream_web/compare/$current...$to)"
    fi
    if list_tags_macos; then
      # Its tags name the version alone (157.0.8103.78) or with a suffix
      # (157.0.8103.78-1.1, 157.0.8103.78_arm64).
      macos_tags="$(awk -v v="$version" '$0 == v || index($0, v "-") == 1 || index($0, v "_") == 1' \
        "$work/macos-tags" | tr '\n' ' ' | sed 's/ $//; s/ /`, `/g')"
      if [[ -n "$macos_tags" ]]; then
        echo "- **ungoogled-chromium-macos:** has tagged this version: \`$macos_tags\`."
      else
        echo "- **ungoogled-chromium-macos:** has no tag for Chromium $version yet."
      fi
    else
      echo "- **ungoogled-chromium-macos:** its tags could not be read."
    fi
    echo "- **Engine build:** the pin changes, so the engine compiles Chromium from scratch (about 4 hours) on the owner's Mac. Only the owner starts it: \`gh workflow run engine.yml -f ref=$branch\`."
    echo "- **Ready for review** means every patch applies, not that the engine compiles. The comment below follows each patch check."
    if [[ "$kind" == major ]]; then
      echo
      echo "### Steps for a new major"
      echo
      echo "See \"Updating the engine\" in \`docs/building.md\`. ungoogled-chromium-macos's patches usually fail first, so this pull request stays a draft until they are synced."
      echo
      echo "- [ ] Sync \`downloads-arm64.ini\`, \`retrieve_and_unpack_resource.py\`, \`flags.macos.gn\` and \`patches/ungoogled-chromium-macos/\` (and \`patches/series\`) from ungoogled-chromium-macos's tag for $version, with the toolchain steps of its \`build.sh\` and \`build_crubit.sh\`. Update the commit in \`CREDITS.md\`."
      echo "- [ ] Keep Clair's \`sha256\` lines for \`[rust]\` and \`[rustc-dev]\` in \`downloads-arm64.ini\`, updated for the new toolchain."
      echo "- [ ] Check the SDK that ungoogled-chromium-macos builds $version with against \`macos-sdk-major\`."
      echo "- [ ] Fix the Clair patches the comment below lists, from the top."
    fi
    if [[ -n "$newer" ]]; then
      echo
      echo "> [!NOTE]"
      echo "> ungoogled-chromium has tagged \`$newer\`, but this pull request stays on \`$to\`: an engine build was started for its pin, and moving the pin would make the next build a full one again. Merge this pull request and the next run opens one for \`$newer\`, or take it now with \`gh workflow run engine-update.yml -f take-newest=true\`."
    fi
    if conflicts "$head"; then
      echo
      echo "> [!WARNING]"
      echo "> This pull request conflicts with \`main\`. GitHub runs no CI on it until the conflict is resolved, so the patch check comment below won't change until then."
    fi
    echo
    echo "Kept up to date by \`.github/workflows/engine-update.yml\`, which never starts an engine build or merges. Text outside this part of the description is left as it is."
    echo "$marker_end"
  } >"$work/block"
}

macos_listed=""
list_tags_macos() {
  if [[ -z "$macos_listed" ]]; then
    if git ls-remote --tags "$macos_url" >"$work/macos-ls-remote" 2>/dev/null; then
      awk '{ name = $2; sub(/^refs\/tags\//, "", name); sub(/\^\{\}$/, "", name); print name }' \
        "$work/macos-ls-remote" | grep -E '^[0-9]+(\.[0-9]+){3}([-_][A-Za-z0-9._-]*)?$' | LC_ALL=C sort -u >"$work/macos-tags" || true
      macos_listed=yes
    else
      macos_listed=no
    fi
  fi
  [[ "$macos_listed" == yes ]]
}

# merge_body <current body file> <out>: the description with the bot's part
# replaced by $work/block, keeping everything outside the markers.
merge_body() {
  # GitHub may return the body with CRLF line ends and without a final newline.
  tr -d '\r' <"$1" >"$work/body-current"
  if [[ -s "$work/body-current" && -n "$(tail -c 1 "$work/body-current")" ]]; then
    echo >>"$work/body-current"
  fi
  if grep -qxF "$marker_start" "$work/body-current" && grep -qxF "$marker_end" "$work/body-current"; then
    awk -v start="$marker_start" -v end="$marker_end" -v block="$work/block" '
      $0 == start && !done { while ((getline line < block) > 0) print line; skipping = 1; next }
      skipping { if ($0 == end) { skipping = 0; done = 1 } next }
      { print }' "$work/body-current" >"$2"
  else
    cat "$work/block" >"$2"
    if [[ -s "$work/body-current" ]]; then
      printf '\n' >>"$2"
      cat "$work/body-current" >>"$2"
    fi
  fi
}

# --- GitHub ------------------------------------------------------------------

api() {
  gh api "$@" || die "the GitHub API call '$1' failed"
}

# update_pr <number> <body file> [<title>]
update_pr() {
  if [[ -n "${3-}" ]]; then
    jq -n --arg title "$3" --rawfile body "$2" '{title: $title, body: $body}' >"$work/request.json"
  else
    jq -n --rawfile body "$2" '{body: $body}' >"$work/request.json"
  fi
  api -X PATCH "repos/$GH_REPO/pulls/$1" --input "$work/request.json" >/dev/null
}

# --- Main --------------------------------------------------------------------

list_tags "$upstream_url" "$work/tags" || die "could not list the tags of $upstream_url"
[[ -s "$work/tags" ]] || die "$upstream_url has no tags of the form 1.2.3.4-5"

remote_git fetch --quiet --no-tags "$remote" "+refs/heads/main:refs/engine-update/main" ||
  die "could not fetch main"
main_commit="$(git rev-parse refs/engine-update/main)"
pin="$(gitlink_of "$main_commit")"
[[ -n "$pin" ]] || die "main has no ungoogled-chromium submodule"
current="$(tag_of "$pin")"
[[ -n "$current" ]] || die "main's ungoogled-chromium pin ($pin) is not on any tag of $upstream_url"
target="$(tail -n 1 "$work/tags" | awk '{ print $1 }')"
target_commit="$(commit_of "$target")"

if ! tag_newer "$target" "$current"; then
  echo "main is on $current, the newest tag. Nothing to do."
  exit 0
fi
echo "main is on $current; the newest tag is $target."

branch_commit=""
if [[ -n "$(remote_git ls-remote --heads "$remote" "refs/heads/$branch")" ]]; then
  remote_git fetch --quiet --no-tags "$remote" "+refs/heads/$branch:refs/engine-update/branch" ||
    die "could not fetch $branch"
  branch_commit="$(git rev-parse refs/engine-update/branch)"
fi

api "repos/$GH_REPO/pulls?state=open&head=$owner:$branch&per_page=100" >"$work/open.json"
open_count="$(jq 'length' "$work/open.json")"

if (( open_count == 0 )); then
  api "repos/$GH_REPO/pulls?state=closed&head=$owner:$branch&per_page=100" >"$work/closed.json"
  declined="$(jq -r --arg marker "<!-- engine-update-tag: $target -->" \
    '[.[] | select(.merged_at == null and ((.body // "") | contains($marker)))] | first | .number // empty' \
    "$work/closed.json")"
  if [[ -n "$declined" ]]; then
    echo "#$declined, for $target, was closed without merging: the owner declined that tag. Nothing to do until a newer one."
    exit 0
  fi
  if [[ -n "$branch_commit" ]]; then
    others="$(git log --format=%ae "$main_commit..$branch_commit" | grep -vxF "$BOT_EMAIL" || true)"
    if [[ -n "$others" ]]; then
      die "the branch $branch exists with no open pull request, and has commits that aren't the bot's. Delete or rename it, and the next run starts again from main."
    fi
    echo "Deleting the leftover branch $branch: every commit it has ahead of main is the bot's."
    remote_git push --quiet "$remote" --delete "$branch" || die "could not delete the leftover branch $branch"
  fi
  make_commit "$main_commit"
  push_branch "$new_commit"
  write_block "$target" "$new_commit"
  cp "$work/block" "$work/body"
  jq -n --arg title "$(title_for "$target")" --arg head "$branch" --rawfile body "$work/body" \
    '{title: $title, head: $head, base: "main", body: $body, draft: true}' >"$work/request.json"
  api -X POST "repos/$GH_REPO/pulls" --input "$work/request.json" >"$work/created.json"
  number="$(jq -r '.number' "$work/created.json")"
  echo "Opened draft pull request #$number, moving the pin from $current to $target."
  exit 0
fi

(( open_count == 1 )) || die "more than one pull request is open from $branch"
number="$(jq -r '.[0].number' "$work/open.json")"
is_draft="$(jq -r '.[0].draft' "$work/open.json")"
jq -j '.[0].body // ""' "$work/open.json" >"$work/body-old"
[[ -n "$branch_commit" ]] || die "#$number is open from $branch, but the branch could not be read"
branch_pin="$(gitlink_of "$branch_commit")"
branch_tag="$(tag_of "$branch_pin")"

if [[ "$branch_pin" == "$target_commit" ]]; then
  write_block "$target" "$branch_commit"
  merge_body "$work/body-old" "$work/body"
  if cmp -s "$work/body" "$work/body-current"; then
    echo "#$number is already on $target. Nothing to do."
  else
    update_pr "$number" "$work/body"
    echo "#$number is already on $target; refreshed its description."
  fi
  exit 0
fi

# Held (D3): an engine build was started for the branch's current pin.
pin_moved_at="$(TZ=UTC git log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd \
  "$branch_commit" -- ungoogled-chromium)"
GH_TOKEN="$actions_token" gh api "repos/$GH_REPO/actions/workflows/engine.yml/runs?per_page=100" \
  >"$work/runs.json" || die "could not list engine.yml's runs"
held_run="$(jq -r --arg title "Engine: $branch" --arg since "$pin_moved_at" \
  '[.workflow_runs[] | select(.display_title == $title and .created_at > $since)] | first | .html_url // empty' \
  "$work/runs.json")"

if [[ -n "$held_run" && "$take_newest" != true ]]; then
  echo "#$number is held on ${branch_tag:-$branch_pin}: an engine build was started for its pin ($held_run). Leaving $branch unchanged; start engine-update.yml with take-newest to move it to $target."
  write_block "${branch_tag:-$current}" "$branch_commit" "$target"
  merge_body "$work/body-old" "$work/body"
  if ! cmp -s "$work/body" "$work/body-current"; then
    update_pr "$number" "$work/body"
    echo "Refreshed #$number's description."
  fi
  exit 0
fi

if [[ -n "$held_run" ]]; then
  echo "#$number is held, but take-newest was asked for: moving it to $target."
fi
make_commit "$branch_commit"
push_branch "$new_commit"
if [[ "$is_draft" != true ]]; then
  gh pr ready --undo "$number" >/dev/null || die "could not convert #$number to a draft"
fi
write_block "$target" "$new_commit"
merge_body "$work/body-old" "$work/body"
update_pr "$number" "$work/body" "$(title_for "$target")"
echo "Moved #$number from ${branch_tag:-$branch_pin} to $target, on top of the branch's commits."

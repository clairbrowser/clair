#!/bin/bash
# Tests for engine-update.sh, with a local stand-in for ungoogled-chromium and
# ungoogled-chromium-macos (their tags), a bare repository as this
# repository's remote, and a fake gh that serves pull requests and engine.yml
# runs and records what the script asks for.

set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/engine-update.sh"
work="$(mktemp -d)"
work="$(cd "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT
failures=0

export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name owner
git config --global user.email owner@example.com
git config --global commit.gpgsign false
git config --global tag.gpgsign false
git config --global init.defaultBranch main
git config --global protocol.file.allow always

bot_name='clair-engine[bot]'
bot_email='1+clair-engine[bot]@users.noreply.github.com'
branch=engine-update

# --- Upstream: one commit per tag name, tags set per test --------------------

upstream="$work/upstream"
git init -q "$upstream"
all_tags="99.0.1.2-1 157.0.900.500-1 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1 158.0.8127.36-1 158.0.8127.40-1 untagged"
for name in $all_tags; do
  git -C "$upstream" commit -q --allow-empty -m "$name"
  echo "$name $(git -C "$upstream" rev-parse HEAD)" >>"$work/commits"
done
commit_for() { awk -v n="$1" '$1 == n { print $2 }' "$work/commits"; }

# set_tags <name>...: upstream has exactly these tags. <name>@a is annotated;
# <other>=<name> tags <name>'s commit as <other> (a name outside the pattern).
set_tags() {
  local spec name tagname
  git -C "$upstream" tag -l | while read -r t; do git -C "$upstream" tag -d "$t" >/dev/null; done
  for spec in "$@"; do
    name="${spec%@a}"
    tagname="${name%%=*}"
    name="${name#*=}"
    if [[ "$spec" == *@a ]]; then
      git -C "$upstream" tag -a -m "$tagname" "$tagname" "$(commit_for "$name")"
    else
      git -C "$upstream" tag "$tagname" "$(commit_for "$name")"
    fi
  done
}

macos="$work/macos"
git init -q "$macos"
git -C "$macos" commit -q --allow-empty -m init
set_macos_tags() {
  local t
  git -C "$macos" tag -l | while read -r t; do git -C "$macos" tag -d "$t" >/dev/null; done
  for t in "$@"; do git -C "$macos" tag "$t"; done
}

# --- This repository ---------------------------------------------------------

origin="$work/origin.git"
seed="$work/seed"

# make_seed <pin tag> <with engine fragment: yes|no>: main's commit.
make_seed() {
  rm -rf "$seed" "$origin"
  git init -q "$seed"
  printf '[submodule "ungoogled-chromium"]\n\tpath = ungoogled-chromium\n\turl = %s\n' "$upstream" >"$seed/.gitmodules"
  mkdir -p "$seed/.changes/unreleased"
  printf 'kind: New\nbody: Something new\ntime: 2026-11-01T00:00:00.000000-05:00\n' \
    >"$seed/.changes/unreleased/New-20261101-000000.yaml"
  printf 'kind: Updated\nbody: Update Sparkle to 2.8\ntime: 2026-11-02T00:00:00.000000-05:00\n' \
    >"$seed/.changes/unreleased/Updated-20261102-000000.yaml"
  if [[ "$2" == yes ]]; then
    printf 'kind: Updated\nbody: Update the engine to Chromium 157.0.8103.78 (ungoogled-chromium 157.0.8103.78-1)\ntime: 2026-11-19T14:11:22.000000-05:00\n' \
      >"$seed/.changes/unreleased/Updated-20261119-141122.yaml"
  fi
  echo "readme" >"$seed/README.md"
  git -C "$seed" add -A
  git -C "$seed" update-index --add --cacheinfo "160000,$(commit_for "$1"),ungoogled-chromium"
  git -C "$seed" commit -q -m "main"
  git clone -q --bare "$seed" "$origin"
}

main_head() { git -C "$origin" rev-parse refs/heads/main; }
branch_head() { git -C "$origin" rev-parse --verify -q "refs/heads/$branch"; }
pin_at() { git -C "$origin" ls-tree "$1" ungoogled-chromium | awk '{ print $3 }'; }

# owner_commit <ref> <file> <content>: the owner pushes a commit to <ref>.
owner_commit() {
  rm -rf "$work/owner"
  git clone -q "$origin" "$work/owner"
  git -C "$work/owner" checkout -q "${1#refs/heads/}"
  mkdir -p "$(dirname "$work/owner/$2")"
  echo "$3" >"$work/owner/$2"
  git -C "$work/owner" add -A
  git -C "$work/owner" commit -q -m "owner: $2"
  git -C "$work/owner" push -q origin "HEAD:$1"
}

# --- Fake gh -----------------------------------------------------------------

gh_state="$work/gh"
mkdir "$work/bin"
cat >"$work/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s | %s\n' "$GH_TOKEN" "$*" >>"$FAKE_GH/log"
input=""
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
  [[ "${args[i]}" == --input ]] && input="${args[i+1]}"
done
case "$*" in
  "api repos/o/r/pulls?state=open&head=o:engine-update&per_page=100") cat "$FAKE_GH/open.json" ;;
  "api repos/o/r/pulls?state=closed&head=o:engine-update&per_page=100") cat "$FAKE_GH/closed.json" ;;
  "api repos/o/r/actions/workflows/engine.yml/runs?per_page=100") cat "$FAKE_GH/runs.json" ;;
  "api -X POST repos/o/r/pulls --input "*) cp "$input" "$FAKE_GH/created.json"; echo '{"number": 300}' ;;
  "api -X PATCH repos/o/r/pulls/"*" --input "*) cp "$input" "$FAKE_GH/patched.json"; echo '{}' ;;
  "pr ready --undo "*) ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$work/bin/gh"

# reset <pin tag> <engine fragment on main: yes|no>: a fresh main, no branch,
# no pull requests and no engine runs.
reset() {
  make_seed "$1" "$2"
  rm -rf "$gh_state"
  mkdir "$gh_state"
  echo '[]' >"$gh_state/open.json"
  echo '[]' >"$gh_state/closed.json"
  echo '{"workflow_runs": []}' >"$gh_state/runs.json"
}

run() {
  rm -rf "$work/checkout"
  git clone -q "$origin" "$work/checkout"
  : >"$gh_state/log"
  rm -f "$gh_state/created.json" "$gh_state/patched.json"
  (cd "$work/checkout" && PATH="$work/bin:$PATH" FAKE_GH="$gh_state" GH_REPO=o/r \
    GH_TOKEN=app-token ACTIONS_TOKEN=actions-token BOT_NAME="$bot_name" BOT_EMAIL="$bot_email" \
    ENGINE_UPDATE_REMOTE="$origin" ENGINE_UPDATE_MACOS_URL="$macos" env "$@" \
    "$script" >"$work/out" 2>"$work/err")
  status=$?
}

# open_pr_from_created [draft]: the pull request the last run created is open.
open_pr_from_created() {
  jq --argjson draft "${1:-true}" '[{number: 300, draft: $draft, body: .body, title: .title}]' \
    "$gh_state/created.json" >"$gh_state/open.json"
}

# open_pr_with_body <file> [draft]
open_pr_with_body() {
  jq -n --rawfile body "$1" --argjson draft "${2:-true}" '[{number: 300, draft: $draft, body: $body}]' \
    >"$gh_state/open.json"
}

add_run() { # <title> <created_at> <status> <conclusion>
  jq --arg t "$1" --arg c "$2" --arg s "$3" --arg k "$4" \
    '.workflow_runs = [{display_title: $t, created_at: $c, status: $s, conclusion: (if $k == "" then null else $k end), html_url: "https://example.com/run"}] + .workflow_runs' \
    "$gh_state/runs.json" >"$gh_state/runs.tmp" && mv "$gh_state/runs.tmp" "$gh_state/runs.json"
}

pass() { echo "ok       $1"; }
fail() {
  echo "FAIL     $1"
  echo "--- out"; cat "$work/out"; echo "--- err"; cat "$work/err"; echo "--- gh"; cat "$gh_state/log"
  failures=$((failures + 1))
}
check() { # <name> <command...>
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
out_has() { grep -qF -- "$1" "$work/out"; }
err_has() { grep -qF -- "$1" "$work/err"; }
created_body_has() { jq -r .body "$gh_state/created.json" | grep -qF -- "$1"; }
patched_body_has() { jq -r .body "$gh_state/patched.json" | grep -qF -- "$1"; }
gh_called() { grep -qF -- "$1" "$gh_state/log"; }
no_branch() { ! branch_head >/dev/null; }
no_pr_change() {
  [[ ! -e "$gh_state/created.json" && ! -e "$gh_state/patched.json" ]] && ! gh_called "pr ready"
}
# changed_files <from> <to>: name-status lines between two commits.
changed_files() { git -C "$origin" diff --name-status "$1" "$2" | sort; }
fragment_on() { # <commit>: the path of the engine fragment the bot wrote.
  git -C "$origin" ls-tree --name-only "$1" .changes/unreleased/ | while read -r f; do
    git -C "$origin" show "$1:$f" | grep -q '^body: Update the engine to Chromium ' && echo "$f"
  done
}

# --- No newer tag ------------------------------------------------------------

reset 157.0.8103.78-1 yes
set_tags 157.0.8103.78-1 99.0.1.2-1 v200.0.0.0-1=158.0.8127.40-1 159.0.1.1=158.0.8127.36-1
run
check "no newer tag: exits 0" test "$status" -eq 0
check "no newer tag: says there is nothing to do" out_has "main is on 157.0.8103.78-1, the newest tag. Nothing to do."
check "no newer tag: an older major and names outside the pattern are ignored" no_branch
check "no newer tag: no pull request is touched" no_pr_change

# --- Pin on no tag -----------------------------------------------------------

reset untagged yes
set_tags 157.0.8103.78-1 157.0.8103.78-2
run
check "a pin that matches no tag fails" test "$status" -eq 1
check "a pin that matches no tag: says so" err_has "is not on any tag"
check "a pin that matches no tag: nothing is pushed" no_branch

# --- Patch-level tag, no pull request; ordering --------------------------------

reset 157.0.8103.78-1 yes
set_tags 99.0.1.2-1 157.0.900.500-1 157.0.8103.78-1 157.0.8103.78-2@a 157.0.8103.100-1@a 158.0.8127.36-1-beta=158.0.8127.36-1
set_macos_tags 157.0.8103.78-1.1 157.0.8103.100-1.1
run
check "patch-level: exits 0" test "$status" -eq 0
check "ordering: 157.0.8103.100-1 is newer than 157.0.8103.78-2, 157.0.900.500-1 and 99.0.1.2-1" \
  test "$(pin_at "refs/heads/$branch")" == "$(commit_for 157.0.8103.100-1)"
check "an annotated tag's pin is its commit, not the tag object" \
  eval 'test "$(pin_at "refs/heads/$branch")" == "$(git -C "$upstream" rev-parse "157.0.8103.100-1^{commit}")" &&
    test "$(pin_at "refs/heads/$branch")" != "$(git -C "$upstream" rev-parse 157.0.8103.100-1)"'
check "patch-level: the branch is one commit on top of main" \
  test "$(git -C "$origin" rev-parse "refs/heads/$branch^")" == "$(main_head)"
check "patch-level: the commit is the bot's" \
  test "$(git -C "$origin" log -1 --format='%an <%ae>|%cn' "refs/heads/$branch")" == "$bot_name <$bot_email>|$bot_name"
check "patch-level: the commit message names the tag" \
  test "$(git -C "$origin" log -1 --format=%s "refs/heads/$branch")" == "build(engine): update to ungoogled-chromium 157.0.8103.100-1"
new_fragment="$(fragment_on "refs/heads/$branch")"
expected="$(printf 'A\t%s\nD\t.changes/unreleased/Updated-20261119-141122.yaml\nM\tungoogled-chromium' "$new_fragment" | sort)"
check "patch-level: only the pin and the fragments change: main's engine fragment is deleted and one is added" \
  test "$(changed_files "$(main_head)" "refs/heads/$branch")" == "$expected"
check "the new fragment is named as changie names them" \
  eval '[[ "$new_fragment" =~ ^\.changes/unreleased/Updated-[0-9]{8}-[0-9]{6}\.yaml$ ]]'
check "the new fragment's body names the version and the tag" \
  eval 'git -C "$origin" show "refs/heads/$branch:$new_fragment" | grep -qx "body: Update the engine to Chromium 157.0.8103.100 (ungoogled-chromium 157.0.8103.100-1)"'
check "patch-level: a draft pull request is opened from $branch to main" \
  eval 'jq -e ".draft == true and .head == \"engine-update\" and .base == \"main\" and .title == \"build(engine): update to ungoogled-chromium 157.0.8103.100-1\"" "$gh_state/created.json" >/dev/null'
check "patch-level: the description says patch-level" created_body_has "a patch-level update, within Chromium 157"
check "patch-level: the description carries the tag marker" created_body_has "<!-- engine-update-tag: 157.0.8103.100-1 -->"
check "patch-level: the description says ungoogled-chromium-macos has tagged it" created_body_has '`157.0.8103.100-1.1`'
check "patch-level: the description has no new-major steps" eval '! created_body_has "Steps for a new major"'
check "the description has no bare @name" eval '! jq -r .body "$gh_state/created.json" | grep -qE "(^|[^\`A-Za-z0-9])@[A-Za-z0-9]"'
check "pull requests use the App's token" gh_called "app-token | api -X POST repos/o/r/pulls"
check "the token is not in the checkout's git configuration" \
  eval '! grep -rq "app-token" "$work/checkout/.git/config"'
check "the token is not in the log" eval '! grep -q "app-token" "$work/out" "$work/err"'

# A second run changes nothing.
open_pr_from_created
before="$(branch_head)"
run
check "second run: exits 0" test "$status" -eq 0
check "second run: the branch is unchanged" test "$(branch_head)" == "$before"
check "second run: the pull request is unchanged" no_pr_change
check "second run: says it is already on the tag" out_has "#300 is already on 157.0.8103.100-1. Nothing to do."

# --- New major, no pull request; no engine fragment on main -------------------

reset 157.0.8103.78-1 no
set_tags 157.0.8103.78-1 158.0.8127.36-1
set_macos_tags 157.0.8103.78-1.1
run
check "new major: exits 0" test "$status" -eq 0
check "new major: the pin moves" test "$(pin_at "refs/heads/$branch")" == "$(commit_for 158.0.8127.36-1)"
check "new major: the description says it is a new major" created_body_has "a new major, from Chromium 157 to Chromium 158"
check "new major: the description lists the manual steps" created_body_has "Steps for a new major"
check "new major: the description says ungoogled-chromium-macos has no tag yet" \
  created_body_has "has no tag for Chromium 158.0.8127.36 yet"
new_fragment="$(fragment_on "refs/heads/$branch")"
expected="$(printf 'A\t%s\nM\tungoogled-chromium' "$new_fragment" | sort)"
check "no engine fragment on main: one is added, and the other fragments stay" \
  test "$(changed_files "$(main_head)" "refs/heads/$branch")" == "$expected"

# --- Declined tag --------------------------------------------------------------

reset 157.0.8103.78-1 yes
set_tags 157.0.8103.78-1 157.0.8103.78-2
jq -n '[{number: 290, merged_at: "2026-11-01T00:00:00Z", body: "<!-- engine-update-tag: 157.0.8103.78-2 -->"},
        {number: 291, merged_at: null, body: "x\n<!-- engine-update-tag: 157.0.8103.78-2 -->\ny"}]' \
  >"$gh_state/closed.json"
run
check "declined: exits 0" test "$status" -eq 0
check "declined: says the owner declined it" out_has "#291, for 157.0.8103.78-2, was closed without merging"
check "declined: no branch and no pull request" eval 'no_branch && no_pr_change'

# A newer tag than the declined one opens a pull request.
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
run
check "declined, then a newer tag: a pull request is opened" \
  eval 'test "$status" -eq 0 && test -e "$gh_state/created.json"'

# --- An open pull request takes a newer tag ------------------------------------

# set_up_open_pr <pin tag> <first tag>: main on <pin tag>, the bot's pull
# request open on <first tag>, as a ready pull request.
set_up_open_pr() {
  reset "$1" yes
  set_tags "$1" "$2"
  run
  open_pr_from_created false
}

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
bot_first="$(branch_head)"
bot_fragment="$(fragment_on "$bot_first")"
owner_commit "refs/heads/$branch" patches/fix.patch "a fix"
owner_head="$(branch_head)"
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
run
check "newer tag on the owner's commit: exits 0" test "$status" -eq 0
check "newer tag on the owner's commit: a commit is added on top of it" \
  test "$(git -C "$origin" rev-parse "refs/heads/$branch^")" == "$owner_head"
check "newer tag on the owner's commit: the pin moves" \
  test "$(pin_at "refs/heads/$branch")" == "$(commit_for 157.0.8103.100-1)"
check "newer tag on the owner's commit: the owner's fix is kept" \
  eval 'git -C "$origin" cat-file -e "refs/heads/$branch:patches/fix.patch"'
rewritten_own_fragment() {
  [[ "$(fragment_on "refs/heads/$branch")" == "$bot_fragment" ]] &&
    git -C "$origin" show "refs/heads/$branch:$bot_fragment" |
    grep -qx "body: Update the engine to Chromium 157.0.8103.100 (ungoogled-chromium 157.0.8103.100-1)"
}
check "the bot rewrites its own fragment when the pin moves again" rewritten_own_fragment
check "main's engine fragment stays deleted" \
  eval '! git -C "$origin" cat-file -e "refs/heads/$branch:.changes/unreleased/Updated-20261119-141122.yaml" 2>/dev/null'
check "newer tag: the pull request is converted to a draft" gh_called "app-token | pr ready --undo 300"
check "newer tag: the title names the newer tag" \
  eval 'jq -e ".title == \"build(engine): update to ungoogled-chromium 157.0.8103.100-1\"" "$gh_state/patched.json" >/dev/null'
check "newer tag: the description names the newer tag" patched_body_has "<!-- engine-update-tag: 157.0.8103.100-1 -->"

# A draft pull request isn't converted again.
set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
open_pr_from_created true
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
run
check "newer tag on a draft: it isn't converted again" eval 'test "$status" -eq 0 && ! gh_called "pr ready"'

# --- Held ----------------------------------------------------------------------

for state in "in_progress|" "completed|failure" "completed|success"; do
  set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
  before="$(branch_head)"
  add_run "Engine: engine-update" 2999-01-01T00:00:00Z "${state%|*}" "${state#*|}"
  set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
  run
  label="held by an engine run (${state%|*} ${state#*|})"
  check "$label: exits 0" test "$status" -eq 0
  check "$label: the branch is unchanged" test "$(branch_head)" == "$before"
  check "$label: the log says it is held" out_has "#300 is held on 157.0.8103.78-2"
  check "$label: the description names the newer tag and why" \
    eval 'patched_body_has "ungoogled-chromium has tagged \`157.0.8103.100-1\`, but this pull request stays on \`157.0.8103.78-2\`"'
  check "$label: the description keeps the pull request's own tag" patched_body_has "<!-- engine-update-tag: 157.0.8103.78-2 -->"
  check "$label: it stays as it was" eval '! gh_called "pr ready"'
  check "$label: engine.yml's runs are read with the Actions token" \
    gh_called "actions-token | api repos/o/r/actions/workflows/engine.yml/runs?per_page=100"
done

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
add_run "Engine: engine-update" 2000-01-01T00:00:00Z completed success
add_run "Engine: main" 2999-01-01T00:00:00Z in_progress ""
add_run "Engine: engine-update-old" 2999-01-01T00:00:00Z in_progress ""
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
run
check "an engine run from before the pin moved, or for another branch, doesn't hold" \
  test "$(pin_at "refs/heads/$branch")" == "$(commit_for 157.0.8103.100-1)"

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
add_run "Engine: engine-update" 2999-01-01T00:00:00Z in_progress ""
set_tags 157.0.8103.78-1 157.0.8103.78-2 158.0.8127.36-1
run TAKE_NEWEST=true
check "take-newest moves a held pin" \
  eval 'test "$status" -eq 0 && test "$(pin_at "refs/heads/$branch")" == "$(commit_for 158.0.8127.36-1)"'
check "take-newest: the log says so" out_has "take-newest was asked for"

# --- Conflicts with main -------------------------------------------------------

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
owner_commit "refs/heads/$branch" README.md "branch readme"
owner_commit refs/heads/main README.md "main readme"
run
check "a pull request that conflicts with main: the description says so" \
  eval 'test "$status" -eq 0 && patched_body_has "This pull request conflicts with \`main\`"'

# --- Description edited outside the markers -------------------------------------

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
{
  echo "Owner's note before."
  echo
  jq -r '.[0].body' "$gh_state/open.json" | sed 's/a patch-level update/an outdated line/'
  echo
  echo "Owner's note after."
} >"$work/edited-body"
open_pr_with_body "$work/edited-body"
run
check "edited description: the bot's part is refreshed" \
  eval 'patched_body_has "a patch-level update" && ! patched_body_has "an outdated line"'
first_and_last() {
  jq -j .body "$gh_state/patched.json" >"$work/patched-body"
  [[ "$(head -n 1 "$work/patched-body")" == "Owner's note before." &&
    "$(tail -n 1 "$work/patched-body")" == "Owner's note after." ]]
}
check "edited description: the owner's text outside the markers is kept" first_and_last
check "edited description: no blank lines are added at the end" \
  test "$(jq -j .body "$gh_state/patched.json" | tail -c 2 | od -An -c | tr -d ' ')" == '.\n'
check "edited description: the bot's part appears once" \
  test "$(jq -r .body "$gh_state/patched.json" | grep -c '<!-- engine-update:start -->')" -eq 1

# --- Leftover branch -------------------------------------------------------------

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
echo '[]' >"$gh_state/open.json"
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
run
check "a leftover branch with only the bot's commits: deleted and started again from main" \
  eval 'test "$status" -eq 0 && test "$(git -C "$origin" rev-parse "refs/heads/$branch^")" == "$(main_head)" &&
    test "$(pin_at "refs/heads/$branch")" == "$(commit_for 157.0.8103.100-1)" && test -e "$gh_state/created.json"'
check "a leftover branch: the log says it was deleted" out_has "Deleting the leftover branch"

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
owner_commit "refs/heads/$branch" patches/fix.patch "a fix"
before="$(branch_head)"
echo '[]' >"$gh_state/open.json"
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
run
check "a leftover branch with other commits: fails" test "$status" -eq 1
check "a leftover branch with other commits: names the branch" err_has "the branch engine-update exists"
check "a leftover branch with other commits: is left alone" \
  eval 'test "$(branch_head)" == "$before" && no_pr_change'

# --- A rejected push -------------------------------------------------------------

set_up_open_pr 157.0.8103.78-1 157.0.8103.78-2
set_tags 157.0.8103.78-1 157.0.8103.78-2 157.0.8103.100-1
cat >"$origin/hooks/pre-receive" <<'HOOK'
#!/bin/bash
exit 1
HOOK
chmod +x "$origin/hooks/pre-receive"
run
check "a rejected push fails the run" eval 'test "$status" -eq 1 && err_has "was rejected"'
check "a rejected push changes no pull request" no_pr_change
rm -f "$origin/hooks/pre-receive"

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"

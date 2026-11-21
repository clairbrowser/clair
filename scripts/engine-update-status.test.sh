#!/bin/bash
# Tests for engine-update-status.sh, with a fake gh that serves the open pull
# request, a CI run's jobs, the Patch check's log and the pull request's
# comments, and records what the script changes.

set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/engine-update-status.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

head_sha=1111111111111111111111111111111111111111
old_sha=2222222222222222222222222222222222222222
state="$work/gh"

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
  "api repos/o/r/actions/runs/77/jobs?per_page=100") cat "$FAKE_GH/jobs.json" ;;
  "api repos/o/r/actions/jobs/502/logs") cat "$FAKE_GH/patch.log" ;;
  "api repos/o/r/issues/300/comments?per_page=100") cat "$FAKE_GH/comments.json" ;;
  "api -X POST repos/o/r/issues/300/comments --input "*) cp "$input" "$FAKE_GH/posted.json"; echo '{}' ;;
  "api -X PATCH repos/o/r/issues/comments/"*" --input "*) cp "$input" "$FAKE_GH/patched.json"; echo '{}' ;;
  "pr ready 300" | "pr ready --undo 300") ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$work/bin/gh"

# reset <draft: true|false>: an open pull request on $head_sha, no comments.
reset() {
  rm -rf "$state"
  mkdir "$state"
  jq -n --arg sha "$head_sha" --argjson draft "$1" '[{number: 300, draft: $draft, head: {sha: $sha}}]' >"$state/open.json"
  echo '[]' >"$state/comments.json"
  : >"$state/patch.log"
}

# jobs <engine key> <patch check> [<engine check>] [<patch check seconds>]
jobs() {
  jq -n --arg key "$1" --arg patch "$2" --arg check "${3:-failure}" --argjson secs "${4:-1200}" '{jobs: [
    {id: 501, name: "Engine key", conclusion: $key, html_url: "https://example.com/job/501"},
    {id: 502, name: "Patch check", conclusion: (if $patch == "" then null else $patch end),
     started_at: "2026-11-20T10:00:00Z",
     completed_at: ((("2026-11-20T10:00:00Z" | fromdateiso8601) + $secs) | todateiso8601),
     html_url: "https://example.com/job/502"},
    {id: 503, name: "Engine check", conclusion: $check, html_url: "https://example.com/job/503"},
    {id: 504, name: "Script tests and lint", conclusion: "failure", html_url: "https://example.com/job/504"}]}' \
    >"$state/jobs.json"
}

run() { # <run conclusion> [<head sha>]
  : >"$state/log"
  rm -f "$state/posted.json" "$state/patched.json"
  PATH="$work/bin:$PATH" FAKE_GH="$state" GH_REPO=o/r GH_TOKEN=job-token DRAFT_TOKEN=draft-token \
    RUN_ID=77 RUN_HEAD_SHA="${2:-$head_sha}" RUN_CONCLUSION="$1" \
    "$script" >"$work/out" 2>"$work/err"
  status=$?
}

pass() { echo "ok       $1"; }
fail() {
  echo "FAIL     $1"
  echo "--- out"; cat "$work/out"; echo "--- err"; cat "$work/err"; echo "--- gh"; cat "$state/log"
  failures=$((failures + 1))
}
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
gh_called() { grep -qF -- "$1" "$state/log"; }
posted_has() { jq -r .body "$state/posted.json" | grep -qF -- "$1"; }
made_ready() { gh_called "draft-token | pr ready 300" && ! gh_called "pr ready --undo"; }
made_draft() { gh_called "draft-token | pr ready --undo 300"; }
draft_untouched() { ! gh_called "pr ready"; }
nothing_changed() { draft_untouched && [[ ! -e "$state/posted.json" && ! -e "$state/patched.json" ]]; }

# --- Engine key passed, Patch check passed ------------------------------------

reset true
jobs success success failure
run success
check "patch check passed: exits 0" test "$status" -eq 0
check "patch check passed: the draft is marked ready, with the draft token" made_ready
check "patch check passed: the comment says every patch applies" posted_has "**Every Clair patch applies** at 1111111"
check "patch check passed: the comment gives the engine build command" posted_has "gh workflow run engine.yml -f ref=engine-update"
check "the comment starts with its marker" eval 'jq -r .body "$state/posted.json" | head -n 1 | grep -qx "<!-- engine-update-status -->"'

# --- Patch check skipped, engine published ------------------------------------

reset true
jobs success skipped success
run success
check "patch check skipped: marked ready" made_ready
check "engine published: the comment says no build is needed" posted_has "its engine is published: no engine build is needed"
check "engine published: no build command" eval '! posted_has "gh workflow run engine.yml"'

# --- Patch check failed: patches named -----------------------------------------

reset false
jobs success failure
cat >"$state/patch.log" <<'LOG'
2026-11-20T10:01:00.0000000Z INFO: * Applying data-paths.patch (28/49)
2026-11-20T10:01:01.0000000Z These patches in patches/series don't apply (a skipped patch can make a later one fail, so fix them from the top):
2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/data-paths.patch
2026-11-20T10:01:01.0000000Z clair-patch-failed: ungoogled-chromium-macos/fix-dsymutil.patch
2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/data-paths.patch
2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/$(touch pwned).patch
2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/with space.patch
2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/`id`.patch
2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/not-a-patch.txt
LOG
run failure
check "patches failed: exits 0" test "$status" -eq 0
check "patches failed: a ready pull request returns to draft, with the draft token" made_draft
check "patches failed: the comment counts them" posted_has "**2 Clair patches don't apply** at 1111111"
expected="$(printf -- '- `patches/clair/data-paths.patch`\n- `patches/ungoogled-chromium-macos/fix-dsymutil.patch`')"
check "patches failed: the comment lists each once, in order, and drops names outside the pattern" \
  test "$(jq -r .body "$state/posted.json" | grep '^- `patches/')" == "$expected"
check "patches failed: the comment links the log" posted_has "(https://example.com/job/502)"
check "a name from the log is never run" test ! -e pwned

# One patch.
reset true
jobs success failure
echo "2026-11-20T10:01:01.0000000Z clair-patch-failed: clair/data-paths.patch" >"$state/patch.log"
run failure
check "one patch failed: the comment says so" posted_has "**1 Clair patch doesn't apply**"
check "one patch failed: a draft stays a draft, untouched" draft_untouched

# --- Patch check failed elsewhere ------------------------------------------------

reset true
jobs success failure
echo "2026-11-20T10:01:01.0000000Z ERROR: download failed" >"$state/patch.log"
run failure
check "failed elsewhere: the comment says the check failed at another step" posted_has "**The patch check failed at another step** at 1111111 (failure)"
check "failed elsewhere: the comment links the job" posted_has "(https://example.com/job/502)"
check "failed elsewhere: stays a draft" draft_untouched

# --- Patch check timed out ----------------------------------------------------------

reset false
jobs success cancelled failure 7205
run cancelled
check "timed out (reported as cancelled): returns to draft" made_draft
check "timed out: the comment says so" posted_has "(timed_out)"

reset false
jobs success timed_out
run failure
check "timed out (reported as timed_out): returns to draft" made_draft

# --- Engine key failed ------------------------------------------------------------

reset false
jobs failure skipped
run failure
check "engine key failed: returns to draft" made_draft
check "engine key failed: the comment links the Engine key job" \
  eval 'posted_has "**The engine key could not be worked out**" && posted_has "(https://example.com/job/501)"'

# --- Changes nothing ----------------------------------------------------------------

reset false
jobs success cancelled failure 300
run cancelled
check "a cancelled run: exits 0" test "$status" -eq 0
check "a cancelled run changes nothing" nothing_changed

reset true
jobs success success
run success "$old_sha"
check "a result for a commit that is no longer the head changes nothing" nothing_changed
check "an old commit: the log says so" grep -q "is now 1111111" "$work/out"

reset true
echo '[]' >"$state/open.json"
jobs success success
run success
check "no open pull request: changes nothing" eval 'test "$status" -eq 0 && nothing_changed'

# --- The comment ----------------------------------------------------------------------

reset true
jobs success success
jq -n '[{id: 54, body: "Quoting <!-- engine-update-status --> in a review"},
        {id: 55, body: "<!-- engine-update-status -->\r\n**2 Clair patches don'"'"'t apply** at 0000000:"}]' \
  >"$state/comments.json"
run success
check "the comment is edited in place" \
  eval 'gh_called "api -X PATCH repos/o/r/issues/comments/55 --input" && test ! -e "$state/posted.json"'
check "the edited comment has the new result" \
  eval 'jq -r .body "$state/patched.json" | grep -qF "**Every Clair patch applies**"'

# Run it again with that comment in place: nothing is added or edited.
jq --rawfile body <(jq -j .body "$state/patched.json") '.[1].body = $body' "$state/comments.json" >"$state/c.json"
mv "$state/c.json" "$state/comments.json"
jq '.[0].draft = false' "$state/open.json" >"$state/o.json" && mv "$state/o.json" "$state/open.json"
run success
check "an up-to-date comment is not added twice or edited" \
  eval 'test ! -e "$state/posted.json" && test ! -e "$state/patched.json"'
check "a ready pull request that should be ready is left alone" draft_untouched

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"

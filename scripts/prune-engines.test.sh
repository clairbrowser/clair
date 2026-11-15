#!/bin/bash
# Tests for prune-engines.sh, in a scratch repository whose commits carry a
# stand-in engine-key.sh, with a fake gh that serves releases, main's head and
# open pull requests.

set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/prune-engines.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

repo="$work/repo"
git init -q "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config commit.gpgsign false
mkdir -p "$repo/scripts"
cat >"$repo/scripts/engine-key.sh" <<'KEY'
#!/bin/bash
cat "${1:-.}/key.txt"
KEY
chmod +x "$repo/scripts/engine-key.sh"

# commit <key>: commits a tree whose engine key is <key>, printing the hash.
# An empty key makes engine-key.sh fail.
commit() {
  if [[ -n "$1" ]]; then echo "$1" >"$repo/key.txt"; else rm -f "$repo/key.txt"; fi
  git -C "$repo" add -A
  git -C "$repo" commit -q --allow-empty -m "key ${1:-none}"
  git -C "$repo" rev-parse HEAD
}

# Releases k1 (oldest) to k9 (newest), and one draft.
releases="$(for i in 1 2 3 4 5 6 7 8 9; do
  printf '{"tagName":"chromium-engine-k%s","createdAt":"2026-11-0%sT00:00:00Z","isDraft":false},' "$i" "$i"
done)"
releases="[${releases}{\"tagName\":\"chromium-engine-kd\",\"createdAt\":\"2026-11-01T00:00:00Z\",\"isDraft\":true},{\"tagName\":\"v0.1.0\",\"createdAt\":\"2026-10-01T00:00:00Z\",\"isDraft\":false}]"

mkdir "$work/bin"
cat >"$work/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
[[ "$1 $2" != "${FAKE_FAIL-}" ]] || exit 1
jq_arg() { while (( $# > 0 )); do [[ "$1" == --jq ]] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "release list") jq -r "$(jq_arg "$@")" <<<"$FAKE_RELEASES" ;;
  "release delete") ;;
  "api repos/o/r/branches/main") echo "$FAKE_MAIN" ;;
  "pr list") printf '%s' "${FAKE_PRS-}" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$work/bin/gh"

run() {
  : >"$work/log"
  (cd "$repo" && PATH="$work/bin:$PATH" FAKE_GH_LOG="$work/log" FAKE_RELEASES="$releases" \
    GH_REPO=o/r "$script" "$@" >"$work/out" 2>"$work/err")
}

check_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: exit $actual, expected $expected"
    cat "$work/out" "$work/err"
    failures=$((failures + 1))
  fi
}

# check_deleted <name> <keys...>: exactly these engines were deleted.
check_deleted() {
  local name="$1" expected actual
  shift
  expected="$(printf 'release delete chromium-engine-%s --cleanup-tag --yes\n' "$@" | sort)"
  [[ $# -gt 0 ]] || expected=""
  actual="$(grep '^release delete' "$work/log" | sort)"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: deleted"
    echo "$actual"
    echo "expected"
    echo "$expected"
    cat "$work/out" "$work/err"
    failures=$((failures + 1))
  fi
}

check_out() {
  local name="$1" pattern="$2"
  if grep -qE -- "$pattern" "$work/out"; then
    echo "ok       $name"
  else
    echo "FAIL     $name: no line matching '$pattern'"
    cat "$work/out" "$work/err"
    failures=$((failures + 1))
  fi
}

main_new="$(commit k9)"
main_old="$(commit k2)"
pr_old="$(commit k3)"
no_key="$(commit "")"
export FAKE_MAIN="$main_new"

# The 5 newest stay; the rest go, with their tags. Drafts and app releases stay.
run
check_exit "a prune succeeds" 0 $?
check_deleted "it deletes all but the 5 newest" k1 k2 k3 k4
check_out "it reports the count" "^Kept 5 engine\(s\); deleted 4$"

# --keep changes how many stay.
run --keep 7
check_deleted "--keep 7 keeps 7" k1 k2

# Engines main or an open pull request needs stay, however old.
FAKE_MAIN="$main_old" FAKE_PRS="12 $pr_old
" run
check_deleted "main's and open pull requests' engines stay" k1 k4
check_out "it says main needs k2" "^keep +chromium-engine-k2 \(needed by main\)$"
check_out "it says #12 needs k3" "^keep +chromium-engine-k3 \(needed by #12\)$"

# A dry run deletes nothing.
FAKE_MAIN="$main_old" run --dry-run
check_deleted "a dry run deletes nothing"
check_out "a dry run says what it would delete" "^Kept 6 engine\(s\); would delete 3$"

# A key that can't be worked out doesn't stop the prune.
FAKE_PRS="13 $no_key
14 0123456789abcdef0123456789abcdef01234567
" run
check_exit "an unknown key doesn't stop the prune" 0 $?
check_deleted "the prune goes on" k1 k2 k3 k4
if grep -q "#13" "$work/err" && grep -q "#14" "$work/err"; then
  echo "ok       it warns about each key it can't work out"
else
  echo "FAIL     it warns about each key it can't work out"
  cat "$work/err"
  failures=$((failures + 1))
fi
if [[ -z "$(git -C "$repo" worktree list | sed 1d)" ]]; then
  echo "ok       it removes its worktrees"
else
  echo "FAIL     it removes its worktrees"
  git -C "$repo" worktree list
  failures=$((failures + 1))
fi

# gh failures stop it before anything is deleted.
FAKE_FAIL="release list" run
check_exit "a failed release list exits 2" 2 $?
FAKE_FAIL="pr list" run
check_exit "a failed pull request list exits 2" 2 $?
check_deleted "nothing is deleted when it can't list the pull requests"

# Bad input is refused.
run --keep 0
check_exit "a zero keep is refused" 2 $?
run --keep "5 --repo x"
check_exit "a keep with options in it is refused" 2 $?
(cd "$repo" && PATH="$work/bin:$PATH" FAKE_GH_LOG="$work/log" "$script" >/dev/null 2>&1)
check_exit "a missing GH_REPO is refused" 2 $?

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"

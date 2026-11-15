#!/bin/bash
# Tests for clean-code-sign-clones.sh. Run directly:
# ./scripts/clean-code-sign-clones.test.sh
# Works on fake clones in a temporary directory, never on Chromium's own.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
clean="$script_dir/clean-code-sign-clones.sh"

failures=0
workdir="$(mktemp -d)"
workdir="$(cd "$workdir" && pwd -P)"
holder=""
trap '[[ -n "$holder" ]] && kill "$holder" 2>/dev/null; rm -rf "$workdir"' EXIT

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

clones="$workdir/X/dev.joshuapark.Clair.code_sign_clone"

# Makes a fake clone NAME, aged an hour unless the second argument is "new".
make_clone() {
  local name="$1" age="${2-old}"
  mkdir -p "$clones/$name/Clair.app.bundle/Contents/MacOS"
  printf 'exe' >"$clones/$name/Clair.app.bundle/Contents/MacOS/Clair"
  if [[ "$age" == old ]]; then
    touch -t "$(date -v-1H +%Y%m%d%H%M.%S)" "$clones/$name"
  fi
}

output=""
status=0
run() {
  status=0
  output="$(CLAIR_CODE_SIGN_CLONE_DIR="$clones" "$clean" "$@" 2>&1)" || status=$?
}

result() {
  if "$@"; then echo pass; else echo fail; fi
}

# --- no clones -------------------------------------------------------------------------
run
check "succeeds when the clones' directory doesn't exist" "$(result test "$status" -eq 0)"

# --- stale, open, new and unrelated entries --------------------------------------------
make_clone code_sign_clone.stale1
make_clone code_sign_clone.stale2
make_clone code_sign_clone.InUse9
make_clone code_sign_clone.fresh7 new
mkdir -p "$clones/not-a-clone"
touch -t "$(date -v-1H +%Y%m%d%H%M.%S)" "$clones/not-a-clone"
# A running process with a file open in a clone, as Clair has its executable.
bash -c 'exec 3<"$1"; exec sleep 60' _ "$clones/code_sign_clone.InUse9/Clair.app.bundle/Contents/MacOS/Clair" &
holder=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  lsof -p "$holder" 2>/dev/null | grep -q InUse9 && break
  sleep 0.2
done

run
check "succeeds" "$(result test "$status" -eq 0)"
check "removes stale clones" \
  "$(result test ! -e "$clones/code_sign_clone.stale1" -a ! -e "$clones/code_sign_clone.stale2")"
check "keeps a clone a running process has open" "$(result test -d "$clones/code_sign_clone.InUse9")"
check "keeps a clone under a minute old" "$(result test -d "$clones/code_sign_clone.fresh7")"
check "keeps entries that aren't clones" "$(result test -d "$clones/not-a-clone")"
check "says how many it removed" "$(result grep -q 'removed 2 stale' <<<"$output")"

kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
holder=""
run
check "removes the clone once nothing has it open" "$(result test ! -e "$clones/code_sign_clone.InUse9")"

run
check "is quiet when there's nothing to remove" "$(result test -z "$output")"

# --- arguments -------------------------------------------------------------------------
run 'bad id/../..'
check "refuses a bundle ID that isn't one" "$(result test "$status" -ne 0)"
run dev.joshuapark.Clair extra
check "refuses extra arguments" "$(result test "$status" -ne 0)"

# --- the default directory -------------------------------------------------------------
# Without the override, it looks next to the user's temporary directory; a
# bundle ID of the test's own has no clones there, so nothing is touched.
status=0
output="$("$clean" "dev.joshuapark.Clair.clean-test.$$" 2>&1)" || status=$?
check "succeeds on the real directory for a bundle ID with no clones" "$(result test "$status" -eq 0 -a -z "$output")"

echo
if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"

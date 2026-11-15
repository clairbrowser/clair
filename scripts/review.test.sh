#!/bin/bash
# Tests for review.sh. Run directly: ./scripts/review.test.sh
#
# Builds a stand-in repository with three review sections and a stand-in engine
# workspace, then walks one review run through every state "next" can report.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
repo="$workdir/repo"
engine="$workdir/engine"
skill="$repo/.claude/skills/clair-review"
export CLAIR_ENGINE_WORKSPACE="$engine"

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

review() {
  "$repo/scripts/review.sh" "$@"
}

# expect <description> <expected output> <review.sh arguments...>
expect() {
  local description="$1" expected="$2" actual
  shift 2
  actual="$(review "$@" 2>&1)"
  if [[ "$actual" == "$expected" ]]; then
    check "$description" pass
  else
    check "$description (got: $actual)" fail
  fi
}

# shows <grep pattern> <review.sh arguments...>: a line of the output matches.
# The output is captured first, so grep stopping early cannot fail the command.
shows() {
  local pattern="$1" output
  shift
  output="$(review "$@" 2>/dev/null)"
  grep -q -- "$pattern" <<<"$output"
}

# refuses <description> <review.sh arguments...>
refuses() {
  local description="$1"
  shift
  if review "$@" >/dev/null 2>&1; then
    check "$description" fail
  else
    check "$description" pass
  fi
}

commit() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q -m "$1"
}

# report <id> <slug> <severity> [complete]
report() {
  {
    echo "# Section $1"
    echo
    echo "### S$1-01 [$3] A finding"
    echo "- Chromium: ${5-verified}"
    if [[ "${4-}" == complete ]]; then
      echo
      echo "Status: complete"
    fi
  } >"$run/$1-$2.md"
}

verified() {
  printf 'verdicts\n\nStatus: complete\n' >"$run/verify/$1.md"
}

# --- a stand-in repository --------------------------------------------------

mkdir -p "$repo/scripts" "$skill" "$repo/src" "$repo/docs" "$repo/art" \
  "$repo/openspec/changes/archive/2026-01-01-add-thing"
git -C "$repo" init -q
git -C "$repo" checkout -q -b main
cp "$script_dir/review.sh" "$repo/scripts/review.sh"
cat >"$repo/scripts/engine-key.sh" <<'EOF'
#!/bin/bash
echo 0123456789abcdef
EOF
chmod +x "$repo/scripts/engine-key.sh"
cat >"$skill/sections.txt" <<'EOF'
# id slug model
03 pilot fable
01 core fable
02 shell opus
EOF
cat >"$skill/scope.txt" <<'EOF'
01 src/core.*
03 src/pilot.c
02 src/*
02 docs/*
-  art/*
-  scripts/*
-  .claude/*
-  openspec/*
-  .gitignore
EOF
echo "build/" >"$repo/.gitignore"
printf 'one\ntwo\n' >"$repo/src/core.c"
printf 'one\n' >"$repo/src/core.h"
printf 'one\ntwo\nthree\nfour\n' >"$repo/src/pilot.c"
printf 'one\ntwo\n' >"$repo/src/view.c"
printf 'one\n' >"$repo/docs/guide.md"
printf '\x00\x01\x02' >"$repo/art/logo.bin"
echo "proposal" >"$repo/openspec/changes/archive/2026-01-01-add-thing/proposal.md"
commit "first"

mkdir -p "$engine/build/src/chrome"
printf 'MAJOR=156\nMINOR=0\nBUILD=8078\nPATCH=79\n' >"$engine/build/src/chrome/VERSION"
echo 0123456789abcdef >"$engine/build/engine_key"
echo finished >"$engine/build/compile_status"

# --- scope ------------------------------------------------------------------

expect "check passes when every file has a rule" \
  "scope: every tracked file is assigned or excluded" check
expect "the first matching rule wins" "src/core.c
src/core.h" files 01
expect "a later catch-all takes what is left" "docs/guide.md
src/view.c" files 02
refuses "files refuses an unknown section" files 09

echo "new" >"$repo/lib.c"
git -C "$repo" add lib.c
if shows "^  lib.c$" check; then
  check "check names a file no rule covers" pass
else
  check "check names a file no rule covers" fail
fi
refuses "check fails while a file is unassigned" check
expect "check reads a named commit instead of the work tree" \
  "scope: every tracked file is assigned or excluded" check HEAD
git -C "$repo" rm -q --cached lib.c
rm "$repo/lib.c"

echo "09 src/other.c" >>"$skill/scope.txt"
refuses "check refuses a rule for an unknown section" check
git -C "$repo" checkout -q -- .claude

if shows "^01  *core  *fable  *2  *3$" sizes; then
  check "sizes counts files and lines for a section" pass
else
  check "sizes counts files and lines for a section" fail
fi

# --- preflight --------------------------------------------------------------

if review preflight >/dev/null 2>&1; then
  check "preflight passes on a ready checkout" pass
else
  check "preflight passes on a ready checkout ($(review preflight 2>&1 | grep FAIL | head -n 1))" fail
fi

git -C "$repo" checkout -q -b feature
refuses "preflight fails off main" preflight
git -C "$repo" checkout -q main

echo "edit" >>"$repo/src/view.c"
refuses "preflight fails with uncommitted changes" preflight
git -C "$repo" checkout -q -- src/view.c

mkdir -p "$repo/openspec/changes/add-other"
if review preflight >/dev/null 2>&1 && shows "^note  open OpenSpec changes: add-other" preflight; then
  check "preflight notes an open change without failing" pass
else
  check "preflight notes an open change without failing" fail
fi
rm -rf "$repo/openspec/changes/add-other"

echo ffffffffffffffff >"$engine/build/engine_key"
refuses "preflight fails when the engine tree has another key" preflight
echo 0123456789abcdef >"$engine/build/engine_key"

echo compiling >"$engine/build/compile_status"
refuses "preflight fails while the engine is building" preflight
echo finished >"$engine/build/compile_status"

mv "$engine/build/src" "$engine/build/src.away"
refuses "preflight fails without an engine tree" preflight
mv "$engine/build/src.away" "$engine/build/src"

# --- one run, state by state ------------------------------------------------

expect "next asks for preflight before any run exists" "preflight" next
refuses "status needs a run" status

run="$(review init)"
if [[ "$run" == build/review/* && -f "$repo/$run/run.md" ]]; then
  check "init creates the run directory" pass
else
  check "init creates the run directory (got: $run)" fail
fi
run="$repo/$run"
expect "init is repeatable for the same commit" "${run#"$repo/"}" init
if grep -qx "chromium: 156.0.8078.79" "$run/run.md" &&
  grep -qx "engine_key: 0123456789abcdef" "$run/run.md"; then
  check "run.md records the Chromium version and engine key" pass
else
  check "run.md records the Chromium version and engine key" fail
fi
if [[ "$(cat "$run/files/01.txt")" == "src/core.c
src/core.h" ]]; then
  check "init writes each section's files" pass
else
  check "init writes each section's files" fail
fi
if [[ -z "$(git -C "$repo" status --porcelain)" ]]; then
  check "the run directory stays out of git" pass
else
  check "the run directory stays out of git" fail
fi

expect "a new run starts with the pilot" "pilot 03:fable" next
report 03 pilot High
expect "a partial pilot report runs again" "pilot 03:fable" next
review dispatched 03
review dispatched 03
expect "two attempts without a report block the run" "blocked 03" next
review retry 03
expect "retry clears the block" "pilot 03:fable" next

report 03 pilot High complete
expect "a High finding sends the pilot to verification" "verify 03" next
refuses "the pilot cannot be approved before verification" approve-pilot
verified 03
expect "a verified pilot waits for the owner" "await-pilot-approval" next
review approve-pilot
expect "after approval the sections go out, two at a time" "sections 01:fable 02:opus" next

review set max 1
expect "max limits the batch" "sections 01:fable" next
refuses "max must be a small number" set max 0
refuses "set takes only max" set cost 10

report 01 core Low complete
expect "a finished section leaves the batch" "sections 02:opus" next
review skip 02
expect "skipped sections are passed over, and Low findings need no verifier" "synthesize" next
rm "$run/02.skipped"

report 02 shell Medium complete unverified
expect "an unverified Medium finding needs a verifier" "verify 02" next
review dispatched verify-02 verify-02
expect "verification blocks after two attempts too" "blocked verify-02" next
verified 02
expect "with every report in, synthesis is next" "synthesize" next
if shows "^03 .* complete  *complete  *0/1/0/0/0" status; then
  check "status counts findings by severity" pass
else
  check "status counts findings by severity" fail
fi

printf 'final\n\nStatus: complete\n' >"$run/REPORT.md"
expect "a complete final report ends the run" "done" next

# --- drift ------------------------------------------------------------------

echo "edit" >>"$repo/src/view.c"
expect "uncommitted changes are drift" "drift tracked files have uncommitted changes" next
commit "change the shell"
if shows "^drift HEAD is " next; then
  check "a new commit is drift" pass
else
  check "a new commit is drift" fail
fi

review rebase-run >/dev/null
if [[ ! -f "$run/02-shell.md" && -f "$run/01-core.md" && ! -f "$run/REPORT.md" ]] &&
  compgen -G "$run/stale/*-02-shell.md" >/dev/null; then
  check "rebase-run sets aside only the changed section and the final report" pass
else
  check "rebase-run sets aside only the changed section and the final report" fail
fi
expect "after rebase-run the changed section runs again" "sections 02:opus" next
refuses "rebase-run refuses when nothing changed" rebase-run

# --- timings ----------------------------------------------------------------

log="job	step	2026-11-14T00:00:00Z Test Case '-[ClairRuntimeTests.SpacesTests testRename]' passed (55.176 seconds).
job	step	2026-11-14T00:01:00Z Test Case '-[ClairRuntimeTests.ProfilesTests testSwitch]' failed (40.5 seconds).
job	step	2026-11-14T00:02:00Z Test Case '-[ClairRuntimeTests.ProfilesTests testIsolation]' passed (4.5 seconds).
job	step	2026-11-14T00:03:00Z unrelated line"
timings="$(review timings <<<"$log")"
if [[ "$(sed -n 2p <<<"$timings")" == *"55.2"*"passed"*"SpacesTests"*"testRename" ]]; then
  check "timings lists tests slowest first" pass
else
  check "timings lists tests slowest first" fail
fi
if grep -q "failed  *ProfilesTests  *testSwitch" <<<"$timings" &&
  grep -q "45.0  *2  *ProfilesTests" <<<"$timings" &&
  grep -q "100.2  *3  *TOTAL" <<<"$timings"; then
  check "timings marks failures and totals each class" pass
else
  check "timings marks failures and totals each class" fail
fi
if review timings <<<"nothing here" >/dev/null 2>&1; then
  check "timings refuses a log without test results" fail
else
  check "timings refuses a log without test results" pass
fi

echo
if [[ $failures -eq 0 ]]; then
  echo "All tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi

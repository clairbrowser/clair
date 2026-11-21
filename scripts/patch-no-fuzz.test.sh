#!/bin/bash
# Tests for patch-no-fuzz.sh. Run directly: ./scripts/patch-no-fuzz.test.sh
#
# Uses a stand-in source file and stand-in patches, in a stand-in checkout
# with the script in scripts/ and the patches in patches/, as patches.py sees
# them.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0
workdir="$(mktemp -d)"
workdir="$(cd "$workdir" && pwd -P)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/repo/scripts" "$workdir/repo/patches/clair"
cp "$script_dir/patch-no-fuzz.sh" "$workdir/repo/scripts/"
strict="$workdir/repo/scripts/patch-no-fuzz.sh"
patch_file="$workdir/repo/patches/clair/test.patch"
failed_list="$workdir/failed"

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

# A hunk adding "new" after line c, with "$1", "$2" and "$3" as its context
# before the addition, written to $4 (default: $patch_file).
write_patch() {
  cat >"${4:-$patch_file}" <<PATCH
--- a/f.txt
+++ b/f.txt
@@ -1,6 +1,7 @@
 $1
 $2
 $3
+new
 d
 e
 f
PATCH
}

original_tree() {
  rm -rf "$workdir/tree"
  mkdir "$workdir/tree"
  printf 'a\nb\nc\nd\ne\nf\n' >"$workdir/tree/f.txt"
}

# Applies the patch in $1 (default: $patch_file) to the tree the way
# ungoogled-chromium's patches.py does.
apply_to_tree() {
  "$strict" -p1 --ignore-whitespace -i "${1:-$patch_file}" -d "$workdir/tree" \
    --no-backup-if-mismatch --forward >"$workdir/output" 2>&1
}

apply() {
  original_tree
  apply_to_tree "$@"
}

unchanged() {
  printf 'a\nb\nc\nd\ne\nf\n' | cmp -s - "$workdir/tree/f.txt"
}

# patches.py checks that its patch tool runs before using it.
if "$strict" --version >/dev/null 2>&1; then r=pass; else r=fail; fi
check "answers --version" "$r"

write_patch a b c
if apply && grep -qx new "$workdir/tree/f.txt"; then r=pass; else r=fail; fi
check "a patch with exact context applies" "$r"

write_patch CHANGED b c
if apply; then r=fail; else r=pass; fi
check "a changed outermost context line fails" "$r"

write_patch a CHANGED c
if apply; then r=fail; else r=pass; fi
check "a changed middle context line fails" "$r"

write_patch a b CHANGED
if apply; then r=fail; else r=pass; fi
check "a changed context line next to the edit fails" "$r"

# With CLAIR_PATCH_FAILURES, failures are recorded and the series goes on.
export CLAIR_PATCH_FAILURES="$failed_list"

if "$strict" --version >/dev/null 2>&1; then r=pass; else r=fail; fi
check "recording failures: answers --version" "$r"

rm -f "$failed_list"
write_patch a b c
if apply && grep -qx new "$workdir/tree/f.txt" && [[ ! -s "$failed_list" ]]; then
  r=pass
else
  r=fail
fi
check "recording failures: a patch that applies is applied and not recorded" "$r"

rm -f "$failed_list"
write_patch a b CHANGED
if apply && unchanged && [[ "$(cat "$failed_list")" == "clair/test.patch" ]]; then
  r=pass
else
  r=fail
fi
check "recording failures: a failing patch exits 0, is recorded by its path under patches/ and leaves the tree unchanged" "$r"

rm -f "$failed_list"
write_patch CHANGED b c
if apply && unchanged && [[ "$(cat "$failed_list")" == "clair/test.patch" ]]; then
  r=pass
else
  r=fail
fi
check "recording failures: a changed outermost context line still counts as failing" "$r"

if grep -q 'Hunk\|hunk\|FAILED\|failed' "$workdir/output"; then r=pass; else r=fail; fi
check "recording failures: patch's output is printed" "$r"

# A series of three: the first and last fail, the middle applies.
rm -f "$failed_list"
mkdir -p "$workdir/repo/patches/clair/sub"
write_patch CHANGED b c "$workdir/repo/patches/clair/first.patch"
write_patch a b c "$workdir/repo/patches/clair/second.patch"
write_patch a CHANGED c "$workdir/repo/patches/clair/sub/third.patch"
original_tree
r=pass
for name in first second sub/third; do
  apply_to_tree "$workdir/repo/patches/clair/$name.patch" || r=fail
done
if [[ "$r" == pass ]] && grep -qx new "$workdir/tree/f.txt" &&
  [[ "$(cat "$failed_list")" == "$(printf 'clair/first.patch\nclair/sub/third.patch')" ]]; then
  r=pass
else
  r=fail
fi
check "recording failures: every failing patch in a series is recorded, in order, and the others apply" "$r"

rm -f "$failed_list"
outside="$workdir/elsewhere.patch"
write_patch a b CHANGED "$outside"
if apply "$outside" && [[ "$(cat "$failed_list")" == "$outside" ]]; then r=pass; else r=fail; fi
check "recording failures: a patch outside patches/ is recorded by its full path" "$r"

unset CLAIR_PATCH_FAILURES

rm -f "$failed_list"
write_patch a b CHANGED
if apply || [[ -e "$failed_list" ]]; then r=fail; else r=pass; fi
check "without CLAIR_PATCH_FAILURES a failing patch still exits non-zero and records nothing" "$r"

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"

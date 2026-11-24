#!/bin/bash
# The patch tool for Clair's series: patch without fuzz. build.sh names it in
# PATCH_BIN, the only way to change how ungoogled-chromium's patches.py runs
# patch.
#
# By default patch ignores up to two context lines at each end of a hunk, so a
# patch can apply silently after the code around it has changed. Taking a new
# ungoogled-chromium tag must stop on that instead, and name the patch.
#
# When CLAIR_PATCH_FAILURES names a file, a patch that doesn't apply is
# recorded instead: patch's output is printed, the patch's path under engine/patches/
# is appended to that file, the tree is left unchanged and the script exits 0,
# so patches.py goes on to the next patch and one run names every failure.

set -uo pipefail

if [[ -z "${CLAIR_PATCH_FAILURES:-}" ]]; then
  exec patch --fuzz=0 "$@"
fi

# patches.py passes the patch file with -i.
patch_file=""
previous=""
for argument in "$@"; do
  if [[ "$previous" == "-i" ]]; then
    patch_file="$argument"
  fi
  previous="$argument"
done
# Without one (patches.py first checks the tool with --version), there is
# nothing to record.
if [[ -z "$patch_file" ]]; then
  exec patch --fuzz=0 "$@"
fi

if output="$(patch --fuzz=0 --dry-run "$@" 2>&1)"; then
  exec patch --fuzz=0 "$@"
fi

printf '%s\n' "$output"
patches_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/patches/"
patch_dir="$(cd "$(dirname "$patch_file")" 2>/dev/null && pwd -P)"
recorded="$patch_dir/$(basename "$patch_file")"
recorded="${recorded#"$patches_dir"}"
if ! printf '%s\n' "$recorded" >>"$CLAIR_PATCH_FAILURES"; then
  echo "patch-no-fuzz.sh: can't record the failure in $CLAIR_PATCH_FAILURES" >&2
  exit 1
fi
echo "Recorded the failure of $recorded; going on to the next patch."

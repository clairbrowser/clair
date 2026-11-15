#!/bin/bash
# Deletes the code-sign clones Chromium left behind for a bundle ID.
#
#   clean-code-sign-clones.sh [bundle-id]
#
# At start-up Chromium copies its own bundle to
# $(getconf DARWIN_USER_TEMP_DIR)../X/<bundle-id>.code_sign_clone/code_sign_clone.XXXXXX/
# (chrome/browser/mac/code_sign_clone_manager.mm), so its signature can still
# be checked if the app is replaced while it runs. It deletes that copy only
# when it quits through its own shutdown path. A SIGTERM, a crash or a kill
# leaves the copy behind, several hundred MB each time, so scripts that stop
# Clair that way run this afterwards.
#
# A clone is deleted only when no running process has a file open in it and it
# is over a minute old. The clone's main executable is a hard link to the
# app's, so every clone of a build counts as open while any copy of that build
# runs; those are deleted on a later run. The bundle ID defaults to Clair's.
#
# For tests only: CLAIR_CODE_SIGN_CLONE_DIR replaces the clones' directory.

set -euo pipefail

die() {
  echo "clean-code-sign-clones: $1" >&2
  exit 1
}

(($# <= 1)) || die "usage: clean-code-sign-clones.sh [bundle-id]"
bundle_id="${1:-dev.joshuapark.Clair}"
[[ "$bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "not a bundle ID: $bundle_id"
command -v lsof >/dev/null || die "lsof is missing, so clones in use can't be told apart"

dir="${CLAIR_CODE_SIGN_CLONE_DIR-}"
if [[ -z "$dir" ]]; then
  temp="$(getconf DARWIN_USER_TEMP_DIR)" || die "couldn't find the user's temporary directory"
  dir="${temp%/}/../X/$bundle_id.code_sign_clone"
fi
[[ -d "$dir" ]] || exit 0

# The clones a running process has a file open in. lsof matches by inode, so
# the paths it prints may not start with $dir (Chromium opens them through
# T/../X); take the clone's name from the path instead. lsof exits 1 when
# nothing is open.
open_clones="$(lsof -Fn +D "$dir" 2>/dev/null |
  sed -nE 's|^n.*/(code_sign_clone\.[A-Za-z0-9]+)(/.*)?$|\1|p' | sort -u)" || true

removed=0
while IFS= read -r -d '' clone; do
  name="$(basename "$clone")"
  [[ "$name" =~ ^code_sign_clone\.[A-Za-z0-9]+$ ]] || continue
  grep -qxF "$name" <<<"$open_clones" && continue
  rm -rf "${dir:?}/${name:?}"
  removed=$((removed + 1))
done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'code_sign_clone.*' -mmin +1 -print0)

if ((removed > 0)); then
  echo "clean-code-sign-clones: removed $removed stale code-sign clone(s) of $bundle_id" >&2
fi

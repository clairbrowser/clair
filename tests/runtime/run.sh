#!/bin/bash
# Runs the runtime suite (change 1 design D12) against a packaged Clair.
#
#   run.sh prepare <engine.zip> <engine.json> <dir> [test selection]
#   run.sh test <dir> [xcodebuild options, such as -only-testing:AppTests]
#
# prepare packages the commit's Clair (ad hoc, trusting the test-only update key)
# and builds the tests. When the test selection, the -only-testing and
# -skip-testing options test will get, runs an update test (AppTests,
# UpdateMenuTests, IdleInstallTests), it also packages a newer Clair to update
# to, as a DMG, which needs dmgbuild, and makes the test appcasts.
# test starts the local web server and runs the tests, retrying a failed test
# once. It writes the failing tests to <dir>/failures.txt, and the logs to
# <dir>/logs.
#
# The tests delete Clair's data directory, its preferences and its keychain item
# for the current user, so this refuses to run anywhere but a hosted runner
# unless CLAIR_RUNTIME_DELETE_MY_DATA=1 says that losing them is fine.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
port=8123
base_url="http://localhost:$port"
project="$root/tests/runtime/ClairRuntimeTests.xcodeproj"
public_key="$root/tests/runtime/update-key/public-ed-key.txt"

die() {
  echo "runtime suite: $1" >&2
  exit 1
}

usage() {
  sed -n '/^#   run.sh prepare/,/^#   run.sh test/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

[[ "${RUNNER_ENVIRONMENT-}" == github-hosted || "${CLAIR_RUNTIME_DELETE_MY_DATA-}" == 1 ]] ||
  die "the tests delete Clair's data and keychain item for the current user. They run on a hosted runner, or locally with CLAIR_RUNTIME_DELETE_MY_DATA=1"

# The classes that update Clair from the test appcasts.
update_classes="AppTests UpdateMenuTests IdleInstallTests"

# Whether xcodebuild's test selection options run a test of an update class:
# with -only-testing, one names the target, a class or a test of one; without,
# everything runs but what -skip-testing names.
selects_update_tests() {
  local option only=0 class selected
  for option in "$@"; do
    [[ "$option" == -only-testing:* ]] && only=1
  done
  for class in $update_classes; do
    selected=$(( 1 - only ))
    for option in "$@"; do
      case "$option" in
        -only-testing:ClairRuntimeTests | "-only-testing:ClairRuntimeTests/$class" | "-only-testing:ClairRuntimeTests/$class/"*)
          selected=1 ;;
      esac
    done
    for option in "$@"; do
      case "$option" in
        -skip-testing:ClairRuntimeTests | "-skip-testing:ClairRuntimeTests/$class") selected=0 ;;
      esac
    done
    (( selected )) && return 0
  done
  return 1
}

prepare() {
  local engine="$1" engine_json="$2" dir="$3"
  shift 3
  local with_update=0
  if selects_update_tests "$@"; then
    with_update=1
  fi
  [[ -f "$engine" ]] || die "no engine at $engine"
  [[ -f "$engine_json" ]] || die "no engine.json at $engine_json"
  mkdir -p "$dir"
  dir="$(cd "$dir" && pwd -P)"

  local version build update_version update_build
  version="$(cat "$root/version.txt")"
  build="$(git -C "$root" rev-list --count HEAD)"
  update_version="$(awk -F . '{ printf "%d.%d.%d", $1, $2, $3 + 1 }' <<<"$version")"
  update_build=$((build + 1))

  local sparkle="$root/build/sparkle"
  "$root/scripts/fetch-sparkle.sh" "$sparkle" >/dev/null
  echo "==> Building ClairUI"
  xcodebuild -project "$root/native/ClairUI.xcodeproj" -scheme ClairUI \
    -configuration Release -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$dir/ClairUI-DerivedData" CODE_SIGNING_ALLOWED=NO -quiet build
  local clairui="$dir/ClairUI-DerivedData/Build/Products/Release/ClairUI.framework"

  package() {
    "$root/package.sh" --clairui "$clairui" --sparkle "$sparkle" --public-key "$public_key" "$@"
  }
  echo "==> Packaging $version ($build)"
  rm -rf "$dir/Clair.app" "$dir/www"
  package --version "$version" --build "$build" --no-dmg "$engine" "$dir/current"
  mv "$dir/current/Clair.app" "$dir/Clair.app"

  local www="$dir/www"
  mkdir -p "$www"
  cp -R "$root/tests/runtime/pages" "$www/pages"
  # The test extensions, which the suite loads with --load-extension.
  rm -rf "$dir/extensions"
  cp -R "$root/tests/runtime/extensions" "$dir/extensions"
  # The extension the install dialog offers, packed with a new key each time.
  python3 -I "$root/tests/runtime/make-crx.py" "$root/tests/runtime/extensions/install-prompt" \
    "$www/install-prompt.crx"

  if (( with_update )); then
    echo "==> Packaging the update, $update_version ($update_build), and the test appcasts"
    package --version "$update_version" --build "$update_build" "$engine" "$dir/update"
    local dmg="Clair-$update_version-arm64.dmg"
    mkdir -p "$www/update" "$www/up-to-date"
    cp "$dir/update/$dmg" "$www/update/$dmg"
    cp "$dir/update/$dmg" "$www/up-to-date/$dmg"
    "$root/scripts/make-test-appcast.sh" --sparkle "$sparkle" --appcast "$www/update/appcast.xml" \
      --dmg "$www/update/$dmg" --version "$update_version" --build "$update_build" \
      --base-url "$base_url/update"
    # The same build as the running one, which Sparkle doesn't offer.
    "$root/scripts/make-test-appcast.sh" --sparkle "$sparkle" --appcast "$www/up-to-date/appcast.xml" \
      --dmg "$www/up-to-date/$dmg" --version "$version" --build "$build" \
      --base-url "$base_url/up-to-date"
    rm -rf "$dir/update"
  else
    echo "==> No update test selected: skipping the update and its appcasts"
  fi

  jq -n --arg version "$version" --arg build "$build" \
    --arg updateVersion "$update_version" --arg updateBuild "$update_build" \
    --arg baseURL "$base_url" --slurpfile engine "$engine_json" \
    '{version: $version, build: $build, updateVersion: $updateVersion,
      updateBuild: $updateBuild, baseURL: $baseURL,
      chromiumVersion: $engine[0].chromium,
      ungoogledVersion: $engine[0].ungoogled_chromium}' >"$dir/config.json"
  cat "$dir/config.json"

  echo "==> Building the tests"
  xcodebuild -project "$project" -scheme ClairRuntimeTests \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$dir/DerivedData" \
    -quiet build-for-testing
}

run_tests() {
  local dir="$1"
  shift
  dir="$(cd "$dir" && pwd -P)"
  [[ -d "$dir/Clair.app" ]] || die "$dir has no Clair.app; run prepare first"
  if selects_update_tests "$@" && [[ ! -d "$dir/www/update" ]]; then
    die "these tests include update tests, but prepare packaged no update; run prepare with the same tests"
  fi
  mkdir -p "$dir/logs"
  : >"$dir/failures.txt"

  python3 -I "$root/tests/runtime/server.py" "$dir/www" "$port" >"$dir/logs/server.log" 2>&1 &
  local server=$!
  # shellcheck disable=SC2064 # The PID is known now.
  trap "kill $server 2>/dev/null || true" EXIT

  # XCUITest can't drive the UI without this, and asks for a password otherwise.
  sudo automationmodetool enable-automationmode-without-authentication

  local status=0
  # xcodebuild passes on TEST_RUNNER_FOO to the tests as FOO.
  TEST_RUNNER_CLAIR_RUNTIME_DIR="$dir" xcodebuild test-without-building \
    -project "$project" -scheme ClairRuntimeTests \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$dir/DerivedData" \
    -resultBundlePath "$dir/results.xcresult" \
    -retry-tests-on-failure -test-iterations 2 \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
    "$@" || status=$?

  log show --last 2h --style compact --info \
    --predicate 'subsystem == "com.clairbrowser.clair" OR subsystem == "org.sparkle-project.Sparkle"' \
    >"$dir/logs/updates.log" 2>/dev/null || true

  if (( status != 0 )); then
    xcrun xcresulttool get test-results tests --path "$dir/results.xcresult" --format json 2>/dev/null |
      jq -r '.. | objects | select(.nodeType? == "Test Case" and .result? == "Failed") | .nodeIdentifier // .name' |
      sort -u >"$dir/failures.txt" || true
    echo "==> Failing tests:"
    cat "$dir/failures.txt"
  fi
  return "$status"
}

case "${1-}" in
  prepare)
    shift
    (( $# >= 3 )) || usage
    prepare "$@"
    ;;
  test)
    shift
    (( $# >= 1 )) || usage
    run_tests "$@"
    ;;
  *) usage ;;
esac

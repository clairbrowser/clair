#!/bin/bash
# Tests for tidy-notes.sh. Run directly: ./scripts/tidy-notes.test.sh

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tidy="$script_dir/tidy-notes.sh"

failures=0

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

# expect DESCRIPTION INPUT EXPECTED: tidy-notes.sh turns INPUT into EXPECTED,
# byte for byte (both given as printf formats).
expect() {
  local description="$1" input="$2" expected="$3" actual
  actual="$(printf -- "$input" | "$tidy" | od -c)"
  if [[ "$actual" == "$(printf -- "$expected" | od -c)" ]]; then
    check "$description" pass
  else
    check "$description" fail
    printf -- "$input" | "$tidy" | sed 's/^/         | /'
  fi
}

# What `changie batch` writes with Clair's configuration.
expect "joins the kind groups into one list" \
  '## 0.3.0 - 2026-01-01\n\n\n- New: A\n- New: B\n\n- Changed: C\n\n- Fixed: D\n\n- Updated: E\n' \
  '## 0.3.0 - 2026-01-01\n\n- New: A\n- New: B\n- Changed: C\n- Fixed: D\n- Updated: E\n'

expect "leaves a single kind as it is, with one blank line under the heading" \
  '## 0.3.0 - 2026-01-01\n\n\n- Fixed: A\n' \
  '## 0.3.0 - 2026-01-01\n\n- Fixed: A\n'

expect "keeps the header text apart from the list" \
  '## 0.3.0 - 2026-01-01\n\n**Note**: Read this.\n\n\n- New: A\n\n- Fixed: B\n' \
  '## 0.3.0 - 2026-01-01\n\n**Note**: Read this.\n\n- New: A\n- Fixed: B\n'

expect "keeps a list in the header text apart from the changes" \
  '## 0.3.0 - 2026-01-01\n\n**Note**:\n\n- one thing\n\n\n- New: A\n' \
  '## 0.3.0 - 2026-01-01\n\n**Note**:\n\n- one thing\n\n- New: A\n'

expect "keeps a trailing blank line" \
  '- New: A\n\n- Fixed: B\n\n' \
  '- New: A\n- Fixed: B\n\n'

if "$tidy" extra </dev/null >/dev/null 2>&1; then
  check "refuses arguments" fail
else
  check "refuses arguments" pass
fi

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"

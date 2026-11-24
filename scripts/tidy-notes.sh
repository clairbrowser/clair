#!/bin/bash
# Tidies a release's notes as `changie batch` writes them, from stdin to stdout.
#
#   changie batch 0.3.0 --dry-run | tidy-notes.sh
#
# .changie.yaml has a kindFormat that prints nothing, because Changie groups the
# lines by kind only when kindFormat is set. Changie still writes a line break
# before each kind's (empty) heading, which leaves a blank line between the
# groups and an extra one under the version heading. A blank line between items
# would make GitHub and the appcast render a loose list, with every item spaced
# like a paragraph, so this drops it and collapses other runs of blank lines.

set -euo pipefail

if (( $# > 0 )); then
  echo "usage: tidy-notes.sh <notes.md >tidy.md" >&2
  exit 2
fi

awk '
  { line[NR] = $0 }
  END {
    change = "^- [A-Za-z]+: "
    n = 0
    for (i = 1; i <= NR; i++) {
      if (line[i] == "") {
        # A run of blank lines becomes one.
        if (n > 0 && out[n] == "") continue
        # None at all between two change lines.
        j = i + 1
        while (j <= NR && line[j] == "") j++
        if (n > 0 && out[n] ~ change && j <= NR && line[j] ~ change) continue
      }
      out[++n] = line[i]
    }
    for (i = 1; i <= n; i++) print out[i]
  }
'

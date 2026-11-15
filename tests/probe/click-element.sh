#!/bin/bash
# Clicks an element the probe's accessibility tree names, at its centre, so a
# script needn't know where a window opened (tests/probe/README.md).
#
#   click-element.sh <match> [left|right] [n]
#
# <match> is an identifier (clair.profilesAdd) or a title or label
# ('Profiles'), matched exactly; the first element in the tree with a size
# wins, or the nth with [n], such as a list's second row's button. "right"
# right-clicks. The probe must be running.
set -euo pipefail

match=${1:?usage: click-element.sh <identifier|title|label> [left|right] [n]}
kind=${2:-}
nth=${3:-1}
case $nth in
  '' | *[!0-9]* | 0)
    echo "click-element.sh: n must be a positive number, not $nth" >&2
    exit 1
    ;;
esac
probe=$(dirname "$0")/probe.sh

tree=$("$probe" send tree)
# The main window's origin: coordinates are relative to it.
origin=$(printf '%s\n' "$tree" | grep -m1 -E "^ *Window" | sed -E 's/.*\{\{([0-9.-]+), ([0-9.-]+)\}.*/\1 \2/')
line=$(printf '%s\n' "$tree" | grep -F -e "identifier: '$match'" -e "title: '$match'" -e "label: '$match'" |
  grep -v "{0.0, 0.0}}" | sed -n "${nth}p" || true)
if [ -z "$line" ]; then
  echo "click-element.sh: nothing in the tree matches $match (match $nth)" >&2
  exit 1
fi
read -r x y w h <<<"$(printf '%s\n' "$line" | sed -E 's/.*\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.]+), ([0-9.]+)\}\}.*/\1 \2 \3 \4/')"
read -r ox oy <<<"$origin"
cx=$(awk -v a="$x" -v b="$w" -v o="$ox" 'BEGIN { printf "%d", a + b / 2 - o }')
cy=$(awk -v a="$y" -v b="$h" -v o="$oy" 'BEGIN { printf "%d", a + b / 2 - o }')
if [ "$kind" = right ]; then
  "$probe" send "rclick $cx $cy" >/dev/null
else
  "$probe" send "click $cx $cy" >/dev/null
fi

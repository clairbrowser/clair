#!/bin/bash
# Tests for the engine's sort keys (add-tab-folders design D1, D12), in
# engine/overlay/chrome/browser/clair/clair_order_key.mm. Run directly:
# ./scripts/order-key.test.sh
#
# The keys are plain C++, so this compiles them with the system's clang
# rather than in a Chromium build, and places thousands of keys at the ends,
# into one gap and at random, checking each sorts between its neighbours.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
overlay="$script_dir/../engine/overlay"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cat >"$workdir/test.cc" <<'EOF'
#include <algorithm>
#include <cstdio>
#include <random>
#include <string>
#include <vector>

#include "chrome/browser/clair/clair_order_key.h"

using clair::IsValidOrderKey;
using clair::OrderKeyBetween;

static int failures = 0;

static void check(const char* description, bool passed) {
  std::printf("%s %s\n", passed ? "ok      " : "FAIL    ", description);
  if (!passed) {
    ++failures;
  }
}

// Places `count` keys, each at the index `where` picks from the list's size,
// and checks every key is valid and sorts between its neighbours. Returns the
// longest key.
template <typename Where>
static size_t Place(const char* description, int count, Where where) {
  std::vector<std::string> keys;
  size_t longest = 0;
  bool ordered = true;
  for (int i = 0; i < count && ordered; ++i) {
    size_t at = where(keys.size());
    std::string before = at > 0 ? keys[at - 1] : "";
    std::string after = at < keys.size() ? keys[at] : "";
    std::string key = OrderKeyBetween(before, after);
    ordered = IsValidOrderKey(key) && (before.empty() || before < key) && (after.empty() || key < after);
    if (!ordered) {
      std::printf("         between \"%s\" and \"%s\": \"%s\"\n", before.c_str(), after.c_str(), key.c_str());
    }
    longest = std::max(longest, key.size());
    keys.insert(keys.begin() + at, key);
  }
  check(description, ordered);
  return longest;
}

int main() {
  check("the first key is a0", OrderKeyBetween("", "") == "a0");
  check("after a0 is a1", OrderKeyBetween("a0", "") == "a1");
  check("before a0 is Zz", OrderKeyBetween("", "a0") == "Zz");
  check("between a0 and a1 is a0V", OrderKeyBetween("a0", "a1") == "a0V");
  check("an invalid neighbour gives no key", OrderKeyBetween("a0", "not a key").empty());
  check("a trailing zero isn't a key", !IsValidOrderKey("a00") && OrderKeyBetween("a00", "").empty());
  check("neighbours out of order give no key", OrderKeyBetween("a1", "a0").empty());
  check("equal neighbours give no key", OrderKeyBetween("a1", "a1").empty());

  size_t end = Place("2,000 keys, each after the last", 2000, [](size_t size) { return size; });
  check("keys at the end stay short", end <= 4);
  size_t start = Place("2,000 keys, each before the first", 2000, [](size_t) { return size_t{0}; });
  check("keys at the start stay short", start <= 4);
  Place("2,000 keys into the gap after the first", 2000, [](size_t size) { return size < 1 ? size : size_t{1}; });
  Place("2,000 keys into the gap before the last", 2000, [](size_t size) { return size < 1 ? size : size - 1; });
  std::mt19937 random(20261125);
  Place("20,000 keys at random places", 20000, [&](size_t size) {
    return std::uniform_int_distribution<size_t>(0, size)(random);
  });

  if (failures > 0) {
    std::printf("%d failed\n", failures);
    return 1;
  }
  std::printf("All passed\n");
  return 0;
}
EOF

if ! clang++ -std=c++20 -O1 -I "$overlay" -x c++ "$overlay/chrome/browser/clair/clair_order_key.mm" \
  -x c++ "$workdir/test.cc" -o "$workdir/test"; then
  echo "FAIL     the sort keys don't compile"
  exit 1
fi
"$workdir/test"

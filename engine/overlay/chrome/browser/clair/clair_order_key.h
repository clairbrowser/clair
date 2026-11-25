// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_ORDER_KEY_H_
#define CHROME_BROWSER_CLAIR_CLAIR_ORDER_KEY_H_

#include <string>
#include <string_view>

namespace clair {

// add-tab-folders design D1, D12: the sort keys that order Spaces, pinned
// tabs, folders and favorites. A key is a fractional index: a string of
// base-62 digits that sorts, byte by byte, between its neighbours, so an item
// can always get a key between any two others and a move rewrites only the
// item that moved. It follows the common fractional-indexing scheme: an
// integer part, whose first character gives its length ("a0", "a1", … "az",
// "b00", …, and "Zz", "Zy", … below "a0"), then an optional fraction without
// trailing zeros. The first key is "a0".

// Whether `key` is a key this scheme makes.
bool IsValidOrderKey(std::string_view key);

// A key sorting after `before` and before `after`. An empty `before` means
// there is nothing before, so the key goes before `after`; an empty `after`
// means there is nothing after. Returns an empty string when a non-empty
// neighbour isn't a valid key, when `before` doesn't sort before `after`, or
// when the scheme has no key left at that end.
std::string OrderKeyBetween(std::string_view before, std::string_view after);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_ORDER_KEY_H_

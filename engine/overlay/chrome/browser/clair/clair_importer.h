// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_IMPORTER_H_
#define CHROME_BROWSER_CLAIR_CLAIR_IMPORTER_H_

#include <string>

#include "base/functional/callback.h"

namespace clair {

// add-browser-import design D8: writes an import plan that ClairUI read from
// another browser. `plan` is the plan's JSON, version 1 (design D3). It
// creates the plan's new profiles and Spaces, writes its pins, folders,
// splits, favorites and Today tabs through Clair's stores, its bookmarks,
// history and favicons through Chromium's services, and installs its
// extensions from the Chrome Web Store, skipping what the destination already
// has. `progress` gets the fraction done and the phase; `done` runs once, at
// the end, with the summary's JSON. One import runs at a time: a plan sent
// while one runs, or one that doesn't parse, is done at once with a summary
// saying so. When it ends, the plan's private folder is removed (D10).
void ApplyImportPlan(
    const std::string& plan,
    base::RepeatingCallback<void(double, const std::string&)> progress,
    base::OnceCallback<void(const std::string&)> done);

// D10: removes the private folders imports left in the temporary directory,
// as after a crash. Called once at launch.
void RemoveLeftoverImportFolders();

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_IMPORTER_H_

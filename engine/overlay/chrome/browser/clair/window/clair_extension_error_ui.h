// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSION_ERROR_UI_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSION_ERROR_UI_H_

#include "chrome/browser/extensions/extension_error_ui.h"

namespace clair {

// Chromium's alert for blocklisted extensions, such as those the store flags
// as malware, as a Clair dialog on the profile's frontmost native window
// (disable-flagged-store-extensions design D6). With no window open, it waits
// for the profile's next one. Returns nullptr while ClairUI isn't running, so
// a bare engine shows Chromium's alert.
extensions::ExtensionErrorUI* CreateExtensionErrorUI(
    extensions::ExtensionErrorUI::Delegate* delegate);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSION_ERROR_UI_H_

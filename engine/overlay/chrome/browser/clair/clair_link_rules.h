// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_LINK_RULES_H_
#define CHROME_BROWSER_CLAIR_CLAIR_LINK_RULES_H_

#include "chrome/browser/ui/startup/startup_tab.h"

namespace clair {

// app_controller_mac.mm's -openStartupTabsReplacingNTP: hook (add-link-rules
// design D2), once start-up has completed: the links macOS handed Clair from
// outside it, through Launch Services or Handoff. Each http or https link
// that a link rule matches opens in a new foreground tab of the first
// matching rule's Space, and leaves `tabs`. The rest stay, in their order,
// for Chromium to open as it would.
void RouteLinksFromOtherApps(StartupTabs& tabs);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_LINK_RULES_H_

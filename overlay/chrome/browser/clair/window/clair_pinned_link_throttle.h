// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PINNED_LINK_THROTTLE_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PINNED_LINK_THROTTLE_H_

#include "content/public/browser/navigation_throttle.h"

namespace content {
class NavigationThrottleRegistry;
}  // namespace content

namespace clair {

// add-pinned-tabs-and-favorites design D7: a link to another site clicked in a
// pinned tab's or favorite's page opens in a Peek of that tab instead of
// navigating it, while the window's preference is on. It is added to every
// navigation by patches/clair/pinned-link-peek.patch, and does nothing outside
// a native window's bound tabs.
class ClairPinnedLinkThrottle : public content::NavigationThrottle {
 public:
  // chrome_content_browser_client_navigation_throttles.cc: adds the throttle
  // to a primary main frame navigation.
  static void MaybeCreateAndAdd(content::NavigationThrottleRegistry& registry);

  explicit ClairPinnedLinkThrottle(content::NavigationThrottleRegistry& registry);
  ClairPinnedLinkThrottle(const ClairPinnedLinkThrottle&) = delete;
  ClairPinnedLinkThrottle& operator=(const ClairPinnedLinkThrottle&) = delete;
  ~ClairPinnedLinkThrottle() override;

  // content::NavigationThrottle:
  ThrottleCheckResult WillStartRequest() override;
  const char* GetNameForLogging() override;
};

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_PINNED_LINK_THROTTLE_H_

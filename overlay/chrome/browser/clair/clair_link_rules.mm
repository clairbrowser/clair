// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_link_rules.h"

#include <utility>

#include "chrome/browser/clair/clair_link_rule_store.h"
#include "chrome/browser/clair/clair_native_layer.h"
#include "chrome/browser/clair/window/clair_window_group.h"
#include "chrome/browser/lifetime/browser_shutdown.h"

namespace clair {

void RouteLinksFromOtherApps(StartupTabs& tabs) {
  // Rules need Clair's windows and Spaces, and nothing opens while quitting.
  if (tabs.empty() || !IsNativeLayerRunning() ||
      browser_shutdown::IsTryingToQuit() ||
      browser_shutdown::HasShutdownStarted()) {
    return;
  }
  const ClairLinkRuleStore* store = ClairLinkRuleStore::Get();
  if (store->rules().empty()) {
    return;
  }
  StartupTabs rest;
  for (StartupTab& tab : tabs) {
    const LinkRule* rule = store->FirstMatch(tab.url);
    if (!rule) {
      rest.push_back(std::move(tab));
      continue;
    }
    // D2: in the most recently active regular window, switched to the
    // rule's Space, or in a new window showing it (add-spaces D7,
    // add-profiles D8).
    ClairWindowGroup::OpenInSpace(rule->space, tab.url);
  }
  tabs = std::move(rest);
}

}  // namespace clair

// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_pinned_link_throttle.h"

#include <memory>
#include <optional>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#import "chrome/browser/clair/ClairHost.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/referrer.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace clair {

namespace {

// The window whose bound tab `contents` is, when its preference opens Peeks
// for links to other sites; null otherwise.
ClairBrowserWindow* PeekingWindowFor(content::WebContents* contents) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(contents);
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  if (!lists || !lists->is_regular() || !tab || lists->PinOf(tab).empty() ||
      !window->peeks()) {
    return nullptr;
  }
  id<ClairWindow> clair_window = window->clair_window();
  return clair_window && clair_window.opensPeekForOtherSites ? window : nullptr;
}

// Opens the link in a Peek of `source`, once the cancelled navigation is
// done with.
void OpenPeek(base::WeakPtr<content::WebContents> source,
              content::OpenURLParams params) {
  ClairBrowserWindow* window =
      source ? PeekingWindowFor(source.get()) : nullptr;
  if (!window) {
    return;
  }
  base::OnceCallback<void(content::NavigationHandle&)> no_callback;
  window->peeks()->OpenURL(source.get(), params, no_callback);
}

}  // namespace

// static
void ClairPinnedLinkThrottle::MaybeCreateAndAdd(
    content::NavigationThrottleRegistry& registry) {
  content::NavigationHandle& handle = registry.GetNavigationHandle();
  if (!handle.IsInPrimaryMainFrame() ||
      !PeekingWindowFor(handle.GetWebContents())) {
    return;
  }
  registry.AddThrottle(std::make_unique<ClairPinnedLinkThrottle>(registry));
}

ClairPinnedLinkThrottle::ClairPinnedLinkThrottle(
    content::NavigationThrottleRegistry& registry)
    : content::NavigationThrottle(registry) {}

ClairPinnedLinkThrottle::~ClairPinnedLinkThrottle() = default;

content::NavigationThrottle::ThrottleCheckResult
ClairPinnedLinkThrottle::WillStartRequest() {
  content::NavigationHandle* handle = navigation_handle();
  content::WebContents* contents = handle->GetWebContents();
  // D7: a link the user clicked in the page, and nothing else: no redirect,
  // form, script without a gesture, reload or history navigation.
  if (!handle->IsInPrimaryMainFrame() || !handle->IsRendererInitiated() ||
      !handle->HasUserGesture() || handle->IsSameDocument() ||
      handle->IsHistory() || handle->IsPost() ||
      handle->GetReloadType() != content::ReloadType::NONE ||
      !ui::PageTransitionCoreTypeIs(handle->GetPageTransition(),
                                    ui::PAGE_TRANSITION_LINK)) {
    return PROCEED;
  }
  const GURL& url = handle->GetURL();
  if (!url.SchemeIsHTTPOrHTTPS() ||
      !IsOtherSite(url, contents->GetLastCommittedURL()) ||
      !PeekingWindowFor(contents)) {
    return PROCEED;
  }
  content::OpenURLParams params(url, content::Referrer(handle->GetReferrer()),
                                WindowOpenDisposition::NEW_FOREGROUND_TAB,
                                ui::PAGE_TRANSITION_LINK,
                                /*is_renderer_initiated=*/true);
  params.user_gesture = true;
  params.initiator_origin = handle->GetInitiatorOrigin();
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&OpenPeek, contents->GetWeakPtr(), std::move(params)));
  return CANCEL_AND_IGNORE;
}

const char* ClairPinnedLinkThrottle::GetNameForLogging() {
  return "ClairPinnedLinkThrottle";
}

}  // namespace clair

// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_bookmark_bar_drain.h"

#include <iterator>
#include <memory>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/bookmarks/bookmark_model_factory.h"
#include "chrome/browser/browser_process.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "components/bookmarks/browser/bookmark_node.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

using bookmarks::BookmarkModel;
using bookmarks::BookmarkNode;

namespace {

const char kUserDataKey[] = "ClairBookmarkBarDrain";

bool NoticeShown() {
  PrefService* local_state = g_browser_process->local_state();
  return !local_state ||
         local_state->GetBoolean(ClairBookmarkBarDrain::kNoticeShownPref);
}

}  // namespace

// static
void ClairBookmarkBarDrain::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterBooleanPref(kNoticeShownPref, false);
}

// static
void ClairBookmarkBarDrain::WindowOpened(ClairBrowserWindow* window) {
  Profile* profile = window->browser()->GetProfile();
  Profile* original = profile->GetOriginalProfile();
  if (original->IsGuestSession()) {
    return;
  }
  auto* drain =
      static_cast<ClairBookmarkBarDrain*>(original->GetUserData(kUserDataKey));
  if (!drain) {
    BookmarkModel* model = BookmarkModelFactory::GetForBrowserContext(original);
    if (!model) {
      return;
    }
    auto owned = std::make_unique<ClairBookmarkBarDrain>(original, model);
    drain = owned.get();
    original->SetUserData(kUserDataKey, std::move(owned));
  }
  if (drain->notice_pending_ && !profile->IsOffTheRecord()) {
    // Once the window is listed among the profile's windows.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&ClairBookmarkBarDrain::ShowNotice,
                                  drain->weak_factory_.GetWeakPtr()));
  }
}

ClairBookmarkBarDrain::ClairBookmarkBarDrain(Profile* profile,
                                             BookmarkModel* model)
    : profile_(profile), model_(model) {
  observation_.Observe(model_);
  if (model_->loaded()) {
    PostDrain();
  }
}

ClairBookmarkBarDrain::~ClairBookmarkBarDrain() = default;

void ClairBookmarkBarDrain::BookmarkModelLoaded(bool ids_reassigned) {
  PostDrain();
}

void ClairBookmarkBarDrain::BookmarkModelBeingDeleted() {
  observation_.Reset();
  model_ = nullptr;
}

void ClairBookmarkBarDrain::BookmarkNodeAdded(const BookmarkNode* parent,
                                              size_t index,
                                              bool added_by_user) {
  if (IsBar(parent)) {
    PostDrain();
  }
}

void ClairBookmarkBarDrain::BookmarkNodeMoved(const BookmarkNode* old_parent,
                                              size_t old_index,
                                              const BookmarkNode* new_parent,
                                              size_t new_index) {
  if (IsBar(new_parent)) {
    PostDrain();
  }
}

void ClairBookmarkBarDrain::ExtensiveBookmarkChangesEnded() {
  PostDrain();
}

bool ClairBookmarkBarDrain::IsBar(const BookmarkNode* node) const {
  return model_ && node &&
         (node == model_->bookmark_bar_node() ||
          node == model_->account_bookmark_bar_node());
}

void ClairBookmarkBarDrain::PostDrain() {
  if (drain_posted_) {
    return;
  }
  drain_posted_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&ClairBookmarkBarDrain::Drain,
                                weak_factory_.GetWeakPtr()));
}

void ClairBookmarkBarDrain::Drain() {
  drain_posted_ = false;
  // An import's extensive changes end with ExtensiveBookmarkChangesEnded(),
  // which drains once for all of it.
  if (!model_ || !model_->loaded() || model_->IsDoingExtensiveChanges()) {
    return;
  }
  size_t moved = 0;
  const BookmarkNode* bars[] = {model_->bookmark_bar_node(),
                                model_->account_bookmark_bar_node()};
  const BookmarkNode* others[] = {model_->other_node(),
                                  model_->account_other_node()};
  for (size_t i = 0; i < std::size(bars); ++i) {
    const BookmarkNode* bar = bars[i];
    const BookmarkNode* other = others[i] ? others[i] : model_->other_node();
    if (!bar || !other) {
      continue;
    }
    // The bar's children go to the top of Other Bookmarks, in their order.
    for (size_t index = 0; !bar->children().empty(); ++index, ++moved) {
      model_->Move(bar->children().front().get(), other, index);
    }
  }
  if (moved && !NoticeShown()) {
    ShowNotice();
  }
}

void ClairBookmarkBarDrain::ShowNotice() {
  if (NoticeShown()) {
    notice_pending_ = false;
    return;
  }
  ClairBrowserWindow* window = nullptr;
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&](BrowserWindowInterface* browser) {
        if (browser->GetProfile() == profile_ &&
            browser->GetType() == BrowserWindowInterface::TYPE_NORMAL) {
          ClairBrowserWindow* candidate =
              ClairBrowserWindow::FromBrowser(browser);
          if (candidate && candidate->clair_window()) {
            window = candidate;
            return false;
          }
        }
        return true;
      });
  if (!window) {
    notice_pending_ = true;
    return;
  }
  notice_pending_ = false;
  g_browser_process->local_state()->SetBoolean(kNoticeShownPref, true);
  [window->clair_window() showBookmarksBarNotice];
}

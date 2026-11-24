// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_BOOKMARK_BAR_DRAIN_H_
#define CHROME_BROWSER_CLAIR_CLAIR_BOOKMARK_BAR_DRAIN_H_

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/supports_user_data.h"
#include "components/bookmarks/browser/base_bookmark_model_observer.h"
#include "components/bookmarks/browser/bookmark_model.h"

class ClairBrowserWindow;
class PrefRegistrySimple;
class Profile;

// Keeps a profile's Bookmarks Bar empty (add-bookmarks-menu design D6): Clair
// has one bookmark list, Other Bookmarks, so whatever is in the bar when the
// bookmarks load, and whatever lands there later from an import, Manage
// Bookmarks or an extension, moves to the top of Other Bookmarks, in its
// order. Folders move whole. The account-storage bar, which only sync fills,
// is drained into the account's Other Bookmarks the same way.
//
// The first drain that moves anything, in any profile, asks the profile's most
// recently active normal window to show the Bookmarks Bar notice, or the first
// one to open when it has none. A Local State pref keeps it to once for the
// whole app. Incognito and guest windows never show it.
//
// One per original profile that isn't a guest profile, owned by the profile,
// started when a native window of it, or of its incognito profile, opens.
class ClairBookmarkBarDrain : public base::SupportsUserData::Data,
                              public bookmarks::BaseBookmarkModelObserver {
 public:
  // The Local State pref that records that the notice has shown.
  static constexpr char kNoticeShownPref[] = "clair.bookmarks_bar_notice_shown";

  static void RegisterPrefs(PrefRegistrySimple* registry);

  // A native window opened: starts the drain for its original profile, and
  // shows the notice in it if a drain is waiting for a window to show it.
  static void WindowOpened(ClairBrowserWindow* window);

  ClairBookmarkBarDrain(Profile* profile, bookmarks::BookmarkModel* model);
  ClairBookmarkBarDrain(const ClairBookmarkBarDrain&) = delete;
  ClairBookmarkBarDrain& operator=(const ClairBookmarkBarDrain&) = delete;
  ~ClairBookmarkBarDrain() override;

  // bookmarks::BaseBookmarkModelObserver:
  void BookmarkModelChanged() override {}
  void BookmarkModelLoaded(bool ids_reassigned) override;
  void BookmarkModelBeingDeleted() override;
  void BookmarkNodeAdded(const bookmarks::BookmarkNode* parent,
                         size_t index,
                         bool added_by_user) override;
  void BookmarkNodeMoved(const bookmarks::BookmarkNode* old_parent,
                         size_t old_index,
                         const bookmarks::BookmarkNode* new_parent,
                         size_t new_index) override;
  void ExtensiveBookmarkChangesEnded() override;

 private:
  bool IsBar(const bookmarks::BookmarkNode* node) const;
  // Drains in a task of its own, never inside an observer call.
  void PostDrain();
  void Drain();
  // Shows the notice in the profile's most recently active normal native
  // window, unless it has shown already. Without such a window, waits for
  // WindowOpened().
  void ShowNotice();

  const raw_ptr<Profile> profile_;
  raw_ptr<bookmarks::BookmarkModel> model_;
  base::ScopedObservation<bookmarks::BookmarkModel,
                          bookmarks::BookmarkModelObserver>
      observation_{this};
  bool drain_posted_ = false;
  // A drain moved something, and no window could show the notice yet.
  bool notice_pending_ = false;
  base::WeakPtrFactory<ClairBookmarkBarDrain> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_CLAIR_BOOKMARK_BAR_DRAIN_H_

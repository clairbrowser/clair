// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BOOKMARKS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BOOKMARKS_H_

#import <AppKit/AppKit.h>

#import "chrome/browser/clair/ClairHost.h"

class Browser;
class ClairBrowserWindow;

// The bookmarks the native window offers (add-bookmarks-menu design D2 to D4):
// one list, Chromium's Other Bookmarks, in the profile's BookmarkModel, which
// an incognito or guest window shares with its original profile.
namespace clair {

// D2: whether the active tab's page is bookmarked by the user, which titles
// Bookmarks > Bookmark This Page… "Edit Bookmark…".
bool IsActivePageBookmarked(Browser* browser);

// D4: IDC_BOOKMARK_THIS_TAB in a native window. Adds the active tab's page to
// the end of Other Bookmarks under its title, unless the user has bookmarked
// it already, then shows the bookmark dialog for the new bookmark or for the
// page's most recently added one.
void BookmarkActivePage(ClairBrowserWindow* window);

// D3: -[ClairBrowser bookmarkFolders], -updateBookmark:title:folder:,
// -removeBookmark: and -addBookmarkFolder:.
NSArray<id<ClairBookmarkFolder>>* BookmarkFolders(Browser* browser);
void UpdateBookmark(Browser* browser,
                    ClairBookmarkID bookmark_id,
                    NSString* title,
                    ClairBookmarkFolderID folder_id);
void RemoveBookmark(Browser* browser, ClairBookmarkID bookmark_id);
ClairBookmarkFolderID AddBookmarkFolder(Browser* browser, NSString* title);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BOOKMARKS_H_

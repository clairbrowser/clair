// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/window/clair_bookmarks.h"

#include <string>

#include "base/location.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/bookmarks/bookmark_model_factory.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/favicon/favicon_utils.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/bookmarks/bookmark_utils.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/bookmarks/browser/bookmark_client.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/bookmarks/browser/bookmark_node.h"
#include "components/bookmarks/browser/bookmark_utils.h"
#include "components/bookmarks/common/bookmark_metrics.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "url/gurl.h"

using bookmarks::BookmarkModel;
using bookmarks::BookmarkNode;

@interface ClairChromiumBookmark : NSObject <ClairBookmark>
- (instancetype)initWithNode:(const BookmarkNode*)node isNew:(BOOL)isNew;
@end

@implementation ClairChromiumBookmark
@synthesize bookmarkID = _bookmarkID;
@synthesize title = _title;
@synthesize url = _url;
@synthesize folderID = _folderID;
@synthesize isNew = _isNew;

- (instancetype)initWithNode:(const BookmarkNode*)node isNew:(BOOL)isNew {
  if ((self = [super init])) {
    _bookmarkID = node->id();
    _title = base::SysUTF16ToNSString(node->GetTitle());
    _url = net::NSURLWithGURL(node->url());
    _folderID =
        node->parent() ? node->parent()->id() : ClairBookmarkFolderIDNone;
    _isNew = isNew;
  }
  return self;
}
@end

@interface ClairChromiumBookmarkFolder : NSObject <ClairBookmarkFolder>
- (instancetype)initWithNode:(const BookmarkNode*)node depth:(NSInteger)depth;
@end

@implementation ClairChromiumBookmarkFolder
@synthesize folderID = _folderID;
@synthesize title = _title;
@synthesize depth = _depth;

- (instancetype)initWithNode:(const BookmarkNode*)node depth:(NSInteger)depth {
  if ((self = [super init])) {
    _folderID = node->id();
    _title = base::SysUTF16ToNSString(node->GetTitle());
    _depth = depth;
  }
  return self;
}
@end

namespace clair {

namespace {

// The profile's bookmarks, once loaded; an incognito or guest profile's are
// its original profile's (BookmarkModelFactory redirects).
BookmarkModel* LoadedModel(Browser* browser) {
  if (!browser) {
    return nullptr;
  }
  BookmarkModel* model =
      BookmarkModelFactory::GetForBrowserContext(browser->GetProfile());
  return model && model->loaded() ? model : nullptr;
}

// The page Chromium would bookmark for the active tab, and its title.
bool ActivePage(Browser* browser, GURL* url, std::u16string* title) {
  content::WebContents* contents =
      browser ? browser->tab_strip_model()->GetActiveWebContents() : nullptr;
  return contents && chrome::GetURLAndTitleToBookmark(contents, url, title);
}

// Whether `node` is Other Bookmarks or one of its folders: where D3 lets a
// bookmark be saved.
bool IsSaveFolder(BookmarkModel* model, const BookmarkNode* node) {
  if (!node || !node->is_folder()) {
    return false;
  }
  for (const BookmarkNode* at = node; at; at = at->parent()) {
    if (at == model->other_node()) {
      return true;
    }
  }
  return false;
}

// The user's bookmark with `id`, or null for a folder, a managed bookmark or
// an unknown ID.
const BookmarkNode* UserBookmark(BookmarkModel* model, ClairBookmarkID id) {
  const BookmarkNode* node = bookmarks::GetBookmarkNodeByID(model, id);
  if (!node || !node->is_url() || model->client()->IsNodeManaged(node)) {
    return nullptr;
  }
  return node;
}

void AddFolders(const BookmarkNode* folder,
                NSInteger depth,
                NSMutableArray<id<ClairBookmarkFolder>>* folders) {
  [folders addObject:[[ClairChromiumBookmarkFolder alloc] initWithNode:folder
                                                                 depth:depth]];
  for (const auto& child : folder->children()) {
    if (child->is_folder()) {
      AddFolders(child.get(), depth + 1, folders);
    }
  }
}

}  // namespace

bool IsActivePageBookmarked(Browser* browser) {
  BookmarkModel* model = LoadedModel(browser);
  GURL url;
  std::u16string title;
  return model && ActivePage(browser, &url, &title) &&
         bookmarks::IsBookmarkedByUser(model, url);
}

void BookmarkActivePage(ClairBrowserWindow* window) {
  Browser* browser = window ? window->browser() : nullptr;
  BookmarkModel* model = LoadedModel(browser);
  id<ClairWindow> clair_window = window ? window->clair_window() : nil;
  GURL url;
  std::u16string title;
  if (!model || !clair_window || !chrome::CanBookmarkCurrentTab(browser) ||
      !ActivePage(browser, &url, &title)) {
    return;
  }
  const BookmarkNode* node = model->GetMostRecentlyAddedUserNodeForURL(url);
  const bool is_new = !node;
  if (is_new) {
    content::WebContents* contents =
        browser->tab_strip_model()->GetActiveWebContents();
    if (contents->GetBrowserContext()->IsOffTheRecord()) {
      // As BookmarkCurrentTab does: an incognito page's favicon isn't saved
      // otherwise, and the bookmark would have none.
      favicon::SaveFaviconEvenIfInIncognito(contents);
    }
    const BookmarkNode* other = model->other_node();
    node = model->AddNewURL(other, other->children().size(), title, url);
    if (!node) {
      return;
    }
  }
  [clair_window showBookmarkDialog:[[ClairChromiumBookmark alloc]
                                       initWithNode:node
                                              isNew:is_new]];
}

NSArray<id<ClairBookmarkFolder>>* BookmarkFolders(Browser* browser) {
  BookmarkModel* model = LoadedModel(browser);
  NSMutableArray<id<ClairBookmarkFolder>>* folders = [NSMutableArray array];
  if (model) {
    AddFolders(model->other_node(), 0, folders);
  }
  return folders;
}

void UpdateBookmark(Browser* browser,
                    ClairBookmarkID bookmark_id,
                    NSString* title,
                    ClairBookmarkFolderID folder_id) {
  BookmarkModel* model = LoadedModel(browser);
  const BookmarkNode* node = model ? UserBookmark(model, bookmark_id) : nullptr;
  if (!node) {
    return;
  }
  std::u16string new_title = base::SysNSStringToUTF16(title ?: @"");
  if (new_title.empty()) {
    // The page's title: the active tab's when it shows the bookmark's page.
    GURL url;
    std::u16string page_title;
    if (ActivePage(browser, &url, &page_title) && url == node->url() &&
        !page_title.empty()) {
      new_title = page_title;
    } else {
      new_title = url_formatter::FormatUrl(node->url());
    }
  }
  if (new_title != node->GetTitle()) {
    model->SetTitle(node, new_title,
                    bookmarks::metrics::BookmarkEditSource::kUser);
  }
  const BookmarkNode* folder = bookmarks::GetBookmarkNodeByID(model, folder_id);
  if (folder != node->parent() && IsSaveFolder(model, folder)) {
    model->Move(node, folder, folder->children().size());
  }
}

void RemoveBookmark(Browser* browser, ClairBookmarkID bookmark_id) {
  BookmarkModel* model = LoadedModel(browser);
  if (const BookmarkNode* node =
          model ? UserBookmark(model, bookmark_id) : nullptr) {
    model->Remove(node, bookmarks::metrics::BookmarkEditSource::kUser,
                  FROM_HERE);
  }
}

ClairBookmarkFolderID AddBookmarkFolder(Browser* browser, NSString* title) {
  BookmarkModel* model = LoadedModel(browser);
  std::u16string trimmed;
  base::TrimWhitespace(base::SysNSStringToUTF16(title ?: @""), base::TRIM_ALL,
                       &trimmed);
  if (!model || trimmed.empty()) {
    return ClairBookmarkFolderIDNone;
  }
  const BookmarkNode* other = model->other_node();
  const BookmarkNode* folder =
      model->AddFolder(other, other->children().size(), trimmed);
  return folder ? folder->id() : ClairBookmarkFolderIDNone;
}

}  // namespace clair

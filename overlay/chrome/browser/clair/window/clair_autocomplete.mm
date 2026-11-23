// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/window/clair_autocomplete.h"

#include <algorithm>
#include <map>
#include <memory>
#include <optional>
#include <vector>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/strcat.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/bookmarks/bookmark_model_factory.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/favicon/favicon_service_factory.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/history/top_sites_factory.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/bookmarks/browser/bookmark_utils.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/top_sites.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/omnibox/browser/autocomplete_classifier.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_enums.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "components/omnibox/browser/favicon_cache.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace {

// Arc shows five rows (D11).
constexpr size_t kMaxSuggestions = 5;

// What a row opens and how, kept for -openSuggestion:.
struct Destination {
  GURL url;
  ui::PageTransition transition = ui::PAGE_TRANSITION_TYPED;
  // The tab it switches to instead, if any.
  base::WeakPtr<content::WebContents> tab;
  // The match it shows, for -deleteSuggestion:. Empty for the empty-query
  // rows, which don't come from the controller.
  std::optional<AutocompleteMatch> match;
  // The icon of the engine it offers to search with Tab, if any.
  GURL keyword_icon_url;
};

}  // namespace

@interface ClairChromiumSuggestion : NSObject <ClairSuggestion>
@property(nonatomic) NSInteger suggestionID;
@property(nonatomic) ClairSuggestionKind kind;
@property(nonatomic, copy) NSString* contents;
@property(nonatomic, copy) NSString* descriptionText;
@property(nonatomic, copy, nullable) NSURL* destination;
@property(nonatomic, nullable) NSImage* icon;
@property(nonatomic) BOOL hasTabMatch;
@property(nonatomic, copy, nullable) NSString* keyword;
@property(nonatomic, copy, nullable) NSString* keywordName;
@property(nonatomic, nullable) NSImage* keywordIcon;
@property(nonatomic) BOOL canDelete;
@end

@implementation ClairChromiumSuggestion

// The same suggestion, with the same ID, showing `icon` and offering its
// engine with `keywordIcon`.
- (ClairChromiumSuggestion*)suggestionWithIcon:(NSImage*)icon
                                   keywordIcon:(NSImage*)keywordIcon {
  ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
  suggestion.suggestionID = _suggestionID;
  suggestion.kind = _kind;
  suggestion.contents = _contents;
  suggestion.descriptionText = _descriptionText;
  suggestion.destination = _destination;
  suggestion.icon = icon;
  suggestion.hasTabMatch = _hasTabMatch;
  suggestion.keyword = _keyword;
  suggestion.keywordName = _keywordName;
  suggestion.keywordIcon = keywordIcon;
  suggestion.canDelete = _canDelete;
  return suggestion;
}

@end

@interface ClairChromiumAutocomplete ()
- (void)resultChanged;
@end

namespace {

class ControllerObserver : public AutocompleteController::Observer {
 public:
  explicit ControllerObserver(ClairChromiumAutocomplete* session)
      : session_(session) {}

  void OnResultChanged(AutocompleteController* controller,
                       bool default_match_changed) override {
    [session_ resultChanged];
  }

 private:
  ClairChromiumAutocomplete* __weak session_;
};

// Whether the user bookmarked `url` (add-bookmarks-menu D8). `model` is the
// profile's bookmarks, or its original profile's in incognito.
bool IsBookmarked(bookmarks::BookmarkModel* model, const GURL& url) {
  return model && model->loaded() && bookmarks::IsBookmarkedByUser(model, url);
}

ClairSuggestionKind KindOf(const AutocompleteMatch& match,
                           bookmarks::BookmarkModel* bookmark_model) {
  if (match.has_tab_match.value_or(false) ||
      match.type == omnibox::AutocompleteMatchType::kOpenTab) {
    return ClairSuggestionKindOpenTab;
  }
  if (AutocompleteMatch::IsSearchType(match.type)) {
    return ClairSuggestionKindSearch;
  }
  // add-bookmarks-menu D8: a bookmarked page looks the same whether bookmarks
  // or history suggested it.
  if (IsBookmarked(bookmark_model, match.destination_url)) {
    return ClairSuggestionKindBookmark;
  }
  if (match.type == omnibox::AutocompleteMatchType::kUrlWhatYouTyped) {
    return ClairSuggestionKindURL;
  }
  return ClairSuggestionKindHistory;
}

}  // namespace

@implementation ClairChromiumAutocomplete {
  base::WeakPtr<ClairBrowserWindow> _browserWindow;
  ClairCommandBarMode _mode;
  id<ClairAutocompleteDelegate> __weak _delegate;
  std::unique_ptr<AutocompleteController> _controller;
  std::unique_ptr<ControllerObserver> _observer;
  std::vector<std::pair<NSInteger, Destination>> _destinations;
  NSInteger _nextSuggestionID;
  NSInteger _generation;
  BOOL _stopped;
  NSString* _keyword;
  NSString* _keywordName;
  NSImage* _keywordIcon;
  GURL _keywordIconURL;
  NSArray<id<ClairSuggestion>>* _lastSuggestions;
  BOOL _lastFinished;
  // The rows' favicons, as the omnibox keeps them: cached ones come back at
  // once, so rows don't flicker as the user types.
  std::unique_ptr<FaviconCache> _favicons;
  // Favicons that arrived since the rows were last published, by page URL.
  std::map<GURL, gfx::Image> _arrivedFavicons;
  // Search engines' icons that arrived since then, by icon URL.
  std::map<GURL, gfx::Image> _arrivedEngineIcons;
  BOOL _faviconsPending;
}

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow
                                 mode:(ClairCommandBarMode)mode
                             delegate:(id<ClairAutocompleteDelegate>)delegate {
  if ((self = [super init])) {
    _mode = mode;
    _delegate = delegate;
    _nextSuggestionID = 1;
    if (browserWindow) {
      _browserWindow = browserWindow->GetWeakPtr();
      Profile* profile = browserWindow->browser()->GetProfile();
      // add-bookmarks-menu D8: the omnibox's own sources, bookmarks included.
      AutocompleteControllerConfig config{
          .provider_types = AutocompleteClassifier::DefaultOmniboxProviders()};
      _controller = std::make_unique<AutocompleteController>(
          std::make_unique<ChromeAutocompleteProviderClient>(profile), config);
      _observer = std::make_unique<ControllerObserver>(self);
      _controller->AddObserver(_observer.get());
      // Read-only, so an incognito window shows the favicons its regular
      // profile has, as the omnibox does, and records nothing.
      _favicons = std::make_unique<FaviconCache>(
          FaviconServiceFactory::GetForProfile(
              profile, ServiceAccessType::EXPLICIT_ACCESS),
          HistoryServiceFactory::GetForProfile(
              profile, ServiceAccessType::EXPLICIT_ACCESS));
    }
  }
  return self;
}

- (void)dealloc {
  [self stop];
}

- (Profile*)profile {
  return _browserWindow ? _browserWindow->browser()->GetProfile() : nullptr;
}

// The bookmarks the rows check, the original profile's in incognito.
- (bookmarks::BookmarkModel*)bookmarkModel {
  Profile* profile = self.profile;
  return profile ? BookmarkModelFactory::GetForBrowserContext(profile) : nullptr;
}

- (NSString*)keyword {
  return _keyword;
}

- (NSString*)keywordName {
  return _keywordName;
}

- (NSImage*)keywordIcon {
  return _keywordIcon;
}

- (const Destination*)destinationOf:(NSInteger)suggestionID {
  auto found = std::ranges::find_if(
      _destinations, [&](const auto& entry) { return entry.first == suggestionID; });
  return found == _destinations.end() ? nullptr : &found->second;
}

// Republishes the rows with the favicons and engine icons that arrived,
// keeping their IDs, which tells ClairUI that only icons changed.
- (void)showArrivedFavicons {
  _faviconsPending = NO;
  std::map<GURL, gfx::Image> arrived;
  arrived.swap(_arrivedFavicons);
  std::map<GURL, gfx::Image> arrivedEngineIcons;
  arrivedEngineIcons.swap(_arrivedEngineIcons);
  if (_stopped) {
    return;
  }
  BOOL changed = NO;
  // The engine in keyword mode, which ClairUI reads on the next update.
  if (_keyword && !_keywordIcon) {
    if (auto found = arrivedEngineIcons.find(_keywordIconURL);
        found != arrivedEngineIcons.end()) {
      _keywordIcon = found->second.AsNSImage();
      changed = YES;
    }
  }
  NSMutableArray<id<ClairSuggestion>>* suggestions = [NSMutableArray array];
  for (id<ClairSuggestion> item in _lastSuggestions) {
    ClairChromiumSuggestion* suggestion = (ClairChromiumSuggestion*)item;
    const Destination* destination = [self destinationOf:suggestion.suggestionID];
    NSImage* icon = suggestion.icon;
    NSImage* keywordIcon = suggestion.keywordIcon;
    if (destination && !icon && suggestion.kind != ClairSuggestionKindSearch &&
        suggestion.kind != ClairSuggestionKindBookmark) {
      if (auto found = arrived.find(destination->url); found != arrived.end()) {
        icon = found->second.AsNSImage();
      }
    }
    if (destination && !keywordIcon && suggestion.keyword) {
      if (auto found = arrivedEngineIcons.find(destination->keyword_icon_url);
          found != arrivedEngineIcons.end()) {
        keywordIcon = found->second.AsNSImage();
      }
    }
    if (icon == suggestion.icon && keywordIcon == suggestion.keywordIcon) {
      [suggestions addObject:suggestion];
      continue;
    }
    [suggestions addObject:[suggestion suggestionWithIcon:icon
                                              keywordIcon:keywordIcon]];
    changed = YES;
  }
  if (changed) {
    [self publish:suggestions finished:_lastFinished];
  }
}

// Shows the icons that arrive in one turn of the run loop in a single update.
- (void)scheduleArrivedFavicons {
  if (_faviconsPending) {
    return;
  }
  _faviconsPending = YES;
  ClairChromiumAutocomplete* __weak weakSelf = self;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(^{
        [weakSelf showArrivedFavicons];
      }));
}

- (void)favicon:(const gfx::Image&)favicon arrivedForPageURL:(const GURL&)url {
  if (_stopped || favicon.IsEmpty()) {
    return;
  }
  _arrivedFavicons[url] = favicon;
  [self scheduleArrivedFavicons];
}

- (void)engineIcon:(const gfx::Image&)icon arrivedForIconURL:(const GURL&)url {
  if (_stopped || icon.IsEmpty()) {
    return;
  }
  _arrivedEngineIcons[url] = icon;
  [self scheduleArrivedFavicons];
}

// A search engine's icon from the profile's favicon database, as the omnibox
// shows it for keyword search, or nil. One not cached yet is fetched, and
// shows when it arrives; an engine whose site was never visited has none.
- (NSImage*)iconForEngineIconURL:(const GURL&)iconURL {
  if (!_favicons || !iconURL.is_valid()) {
    return nil;
  }
  const GURL url = iconURL;
  ClairChromiumAutocomplete* __weak weakSelf = self;
  const gfx::Image cached = _favicons->GetFaviconForIconUrl(
      iconURL,
      base::BindOnce(^(const gfx::Image& icon) {
        [weakSelf engineIcon:icon arrivedForIconURL:url];
      }),
      /*notify_on_empty=*/false);
  return cached.IsEmpty() ? nil : cached.AsNSImage();
}

// The page's favicon from the profile's favicon database, or nil. One not
// cached yet is fetched, and shows when it arrives.
- (NSImage*)faviconForPageURL:(const GURL&)url {
  if (!_favicons) {
    return nil;
  }
  const GURL pageURL = url;
  ClairChromiumAutocomplete* __weak weakSelf = self;
  const gfx::Image cached = _favicons->GetFaviconForPageUrl(
      url, base::BindOnce(^(const gfx::Image& favicon) {
        [weakSelf favicon:favicon arrivedForPageURL:pageURL];
      }));
  return cached.AsNSImage();
}

- (NSInteger)rememberDestination:(Destination)destination {
  const NSInteger suggestionID = _nextSuggestionID++;
  _destinations.emplace_back(suggestionID, std::move(destination));
  return suggestionID;
}

- (void)startWithText:(const std::u16string&)text inKeywordMode:(bool)keywordMode {
  Profile* profile = self.profile;
  if (_stopped || !_controller || !profile) {
    return;
  }
  ++_generation;
  _controller->Stop(AutocompleteStopReason::kClobbered);
  const metrics::OmniboxEventProto::PageClassification classification =
      _mode == ClairCommandBarModeNewTab
          ? metrics::OmniboxEventProto::INSTANT_NTP_WITH_OMNIBOX_AS_STARTING_FOCUS
          : metrics::OmniboxEventProto::OTHER;
  AutocompleteInput input(text, classification,
                          ChromeAutocompleteSchemeClassifier(profile));
  // Arc fills nothing in.
  input.set_prevent_inline_autocomplete(true);
  input.set_in_keyword_mode(keywordMode);
  input.set_allow_exact_keyword_match(keywordMode);
  _controller->Start(input);
}

- (void)queryText:(NSString*)text {
  if (_stopped) {
    return;
  }
  std::u16string query = base::SysNSStringToUTF16(text);
  if (_keyword) {
    [self startWithText:base::StrCat({base::SysNSStringToUTF16(_keyword), u" ",
                                      query})
          inKeywordMode:true];
    return;
  }
  if (query.empty()) {
    [self showEmptyQueryList];
    return;
  }
  [self startWithText:query inKeywordMode:false];
}

- (void)acceptKeywordOfSuggestion:(NSInteger)suggestionID text:(NSString*)text {
  Profile* profile = self.profile;
  if (_stopped || !profile || !_controller) {
    return;
  }
  NSString* keyword = nil;
  for (id<ClairSuggestion> suggestion in _lastSuggestions) {
    if (suggestion.suggestionID == suggestionID) {
      keyword = suggestion.keyword;
    }
  }
  if (!keyword.length) {
    return;
  }
  TemplateURLService* service = TemplateURLServiceFactory::GetForProfile(profile);
  TemplateURL* engine =
      service ? service->GetTemplateURLForKeyword(base::SysNSStringToUTF16(keyword))
              : nullptr;
  _keyword = keyword;
  _keywordName = engine ? base::SysUTF16ToNSString(engine->short_name()) : keyword;
  _keywordIconURL = engine ? engine->favicon_url() : GURL();
  _keywordIcon = [self iconForEngineIconURL:_keywordIconURL];
  [self queryText:text];
}

- (void)clearKeywordWithText:(NSString*)text {
  _keyword = nil;
  _keywordName = nil;
  _keywordIcon = nil;
  _keywordIconURL = GURL();
  [self queryText:text];
}

// D11: with an empty query, the window's other tabs by last use, then the profile's
// most visited sites. ungoogled-chromium's zero-suggest has no remote source,
// so this list is built here.
- (void)showEmptyQueryList {
  ++_generation;
  if (_controller) {
    _controller->Stop(AutocompleteStopReason::kClobbered);
  }
  _destinations.clear();
  NSMutableArray<id<ClairSuggestion>>* suggestions = [NSMutableArray array];
  if (_browserWindow) {
    TabStripModel* strip = _browserWindow->browser()->tab_strip_model();
    std::vector<content::WebContents*> tabs;
    // Switching to the tab already shown would do nothing.
    for (int i = 0; i < strip->count(); ++i) {
      if (i != strip->active_index()) {
        tabs.push_back(strip->GetWebContentsAt(i));
      }
    }
    std::ranges::sort(tabs, [](content::WebContents* a, content::WebContents* b) {
      return a->GetLastActiveTimeTicks() > b->GetLastActiveTimeTicks();
    });
    for (content::WebContents* tab : tabs) {
      ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
      suggestion.kind = ClairSuggestionKindOpenTab;
      suggestion.contents = base::SysUTF16ToNSString(tab->GetTitle());
      suggestion.descriptionText = base::SysUTF16ToNSString(
          url_formatter::FormatUrl(tab->GetLastCommittedURL()));
      suggestion.destination = net::NSURLWithGURL(tab->GetLastCommittedURL());
      suggestion.hasTabMatch = YES;
      if (auto* favicons = favicon::ContentFaviconDriver::FromWebContents(tab);
          favicons && favicons->FaviconIsValid()) {
        suggestion.icon = favicons->GetFavicon().ToNSImage();
      }
      suggestion.suggestionID =
          [self rememberDestination:Destination{tab->GetLastCommittedURL(),
                                                ui::PAGE_TRANSITION_AUTO_BOOKMARK,
                                                tab->GetWeakPtr()}];
      [suggestions addObject:suggestion];
    }
  }
  [self publish:suggestions finished:NO];

  Profile* profile = self.profile;
  scoped_refptr<history::TopSites> top_sites =
      profile ? TopSitesFactory::GetForProfile(profile) : nullptr;
  if (!top_sites) {
    [self publish:suggestions finished:YES];
    return;
  }
  const NSInteger generation = _generation;
  ClairChromiumAutocomplete* __weak weakSelf = self;
  NSArray<id<ClairSuggestion>>* tabSuggestions = [suggestions copy];
  top_sites->GetMostVisitedURLs(
      base::BindOnce(^(const history::MostVisitedURLList& sites) {
        [weakSelf addMostVisited:sites
                   toSuggestions:tabSuggestions
                      generation:generation];
      }));
}

- (void)addMostVisited:(const history::MostVisitedURLList&)sites
         toSuggestions:(NSArray<id<ClairSuggestion>>*)tabs
            generation:(NSInteger)generation {
  if (_stopped || generation != _generation) {
    return;
  }
  NSMutableArray<id<ClairSuggestion>>* suggestions = [tabs mutableCopy];
  for (const history::MostVisitedURL& site : sites) {
    if (suggestions.count >= tabs.count + kMaxSuggestions) {
      break;
    }
    ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
    // add-bookmarks-menu D8: a bookmarked page shows the bookmark icon.
    const bool bookmarked = IsBookmarked(self.bookmarkModel, site.url);
    suggestion.kind =
        bookmarked ? ClairSuggestionKindBookmark : ClairSuggestionKindHistory;
    suggestion.contents = base::SysUTF16ToNSString(
        site.title.empty() ? url_formatter::FormatUrl(site.url) : site.title);
    suggestion.descriptionText =
        base::SysUTF16ToNSString(url_formatter::FormatUrl(site.url));
    suggestion.destination = net::NSURLWithGURL(site.url);
    if (!bookmarked) {
      suggestion.icon = [self faviconForPageURL:site.url];
    }
    suggestion.suggestionID = [self
        rememberDestination:Destination{site.url, ui::PAGE_TRANSITION_AUTO_BOOKMARK,
                                        nullptr}];
    [suggestions addObject:suggestion];
  }
  [self publish:suggestions finished:YES];
}

- (void)resultChanged {
  if (_stopped || !_controller) {
    return;
  }
  _destinations.clear();
  NSMutableArray<id<ClairSuggestion>>* suggestions = [NSMutableArray array];
  Profile* profile = self.profile;
  TemplateURLService* service =
      profile ? TemplateURLServiceFactory::GetForProfile(profile) : nullptr;
  bookmarks::BookmarkModel* bookmark_model = self.bookmarkModel;
  for (const AutocompleteMatch& match : _controller->result()) {
    if (suggestions.count >= kMaxSuggestions) {
      break;
    }
    if (!match.destination_url.is_valid()) {
      continue;
    }
    ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
    suggestion.kind = KindOf(match, bookmark_model);
    // The row's title, as the omnibox shows it first: a page's title comes
    // in `description`, with `swap_contents_and_description` set
    // (command-bar spec, "Suggestions from Chromium's autocomplete").
    const bool swapped = match.swap_contents_and_description;
    suggestion.contents = base::SysUTF16ToNSString(
        swapped ? match.description : match.contents);
    suggestion.descriptionText = base::SysUTF16ToNSString(
        swapped ? match.contents : match.description);
    suggestion.destination = net::NSURLWithGURL(match.destination_url);
    suggestion.hasTabMatch = match.has_tab_match.value_or(false);
    // Searches keep the magnifier, as in Arc, and bookmarked pages show the
    // bookmark icon without waiting on the favicon database
    // (add-bookmarks-menu D8).
    if (suggestion.kind != ClairSuggestionKindSearch &&
        suggestion.kind != ClairSuggestionKindBookmark) {
      suggestion.icon = [self faviconForPageURL:match.destination_url];
    }
    GURL keywordIconURL;
    if (!match.associated_keyword.empty()) {
      suggestion.keyword = base::SysUTF16ToNSString(match.associated_keyword);
      TemplateURL* engine =
          service ? service->GetTemplateURLForKeyword(match.associated_keyword)
                  : nullptr;
      suggestion.keywordName =
          engine ? base::SysUTF16ToNSString(engine->short_name())
                 : suggestion.keyword;
      // command-bar spec, "Site search keywords": the engine's icon.
      if (engine) {
        keywordIconURL = engine->favicon_url();
        suggestion.keywordIcon = [self iconForEngineIconURL:keywordIconURL];
      }
    }
    suggestion.canDelete = match.SupportsDeletion();
    suggestion.suggestionID = [self
        rememberDestination:Destination{match.destination_url, match.transition,
                                        nullptr, match, keywordIconURL}];
    [suggestions addObject:suggestion];
  }
  [self publish:suggestions finished:_controller->done()];
}

- (void)deleteSuggestion:(NSInteger)suggestionID {
  if (_stopped || !_controller) {
    return;
  }
  auto found = std::ranges::find_if(
      _destinations, [&](const auto& entry) { return entry.first == suggestionID; });
  if (found == _destinations.end() || !found->second.match ||
      !found->second.match->SupportsDeletion()) {
    return;
  }
  // A copy: Chromium sends the shorter list during the call, which replaces
  // _destinations. Providers find what to delete by its URL or contents.
  const AutocompleteMatch match = *found->second.match;
  // A page typed without a scheme is in history twice, as http: and as the
  // https: page it was upgraded to. The history index doesn't learn the
  // first until later, so the match may not carry it as a duplicate, and
  // deleting the match alone would let the page come back. Delete it too.
  const GURL& url = match.destination_url;
  if (match.deletable && !AutocompleteMatch::IsSearchType(match.type) &&
      url.SchemeIsHTTPOrHTTPS()) {
    GURL::Replacements other_scheme;
    other_scheme.SetSchemeStr(url.SchemeIs(url::kHttpsScheme) ? url::kHttpScheme
                                                              : url::kHttpsScheme);
    if (history::HistoryService* history = HistoryServiceFactory::GetForProfile(
            self.profile, ServiceAccessType::EXPLICIT_ACCESS)) {
      history->DeleteURLs({url.ReplaceComponents(other_scheme)});
    }
  }
  _controller->DeleteMatch(match);
}

- (void)publish:(NSArray<id<ClairSuggestion>>*)suggestions finished:(BOOL)finished {
  _lastSuggestions = [suggestions copy];
  _lastFinished = finished;
  [_delegate autocomplete:self
      didUpdateSuggestions:_lastSuggestions
                  finished:finished];
}

// Activates the tab of this profile showing `url`, in its window.
- (BOOL)switchToTab:(const Destination&)destination {
  content::WebContents* target = destination.tab.get();
  Profile* profile = self.profile;
  bool switched = false;
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&](BrowserWindowInterface* browser) {
        if (browser->GetProfile() != profile) {
          return true;
        }
        TabStripModel* strip = browser->GetTabStripModel();
        for (int i = 0; i < strip->count(); ++i) {
          content::WebContents* contents = strip->GetWebContentsAt(i);
          if (target ? contents == target
                     : contents->GetLastCommittedURL() == destination.url) {
            strip->ActivateTabAt(
                i, TabStripUserGestureDetails(
                       TabStripUserGestureDetails::GestureType::kOther));
            browser->GetWindow()->Activate();
            switched = true;
            return false;
          }
        }
        return true;
      });
  return switched;
}

- (void)openSuggestion:(NSInteger)suggestionID
           disposition:(ClairOpenDisposition)disposition {
  if (_stopped || !_browserWindow) {
    return;
  }
  auto found = std::ranges::find_if(
      _destinations, [&](const auto& entry) { return entry.first == suggestionID; });
  if (found == _destinations.end()) {
    return;
  }
  const Destination destination = found->second;
  BOOL hasTabMatch = destination.tab.get() != nullptr;
  for (id<ClairSuggestion> suggestion in _lastSuggestions) {
    if (suggestion.suggestionID == suggestionID && suggestion.hasTabMatch) {
      hasTabMatch = YES;
    }
  }
  Browser* browser = _browserWindow->browser();
  [self stop];
  if (hasTabMatch && [self switchToTab:destination]) {
    return;
  }
  NavigateParams params(browser, destination.url, destination.transition);
  switch (disposition) {
    case ClairOpenDispositionCurrentTab:
      params.disposition = WindowOpenDisposition::CURRENT_TAB;
      break;
    case ClairOpenDispositionNewForegroundTab:
      params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
      break;
    case ClairOpenDispositionNewBackgroundTab:
      params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
      break;
    case ClairOpenDispositionNewWindow:
      params.disposition = WindowOpenDisposition::NEW_WINDOW;
      break;
  }
  // add-pinned-tabs-and-favorites D7: another site leaves a favorite's page
  // as it is, in a new Today tab.
  if (params.disposition == WindowOpenDisposition::CURRENT_TAB &&
      clair::LeavesFavorite(_browserWindow.get(), destination.url)) {
    params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
  }
  params.window_action = NavigateParams::WindowAction::kShowWindow;
  Navigate(&params);
}

- (void)stop {
  if (_stopped) {
    return;
  }
  _stopped = YES;
  if (_controller) {
    _controller->Stop(AutocompleteStopReason::kInteraction);
    _controller->RemoveObserver(_observer.get());
  }
  _observer.reset();
  _controller.reset();
  _favicons.reset();
  _arrivedFavicons.clear();
  _arrivedEngineIcons.clear();
  _delegate = nil;
}

@end

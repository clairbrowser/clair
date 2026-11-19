// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/clair_space_tabs.h"

#include <algorithm>
#include <limits>
#include <utility>

#include "base/barrier_closure.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/escape.h"
#include "base/strings/string_util.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/browser_process.h"
#import "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_window_group.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/clair/window/clair_space_session.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profiles_state.h"
#include "chrome/browser/sessions/session_restore.h"
#include "chrome/browser/sessions/session_service.h"
#include "chrome/browser/sessions/session_service_factory.h"
#include "chrome/browser/sessions/tab_restore_service_factory.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/recently_audible_helper.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/webui_url_constants.h"
#include "components/content_settings/browser/page_specific_content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/security_state/core/security_state.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/sessions/core/tab_restore_service.h"
#include "components/url_formatter/url_formatter.h"
#include "base/scoped_observation.h"
#include "base/strings/utf_string_conversions.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/referrer.h"
#include "content/public/common/url_constants.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace {

// --- The Space tag (D2, D6) ---------------------------------------------------

const void* const kSpaceTagKey = &kSpaceTagKey;
const void* const kSpaceTabsKey = &kSpaceTabsKey;
const void* const kPlaceholderKey = &kPlaceholderKey;

// share-tabs-across-windows D2: marks a window's placeholder tab.
struct PlaceholderMark : public base::SupportsUserData::Data {};

// A tab's Space, kept on its WebContents so it follows the tab between
// windows and comes back with it from a session.
struct SpaceTag : public base::SupportsUserData::Data {
  std::string space;
  // From a restored session: the tab's index in its Space's list when it was
  // saved. It orders restored tabs until the list is next written.
  std::optional<int> rank;
  // What the session holds for the tab, so it's written only on a change.
  std::string written_space;
  int written_rank = -1;
  // add-profiles D6: the window group a restored tab's window belonged to,
  // and the group the session holds for it.
  std::string window;
  std::string written_window;
  // add-profiles D6: the window selected this restored tab in place of a new
  // tab page it dropped.
  bool new_tab_was_selected = false;
  // add-pinned-tabs-and-favorites D2, D3: the pin the tab is bound to, is to
  // be bound to as it joins a strip, or was bound to before Remove Pin, so
  // that Restore Last Closed Tab binds it again. Bound or not is
  // ClairSpaceTabs::bound_'s.
  std::string pin;
  // The tab's custom name while it isn't bound; a bound tab's is its pin's.
  std::string name;
  // What the session holds for the two; nullopt when unknown.
  std::optional<std::string> written_pin;
  std::optional<std::string> written_name;
};

// add-profiles D6: the group of the window holding `contents`, or empty.
std::string GroupOf(content::WebContents* contents) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(contents);
  ClairWindowGroup* group = window ? ClairWindowGroup::Of(window) : nullptr;
  return group ? group->id() : std::string();
}

SpaceTag* GetTag(content::WebContents* contents) {
  return contents ? static_cast<SpaceTag*>(contents->GetUserData(kSpaceTagKey))
                  : nullptr;
}

SpaceTag* EnsureTag(content::WebContents* contents) {
  if (SpaceTag* tag = GetTag(contents)) {
    return tag;
  }
  auto tag = std::make_unique<SpaceTag>();
  SpaceTag* raw = tag.get();
  contents->SetUserData(kSpaceTagKey, std::move(tag));
  return raw;
}

std::set<ClairSpaceTabs*>& Instances() {
  static base::NoDestructor<std::set<ClairSpaceTabs*>> instances;
  return *instances;
}

// --- Snapshots (moved from clair_browser_bridge.mm) --------------------------

NSString* NSStringOrNil(const std::u16string& text) {
  return text.empty() ? nil : base::SysUTF16ToNSString(text);
}

ClairTabIndicators IndicatorsOf(content::WebContents* contents) {
  ClairTabIndicators indicators = ClairTabIndicatorsNone;
  scoped_refptr<MediaStreamCaptureIndicator> capture =
      MediaCaptureDevicesDispatcher::GetInstance()
          ->GetMediaStreamCaptureIndicator();
  if (capture) {
    if (capture->IsCapturingVideo(contents)) {
      indicators |= ClairTabIndicatorsCamera;
    }
    if (capture->IsCapturingAudio(contents)) {
      indicators |= ClairTabIndicatorsMicrophone;
    }
    if (capture->IsBeingMirrored(contents) || capture->IsCapturingTab(contents) ||
        capture->IsCapturingWindow(contents) ||
        capture->IsCapturingDisplay(contents)) {
      indicators |= ClairTabIndicatorsScreenCapture;
    }
  }
  auto* settings = content_settings::PageSpecificContentSettings::GetForFrame(
      contents->GetPrimaryMainFrame());
  if (settings) {
    if (settings->IsContentAllowed(ContentSettingsType::GEOLOCATION)) {
      indicators |= ClairTabIndicatorsLocation;
    }
    for (ContentSettingsType type :
         {ContentSettingsType::GEOLOCATION, ContentSettingsType::NOTIFICATIONS,
          ContentSettingsType::MEDIASTREAM_CAMERA,
          ContentSettingsType::MEDIASTREAM_MIC}) {
      if (settings->IsContentBlocked(type)) {
        indicators |= ClairTabIndicatorsBlockedPermission;
      }
    }
  }
  return indicators;
}

}  // namespace

@interface ClairChromiumInfobar : NSObject <ClairInfobar>
- (instancetype)initWithInfobar:(infobars::InfoBar*)infobar
                       delegate:(ConfirmInfoBarDelegate*)delegate;
@end

@implementation ClairChromiumInfobar
@synthesize infobarID = _infobarID;
@synthesize message = _message;
@synthesize linkText = _linkText;
@synthesize okButtonLabel = _okButtonLabel;
@synthesize cancelButtonLabel = _cancelButtonLabel;
@synthesize icon = _icon;

- (instancetype)initWithInfobar:(infobars::InfoBar*)infobar
                       delegate:(ConfirmInfoBarDelegate*)delegate {
  if ((self = [super init])) {
    _infobarID = clair::InfobarIDOf(infobar);
    _message = base::SysUTF16ToNSString(delegate->GetMessageText());
    _linkText = NSStringOrNil(delegate->GetLinkText());
    const int buttons = delegate->GetButtons();
    if (buttons & ConfirmInfoBarDelegate::BUTTON_OK) {
      _okButtonLabel = base::SysUTF16ToNSString(
          delegate->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_OK));
    }
    if (buttons & ConfirmInfoBarDelegate::BUTTON_CANCEL) {
      _cancelButtonLabel = base::SysUTF16ToNSString(
          delegate->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_CANCEL));
    }
  }
  return self;
}
@end

@interface ClairChromiumTab : NSObject <ClairTab>
- (instancetype)initWithContents:(content::WebContents*)contents
                    peekParentID:(ClairTabID)peekParentID
                          peekID:(ClairTabID)peekID
                         spaceID:(NSString*)spaceID
                       browserID:(ClairBrowserID)browserID
                           pinID:(NSString*)pinID
                            name:(NSString*)name;
@end

@implementation ClairChromiumTab
@synthesize tabID = _tabID;
@synthesize title = _title;
@synthesize url = _url;
@synthesize urlText = _urlText;
@synthesize displayHost = _displayHost;
@synthesize isNewTabPage = _isNewTabPage;
@synthesize isNotSecure = _isNotSecure;
@synthesize favicon = _favicon;
@synthesize isLoading = _isLoading;
@synthesize loadProgress = _loadProgress;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize isAudible = _isAudible;
@synthesize isMuted = _isMuted;
@synthesize isCrashed = _isCrashed;
@synthesize indicators = _indicators;
@synthesize infobars = _infobars;
@synthesize peekParentID = _peekParentID;
@synthesize peekID = _peekID;
@synthesize spaceID = _spaceID;
@synthesize browserID = _browserID;
@synthesize pinID = _pinID;
@synthesize name = _name;

- (instancetype)initWithContents:(content::WebContents*)contents
                    peekParentID:(ClairTabID)peekParentID
                          peekID:(ClairTabID)peekID
                         spaceID:(NSString*)spaceID
                       browserID:(ClairBrowserID)browserID
                           pinID:(NSString*)pinID
                            name:(NSString*)name {
  if ((self = [super init])) {
    _peekParentID = peekParentID;
    _peekID = peekID;
    _spaceID = [spaceID copy];
    _browserID = browserID;
    _pinID = [pinID copy];
    _name = [name copy];
    const GURL& url = contents->GetVisibleURL();
    _tabID = clair::TabIDOf(contents);
    _url = url.is_valid() ? net::NSURLWithGURL(url) : nil;
    _urlText = base::SysUTF16ToNSString(url_formatter::FormatUrl(
        url, url_formatter::kFormatUrlOmitNothing, base::UnescapeRule::NORMAL,
        nullptr, nullptr, nullptr));
    _displayHost = url.has_host() ? base::SysUTF16ToNSString(
                                        url_formatter::IDNToUnicode(url.host()))
                                  : nil;
    _isNewTabPage = clair::IsNewTabPageURL(url);
    const security_state::SecurityLevel security_level =
        chrome_security_state::GetSecurityLevel(contents);
    _isNotSecure = security_level == security_state::WARNING ||
                   security_level == security_state::DANGEROUS;
    std::u16string title = contents->GetTitle();
    _title = base::SysUTF16ToNSString(title.empty() ? url_formatter::FormatUrl(url)
                                                    : title);
    if (auto* favicons =
            favicon::ContentFaviconDriver::FromWebContents(contents);
        favicons && favicons->FaviconIsValid()) {
      gfx::Image image = favicons->GetFavicon();
      _favicon = image.IsEmpty() ? nil : image.ToNSImage();
    }
    // Chromium's toolbar and tab strip state (replace-browser-window D1): a
    // frame loading on its own or a same-document navigation doesn't show
    // stop.
    _isLoading = contents->IsLoading() && contents->ShouldShowLoadingUI();
    _loadProgress = contents->GetLoadProgress();
    _canGoBack = contents->GetController().CanGoBack();
    _canGoForward = contents->GetController().CanGoForward();
    auto* audible = RecentlyAudibleHelper::FromWebContents(contents);
    _isAudible = contents->IsCurrentlyAudible() ||
                 (audible && audible->WasRecentlyAudible());
    _isMuted = contents->IsAudioMuted();
    _isCrashed = contents->IsCrashed();
    _indicators = IndicatorsOf(contents);
    NSMutableArray<id<ClairInfobar>>* infobars = [NSMutableArray array];
    if (auto* manager =
            infobars::ContentInfoBarManager::FromWebContents(contents)) {
      for (infobars::InfoBar* infobar : manager->infobars()) {
        if (ConfirmInfoBarDelegate* delegate =
                infobar->delegate()->AsConfirmInfoBarDelegate()) {
          [infobars addObject:[[ClairChromiumInfobar alloc]
                                  initWithInfobar:infobar
                                         delegate:delegate]];
        }
      }
    }
    _infobars = [infobars copy];
  }
  return self;
}
@end

@interface ClairChromiumPin : NSObject <ClairPin>
- (instancetype)initWithPin:(const clair::Pin&)pin
                       tabs:(NSArray<id<ClairTab>>*)tabs
              isAtPinnedURL:(BOOL)isAtPinnedURL;
@end

@implementation ClairChromiumPin
@synthesize pinID = _pinID;
@synthesize isFavorite = _isFavorite;
@synthesize spaceID = _spaceID;
@synthesize profileID = _profileID;
@synthesize url = _url;
@synthesize title = _title;
@synthesize name = _name;
@synthesize icon = _icon;
@synthesize tabID = _tabID;
@synthesize tabs = _tabs;
@synthesize isAtPinnedURL = _isAtPinnedURL;

- (instancetype)initWithPin:(const clair::Pin&)pin
                       tabs:(NSArray<id<ClairTab>>*)tabs
              isAtPinnedURL:(BOOL)isAtPinnedURL {
  if ((self = [super init])) {
    clair::ClairPinStore* store = clair::ClairPinStore::Get();
    _pinID = base::SysUTF8ToNSString(pin.id);
    _isFavorite = pin.container.is_favorites();
    _spaceID = _isFavorite ? nil : base::SysUTF8ToNSString(pin.container.space);
    _profileID = base::SysUTF8ToNSString(store->ProfileOf(pin));
    _url = net::NSURLWithGURL(pin.url) ?: [NSURL URLWithString:@"about:blank"];
    _title = base::SysUTF8ToNSString(pin.title);
    if (_title.length == 0) {
      _title = base::SysUTF16ToNSString(url_formatter::FormatUrl(pin.url));
    }
    _name = pin.name.empty() ? nil : base::SysUTF8ToNSString(pin.name);
    _icon = store->IconOf(pin.id);
    _tabs = [tabs copy] ?: @[];
    _tabID = _tabs.count ? _tabs.firstObject.tabID : ClairTabIDNone;
    _isAtPinnedURL = isAtPinnedURL;
  }
  return self;
}
@end

@interface ClairChromiumSpace : NSObject <ClairSpace>
- (instancetype)initWithSpace:(const clair::Space&)space;
@end

@implementation ClairChromiumSpace
@synthesize spaceID = _spaceID;
@synthesize name = _name;
@synthesize icon = _icon;
@synthesize profileID = _profileID;

- (instancetype)initWithSpace:(const clair::Space&)space {
  if ((self = [super init])) {
    _spaceID = base::SysUTF8ToNSString(space.id);
    _name = base::SysUTF8ToNSString(space.name);
    _icon = space.icon.empty() ? nil : base::SysUTF8ToNSString(space.icon);
    _profileID = base::SysUTF8ToNSString(space.profile);
  }
  return self;
}
@end

// --- Observation ---------------------------------------------------------------

// Tells the lists when a tab's load progress or security state changes, so it
// rides the tab's coalesced push (replace-browser-window D4), and when a bound
// tab's title, icon or URL changes (add-pinned-tabs-and-favorites D2).
class ClairSpaceTabs::ProgressObserver
    : public content::WebContentsObserver,
      public favicon::FaviconDriverObserver {
 public:
  ProgressObserver(ClairSpaceTabs* owner, content::WebContents* contents)
      : content::WebContentsObserver(contents), owner_(owner) {
    if (auto* favicons =
            favicon::ContentFaviconDriver::FromWebContents(contents)) {
      favicon_observation_.Observe(favicons);
    }
  }

  // content::WebContentsObserver:
  void LoadProgressChanged(double progress) override {
    owner_->TabChanged(web_contents());
  }
  void TitleWasSet(content::NavigationEntry* entry) override {
    owner_->BoundTabUpdated(web_contents());
  }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && handle->HasCommitted()) {
      owner_->BoundTabUpdated(web_contents());
    }
  }
  void WebContentsDestroyed() override { favicon_observation_.Reset(); }

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* favicon_driver,
                        NotificationIconType notification_icon_type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override {
    if (notification_icon_type == NON_TOUCH_16_DIP && !image.IsEmpty()) {
      owner_->BoundFaviconUpdated(web_contents(), image.ToNSImage());
    }
  }
  // Mixed content can be found after a load has finished.
  void DidChangeVisibleSecurityState() override {
    owner_->TabChanged(web_contents());
  }
  // D4: the page answered a close, before Chromium acts on the answer.
  void BeforeUnloadFired(bool proceed) override {
    if (ClairBrowserWindow* window =
            ClairBrowserWindow::FromWebContents(web_contents())) {
      window->BeforeUnloadFired(web_contents(), proceed);
    }
  }

 private:
  const raw_ptr<ClairSpaceTabs> owner_;
  base::ScopedObservation<favicon::FaviconDriver,
                          favicon::FaviconDriverObserver>
      favicon_observation_{this};
};

// --- ClairSpaceTabs ------------------------------------------------------------

// static
ClairSpaceTabs* ClairSpaceTabs::ForProfile(Profile* profile) {
  if (!profile) {
    return nullptr;
  }
  if (auto* existing =
          static_cast<ClairSpaceTabs*>(profile->GetUserData(kSpaceTabsKey))) {
    return existing;
  }
  auto owned = std::make_unique<ClairSpaceTabs>(profile);
  ClairSpaceTabs* raw = owned.get();
  profile->SetUserData(kSpaceTabsKey, std::move(owned));
  return raw;
}

// static
ClairSpaceTabs* ClairSpaceTabs::ForWebContents(content::WebContents* contents) {
  if (!contents) {
    return nullptr;
  }
  return static_cast<ClairSpaceTabs*>(
      contents->GetBrowserContext()->GetUserData(kSpaceTabsKey));
}

// static
std::vector<ClairSpaceTabs*> ClairSpaceTabs::All() {
  return std::vector<ClairSpaceTabs*>(Instances().begin(), Instances().end());
}

namespace clair {
namespace {
void FlushPins();
}  // namespace
}  // namespace clair

// static
void ClairSpaceTabs::FlushAll() {
  for (ClairSpaceTabs* tabs : All()) {
    tabs->Flush();
  }
  clair::FlushPins();
}

// static
void ClairSpaceTabs::SetRestoredTag(content::WebContents* contents,
                                    const std::string& space,
                                    std::optional<int> rank) {
  if (!contents || space.empty()) {
    return;
  }
  SpaceTag* tag = EnsureTag(contents);
  tag->space = space;
  tag->rank = rank;
}

// static
void ClairSpaceTabs::SetRestoredWindowTag(content::WebContents* contents,
                                          const std::string& group) {
  if (contents && !group.empty()) {
    EnsureTag(contents)->window = group;
  }
}

// static
std::string ClairSpaceTabs::WindowTag(content::WebContents* contents) {
  SpaceTag* tag = GetTag(contents);
  return tag ? tag->window : std::string();
}

// static
void ClairSpaceTabs::SetRestoredPinTag(content::WebContents* contents,
                                       const std::string& pin,
                                       const std::string& name) {
  if (!contents) {
    return;
  }
  SpaceTag* tag = EnsureTag(contents);
  tag->pin = pin;
  tag->name = name;
  tag->written_pin = pin;
  tag->written_name = name;
}

// static
void ClairSpaceTabs::SetPendingPin(content::WebContents* contents,
                                   const std::string& pin) {
  if (!contents) {
    return;
  }
  SpaceTag* tag = EnsureTag(contents);
  tag->pin = pin;
  // add-spaces D3: a pinned tab's window shows its Space once it's active,
  // which may be before the lists hear of it.
  const clair::Pin* record = clair::ClairPinStore::Get()->Find(pin);
  if (record && !record->container.is_favorites()) {
    tag->space = record->container.space;
  }
}

// static
void ClairSpaceTabs::SetRestoredNewTabWasSelected(
    content::WebContents* contents) {
  if (contents) {
    EnsureTag(contents)->new_tab_was_selected = true;
  }
}

// static
bool ClairSpaceTabs::TakeRestoredNewTabWasSelected(
    content::WebContents* contents) {
  SpaceTag* tag = GetTag(contents);
  if (!tag || !tag->new_tab_was_selected) {
    return false;
  }
  tag->new_tab_was_selected = false;
  return true;
}

// static
std::map<std::string, std::string> ClairSpaceTabs::SessionTags(
    content::WebContents* contents) {
  std::map<std::string, std::string> tags;
  SpaceTag* tag = GetTag(contents);
  ClairSpaceTabs* lists = ForWebContents(contents);
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (!tag || !lists || !lists->is_regular()) {
    return tags;
  }
  // add-pinned-tabs-and-favorites D2: a bound tab carries its pin, and a
  // favorite's tab may have no Space.
  const std::string pin = lists->SessionPinOf(tab);
  if (tag->space.empty() && pin.empty()) {
    return tags;
  }
  if (!tag->space.empty()) {
    int rank = pin.empty() ? tag->written_rank : -1;
    if (auto list = lists->lists_.find(tag->space);
        tab && list != lists->lists_.end()) {
      auto it = std::ranges::find(list->second, tab->GetHandle());
      if (it != list->second.end()) {
        rank = static_cast<int>(it - list->second.begin());
      }
    }
    tags[clair::kSpaceSessionKey] = tag->space;
    if (rank >= 0) {
      tags[clair::kOrderSessionKey] = base::NumberToString(rank);
    }
  }
  if (std::string group = GroupOf(contents); !group.empty()) {
    tags[clair::kWindowSessionKey] = group;
  }
  if (!pin.empty()) {
    tags[clair::kPinSessionKey] = pin;
  }
  if (std::string name = lists->NameOf(tab); !name.empty()) {
    tags[clair::kNameSessionKey] = name;
  }
  return tags;
}

// static
void ClairSpaceTabs::MarkPlaceholder(content::WebContents* contents) {
  if (contents && !IsPlaceholder(contents)) {
    contents->SetUserData(kPlaceholderKey, std::make_unique<PlaceholderMark>());
  }
}

// static
bool ClairSpaceTabs::IsPlaceholder(content::WebContents* contents) {
  return contents && contents->GetUserData(kPlaceholderKey);
}

ClairSpaceTabs::ClairSpaceTabs(Profile* profile) : profile_(profile) {
  if (profile->IsOffTheRecord()) {
    static int next_private_space = 1;
    private_space_ =
        "private-" + base::NumberToString(next_private_space++);
  }
  Instances().insert(this);
  clair::ClairPinStore::Get()->AddObserver(this);
  if (!profile->IsOffTheRecord()) {
    session_restored_subscription_ =
        SessionRestore::RegisterOnSessionRestoredCallback(base::BindRepeating(
            &ClairSpaceTabs::SessionRestored, base::Unretained(this)));
  }
}

ClairSpaceTabs::~ClairSpaceTabs() {
  clair::ClairPinStore::Get()->RemoveObserver(this);
  Instances().erase(this);
  infobar_observations_.RemoveAllObservations();
  progress_observers_.clear();
  for (ClairBrowserWindow* window : windows_) {
    if (window->browser()) {
      window->browser()->tab_strip_model()->RemoveObserver(this);
    }
  }
}

void ClairSpaceTabs::AddBrowser(ClairBrowserWindow* window) {
  if (!window || std::ranges::find(windows_, window) != windows_.end()) {
    return;
  }
  windows_.push_back(window);
  TabStripModel* strip = window->browser()->tab_strip_model();
  strip->AddObserver(this);
  for (int i = 0; i < strip->count(); ++i) {
    Watch(strip->GetWebContentsAt(i));
    Insert(strip, strip->GetTabAtIndex(i), i);
  }
}

void ClairSpaceTabs::RemoveBrowser(ClairBrowserWindow* window) {
  auto it = std::ranges::find(windows_, window);
  if (it == windows_.end()) {
    return;
  }
  windows_.erase(it);
  TabStripModel* strip =
      window->browser() ? window->browser()->tab_strip_model() : nullptr;
  if (!strip) {
    return;
  }
  strip->RemoveObserver(this);
  for (int i = 0; i < strip->count(); ++i) {
    Unwatch(strip->GetWebContentsAt(i));
    Remove(strip->GetTabAtIndex(i));
  }
}

ClairBrowserWindow* ClairSpaceTabs::WindowFor(const TabStripModel* model) const {
  for (ClairBrowserWindow* window : windows_) {
    if (window->browser() && window->browser()->tab_strip_model() == model) {
      return window;
    }
  }
  return nullptr;
}

namespace {

// The tab `peek` is a Peek of, in its window, or null.
tabs::TabInterface* PeekParentOf(const tabs::TabInterface* peek) {
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(peek);
  return holder && holder->peeks() ? holder->peeks()->ParentOf(peek) : nullptr;
}

}  // namespace

std::string ClairSpaceTabs::SpaceOf(const tabs::TabInterface* tab) const {
  if (!tab) {
    return std::string();
  }
  const tabs::TabHandle handle = tab->GetHandle();
  for (const auto& [space, list] : lists_) {
    if (std::ranges::find(list, handle) != list.end()) {
      return space;
    }
  }
  // add-pinned-tabs-and-favorites D2: a pinned tab's is its pin's, and a
  // favorite's tab has none. A bound tab's Peek follows it.
  const tabs::TabInterface* bound = tab;
  std::string pin = PinOf(tab);
  if (pin.empty()) {
    bound = PeekParentOf(tab);
    pin = bound ? PinOf(bound) : std::string();
  }
  const clair::Pin* record =
      pin.empty() ? nullptr : clair::ClairPinStore::Get()->Find(pin);
  return record ? record->container.space : std::string();
}

bool ClairSpaceTabs::IsListed(const tabs::TabInterface* tab) const {
  if (!tab) {
    return false;
  }
  if (!SpaceOf(tab).empty() || !PinOf(tab).empty()) {
    return true;
  }
  const tabs::TabInterface* parent = PeekParentOf(tab);
  return parent && !PinOf(parent).empty();
}

std::string ClairSpaceTabs::PinOf(const tabs::TabInterface* tab) const {
  SpaceTag* tag = tab ? GetTag(tab->GetContents()) : nullptr;
  if (!tag || tag->pin.empty()) {
    return std::string();
  }
  auto found = bound_.find(tag->pin);
  return found != bound_.end() && found->second == tab->GetHandle()
             ? tag->pin
             : std::string();
}

std::string ClairSpaceTabs::SessionPinOf(const tabs::TabInterface* tab) const {
  std::string pin = PinOf(tab);
  if (!pin.empty()) {
    return pin;
  }
  // A tab closing as its pin stays, or after Remove Pin while the pin can
  // come back, keeps it for Reopen Closed Tab.
  SpaceTag* tag = tab ? GetTag(tab->GetContents()) : nullptr;
  if (!tag || tag->pin.empty()) {
    return std::string();
  }
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  return store->WasRemoved(tag->pin) ||
                 (store->Find(tag->pin) && !clair::BoundTabOf(tag->pin))
             ? tag->pin
             : std::string();
}

tabs::TabInterface* ClairSpaceTabs::BoundTab(std::string_view pin) const {
  auto found = bound_.find(std::string(pin));
  return found == bound_.end() ? nullptr : found->second.Get();
}

bool ClairSpaceTabs::IsFavoriteTab(const tabs::TabInterface* tab) const {
  const std::string pin = PinOf(tab);
  const clair::Pin* record =
      pin.empty() ? nullptr : clair::ClairPinStore::Get()->Find(pin);
  return record && record->container.is_favorites();
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::PinnedTabsIn(
    const std::string& space) const {
  std::vector<tabs::TabInterface*> result;
  for (const clair::Pin* pin : clair::ClairPinStore::Get()->PinsIn(
           clair::PinContainer::OfSpace(space))) {
    if (tabs::TabInterface* tab = BoundTab(pin->id)) {
      result.push_back(tab);
    }
  }
  return result;
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::FavoriteTabs() const {
  std::vector<tabs::TabInterface*> result;
  if (!is_regular()) {
    return result;
  }
  for (const clair::Pin* pin :
       clair::ClairPinStore::Get()->PinsIn(clair::PinContainer::OfProfile(
           clair::ClairProfiles::IDOf(profile_)))) {
    if (tabs::TabInterface* tab = BoundTab(pin->id)) {
      result.push_back(tab);
    }
  }
  return result;
}

std::string ClairSpaceTabs::NameOf(const tabs::TabInterface* tab) const {
  const std::string pin = PinOf(tab);
  if (!pin.empty()) {
    const clair::Pin* record = clair::ClairPinStore::Get()->Find(pin);
    return record ? record->name : std::string();
  }
  SpaceTag* tag = tab ? GetTag(tab->GetContents()) : nullptr;
  return tag ? tag->name : std::string();
}

void ClairSpaceTabs::SetName(tabs::TabInterface* tab, const std::string& name) {
  if (!tab || !is_regular()) {
    return;
  }
  std::string cleaned(base::TrimWhitespaceASCII(name, base::TRIM_ALL));
  std::string cut;
  base::TruncateUTF8ToByteSize(cleaned, clair::ClairPinStore::kMaxNameLength,
                               &cut);
  const std::string pin = PinOf(tab);
  if (!pin.empty()) {
    clair::ClairPinStore::Get()->SetName(pin, cut);
    return;
  }
  SpaceTag* tag = EnsureTag(tab->GetContents());
  if (tag->name == cut) {
    return;
  }
  tag->name = cut;
  TabChanged(tab->GetContents());
  // Its session tags are written with its list.
  ListChanged(SpaceOf(tab));
}

bool ClairSpaceTabs::IsAtPinnedURL(const tabs::TabInterface* tab) const {
  const std::string pin = PinOf(tab);
  const clair::Pin* record =
      pin.empty() ? nullptr : clair::ClairPinStore::Get()->Find(pin);
  if (!record) {
    return true;
  }
  content::NavigationEntry* entry =
      tab->GetContents()->GetController().GetLastCommittedEntry();
  if (!entry || entry->IsInitialEntry()) {
    return true;
  }
  // D2: a redirect from the pinned URL counts as being at it.
  return clair::SamePinnedURL(entry->GetURL(), record->url) ||
         clair::SamePinnedURL(entry->GetVirtualURL(), record->url) ||
         clair::SamePinnedURL(entry->GetOriginalRequestURL(), record->url);
}

std::string ClairSpaceTabs::SpaceOf(content::WebContents* contents) const {
  return SpaceOf(contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                          : nullptr);
}

std::string ClairSpaceTabs::IntendedSpaceOf(tabs::TabInterface* tab) const {
  std::string space = SpaceOf(tab);
  if (!space.empty() || !tab || !is_regular()) {
    return space;
  }
  SpaceTag* tag = GetTag(tab->GetContents());
  if (!tag) {
    return std::string();
  }
  // add-pinned-tabs-and-favorites D2: a favorite's tab, bound or about to
  // be, belongs to no Space, and leaves its window's as it is.
  if (!tag->pin.empty()) {
    const clair::Pin* record = clair::ClairPinStore::Get()->Find(tag->pin);
    if (record && record->container.is_favorites() &&
        (PinOf(tab) == tag->pin || !BoundTab(tag->pin))) {
      return std::string();
    }
  }
  return clair::ClairSpaceStore::Get()->Contains(tag->space) ? tag->space
                                                              : std::string();
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::TabsIn(
    const std::string& space) const {
  std::vector<tabs::TabInterface*> result;
  auto list = lists_.find(space);
  if (list == lists_.end()) {
    return result;
  }
  for (const tabs::TabHandle& handle : list->second) {
    if (tabs::TabInterface* tab = handle.Get()) {
      result.push_back(tab);
    }
  }
  return result;
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::TabsIn(
    const std::string& space,
    const Browser* browser) const {
  std::vector<tabs::TabInterface*> result;
  for (tabs::TabInterface* tab : TabsIn(space)) {
    if (tab->GetBrowserWindowInterface() == browser) {
      result.push_back(tab);
    }
  }
  return result;
}

std::vector<std::string> ClairSpaceTabs::SpacesWithTabs() const {
  std::vector<std::string> spaces;
  for (const auto& [space, list] : lists_) {
    if (!list.empty()) {
      spaces.push_back(space);
    }
  }
  return spaces;
}

id<ClairTab> ClairSpaceTabs::Snapshot(content::WebContents* contents) const {
  ClairTabID peek_parent_id = ClairTabIDNone;
  ClairTabID peek_id = ClairTabIDNone;
  ClairBrowserID browser_id = 0;
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(contents)) {
    browser_id = window->browser()->GetSessionID().id();
    if (ClairPeeks* peeks = window->peeks(); peeks && tab) {
      if (tabs::TabInterface* peek = peeks->ShownPeekOf(tab)) {
        peek_id = peek->GetHandle().raw_value();
      }
      if (std::optional<int32_t> parent = peeks->ParentIDOf(tab)) {
        peek_parent_id = *parent;
      }
    }
  }
  const std::string pin = PinOf(tab);
  const std::string name = NameOf(tab);
  return [[ClairChromiumTab alloc]
      initWithContents:contents
          peekParentID:peek_parent_id
                peekID:peek_id
               spaceID:base::SysUTF8ToNSString(SpaceOf(tab))
             browserID:browser_id
                 pinID:pin.empty() ? nil : base::SysUTF8ToNSString(pin)
                  name:name.empty() ? nil : base::SysUTF8ToNSString(name)];
}

id<ClairPin> ClairSpaceTabs::PinSnapshot(const clair::Pin& pin) const {
  NSMutableArray<id<ClairTab>>* tabs = [NSMutableArray array];
  tabs::TabInterface* bound = BoundTab(pin.id);
  if (bound) {
    [tabs addObject:Snapshot(bound->GetContents())];
    ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(bound);
    if (tabs::TabInterface* peek =
            holder && holder->peeks() ? holder->peeks()->PeekOf(bound)
                                      : nullptr) {
      [tabs addObject:Snapshot(peek->GetContents())];
    }
  }
  return [[ClairChromiumPin alloc] initWithPin:pin
                                          tabs:tabs
                                 isAtPinnedURL:!bound || IsAtPinnedURL(bound)];
}

NSArray<id<ClairTab>>* ClairSpaceTabs::Snapshots(const std::string& space) const {
  NSMutableArray<id<ClairTab>>* snapshots = [NSMutableArray array];
  for (tabs::TabInterface* tab : TabsIn(space)) {
    [snapshots addObject:Snapshot(tab->GetContents())];
  }
  return snapshots;
}

// --- Placing tabs (D2) ---

void ClairSpaceTabs::Insert(TabStripModel* model,
                            tabs::TabInterface* tab,
                            int index) {
  if (!tab) {
    return;
  }
  content::WebContents* contents = tab->GetContents();
  Remove(tab);
  ClairBrowserWindow* window = WindowFor(model);
  // share-tabs-across-windows D2: a placeholder, marked before it joined the
  // strip, is in no Space.
  if (IsPlaceholder(contents)) {
    return;
  }
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  SpaceTag* tag = GetTag(contents);
  // add-pinned-tabs-and-favorites D3: a tab restored or opened for a pin
  // binds to it, unless the pin is gone or already has a tab.
  if (is_regular() && tag && !tag->pin.empty()) {
    if (Bind(tab, tag->pin)) {
      return;
    }
    if (!clair::ClairPinStore::Get()->WasRemoved(tag->pin)) {
      tag->pin.clear();
    }
  }
  std::string space;
  std::optional<int> rank;
  if (!is_regular()) {
    space = private_space_;
  } else if (tag && store->Contains(tag->space)) {
    // Restored from a session, or moved from another window.
    space = tag->space;
    rank = tag->rank;
  } else {
    // A new tab joins the Space its window shows (D3). A Peek joins its
    // parent's once it's linked (PeekLinked).
    space = window && store->Contains(window->shown_space())
                ? window->shown_space()
                : store->last_space();
  }
  tag = EnsureTag(contents);
  tag->space = space;
  tag->rank = rank;

  std::vector<tabs::TabHandle>& list = lists_[space];
  size_t at = 0;
  if (rank) {
    // By its saved rank, after the tabs ranked the same: ties keep the
    // strip's order. Tabs listed since the restore count by their index.
    at = list.size();
    for (size_t i = 0; i < list.size(); ++i) {
      tabs::TabInterface* other = list[i].Get();
      SpaceTag* other_tag = other ? GetTag(other->GetContents()) : nullptr;
      const bool after = other_tag && other_tag->rank
                             ? *other_tag->rank > *rank
                             : static_cast<int>(i) >= *rank;
      if (after) {
        at = i;
        break;
      }
    }
  } else if (index > 0) {
    // Directly after the nearest tab before it in the strip that belongs to
    // the same Space, which keeps a Peek being expanded below its parent.
    // At index 0, where clair::NewTabIndex puts new tabs, it goes to the top.
    for (int i = std::min(index, model->count()) - 1; i >= 0; --i) {
      tabs::TabInterface* before = model->GetTabAtIndex(i);
      if (!before || before == tab) {
        continue;
      }
      auto it = std::ranges::find(list, before->GetHandle());
      if (it != list.end()) {
        at = static_cast<size_t>(it - list.begin()) + 1;
        break;
      }
    }
  }
  list.insert(list.begin() + at, tab->GetHandle());
  ListChanged(space);
}

std::string ClairSpaceTabs::Remove(const tabs::TabInterface* tab) {
  std::string space = RemoveFromLists(tab);
  // add-pinned-tabs-and-favorites D2: a bound tab leaving for good leaves its
  // pin in place, unbound.
  Unbind(tab, /*keep_tag=*/true);
  return space;
}

std::string ClairSpaceTabs::RemoveFromLists(const tabs::TabInterface* tab) {
  if (!tab) {
    return std::string();
  }
  const tabs::TabHandle handle = tab->GetHandle();
  for (auto& [space, list] : lists_) {
    if (std::erase(list, handle) > 0) {
      ListChanged(space);
      return space;
    }
  }
  return std::string();
}

// --- Binding (add-pinned-tabs-and-favorites D2 to D5) ---

bool ClairSpaceTabs::Bind(tabs::TabInterface* tab, const std::string& pin) {
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  if (!tab || !is_regular() || ClairSpaceTabs::IsPlaceholder(tab->GetContents())) {
    return false;
  }
  // D3: a tab Restore Last Closed Tab brings back with a removed pin brings
  // the pin back first.
  if (!store->Find(pin) && store->WasRemoved(pin)) {
    store->Restore(pin);
  }
  const clair::Pin* record = store->Find(pin);
  if (!record || store->ProfileOf(*record) != clair::ClairProfiles::IDOf(profile_)) {
    return false;
  }
  if (tabs::TabInterface* bound = BoundTab(pin); bound && bound != tab) {
    return false;
  }
  const std::string old = PinOf(tab);
  if (!old.empty() && old != pin) {
    Unbind(tab, /*keep_tag=*/false);
  }
  content::WebContents* contents = tab->GetContents();
  SpaceTag* tag = EnsureTag(contents);
  // A Peek is in no list while its parent is bound; it follows it.
  for (tabs::TabInterface* member : FamilyOf(tab)) {
    RemoveFromLists(member);
    SpaceTag* member_tag = EnsureTag(member->GetContents());
    if (!record->container.is_favorites()) {
      member_tag->space = record->container.space;
    }
    member_tag->rank.reset();
  }
  bound_[pin] = tab->GetHandle();
  tag->pin = pin;
  // The name moves into the record.
  if (!tag->name.empty()) {
    if (record->name.empty()) {
      store->SetName(pin, tag->name);
    }
    tag->name.clear();
  }
  changed_bound_.insert(tab->GetHandle());
  clair::PinsChanged(record->container);
  TabChanged(contents);
  PostFlush();
  return true;
}

void ClairSpaceTabs::Unbind(const tabs::TabInterface* tab, bool keep_tag) {
  const std::string pin = PinOf(tab);
  if (pin.empty()) {
    return;
  }
  bound_.erase(pin);
  changed_bound_.erase(tab->GetHandle());
  if (!keep_tag) {
    EnsureTag(tab->GetContents())->pin.clear();
  }
  if (const clair::Pin* record = clair::ClairPinStore::Get()->Find(pin)) {
    clair::PinsChanged(record->container);
  }
}

void ClairSpaceTabs::ListInToday(tabs::TabInterface* tab,
                                 const std::string& space,
                                 int index) {
  if (!tab || space.empty()) {
    return;
  }
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* member : FamilyOf(tab)) {
    RemoveFromLists(member);
    SpaceTag* tag = EnsureTag(member->GetContents());
    tag->space = space;
    tag->rank.reset();
    handles.push_back(member->GetHandle());
  }
  std::vector<tabs::TabHandle>& list = lists_[space];
  const size_t at = static_cast<size_t>(
      std::clamp(index, 0, static_cast<int>(list.size())));
  list.insert(list.begin() + at, handles.begin(), handles.end());
  ListChanged(space);
  TabChanged(tab->GetContents());
}

std::string ClairSpaceTabs::FallbackSpaceFor(tabs::TabInterface* tab) const {
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  const std::string profile = clair::ClairProfiles::IDOf(profile_);
  SpaceTag* tag = tab ? GetTag(tab->GetContents()) : nullptr;
  if (tag && store->Contains(tag->space) && store->ProfileOf(tag->space) == profile) {
    return tag->space;
  }
  if (ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab);
      holder && store->Contains(holder->shown_space())) {
    return holder->shown_space();
  }
  for (const clair::Space& space : store->spaces()) {
    if (space.profile == profile) {
      return space.id;
    }
  }
  return store->last_space();
}

std::string ClairSpaceTabs::PinTab(tabs::TabInterface* tab,
                                   const clair::PinContainer& container,
                                   size_t index) {
  if (!tab || !is_regular() || !PinOf(tab).empty() || SpaceOf(tab).empty() ||
      PeekParentOf(tab)) {
    return std::string();
  }
  content::WebContents* contents = tab->GetContents();
  content::NavigationEntry* entry =
      contents->GetController().GetLastCommittedEntry();
  const GURL url = entry && !entry->IsInitialEntry() ? entry->GetURL()
                                                      : contents->GetVisibleURL();
  SpaceTag* tag = EnsureTag(contents);
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  const std::string pin =
      store->Create(container, index, url, base::UTF16ToUTF8(contents->GetTitle()),
                    tag->name);
  if (pin.empty()) {
    return pin;
  }
  if (auto* favicons = favicon::ContentFaviconDriver::FromWebContents(contents);
      favicons && favicons->FaviconIsValid()) {
    gfx::Image image = favicons->GetFavicon();
    if (!image.IsEmpty()) {
      store->SetIcon(pin, image.ToNSImage());
    }
  }
  tag->name.clear();
  Bind(tab, pin);
  return pin;
}

void ClairSpaceTabs::UnbindToToday(tabs::TabInterface* tab,
                                   const std::string& space,
                                   int index) {
  const std::string pin = PinOf(tab);
  if (pin.empty()) {
    return;
  }
  const clair::Pin* record = clair::ClairPinStore::Get()->Find(pin);
  const std::string name = record ? record->name : std::string();
  Unbind(tab, /*keep_tag=*/false);
  EnsureTag(tab->GetContents())->name = name;
  ListInToday(tab, space, index);
  changed_bound_.erase(tab->GetHandle());
}

void ClairSpaceTabs::UnbindForReopen(tabs::TabInterface* tab) {
  Unbind(tab, /*keep_tag=*/false);
}

void ClairSpaceTabs::PeekExpanded(tabs::TabInterface* peek,
                                  const std::string& space) {
  if (!peek || !is_regular() || IsListed(peek)) {
    return;
  }
  // D7: at the top of Today, as any new tab.
  ListInToday(peek, space, 0);
}

void ClairSpaceTabs::OnPinsChanged(const clair::PinContainer& container) {
  if (!is_regular()) {
    return;
  }
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  const std::string profile = clair::ClairProfiles::IDOf(profile_);
  std::vector<std::pair<std::string, tabs::TabHandle>> bound(bound_.begin(),
                                                             bound_.end());
  for (const auto& [pin, handle] : bound) {
    tabs::TabInterface* tab = handle.Get();
    const clair::Pin* record = store->Find(pin);
    if (!tab) {
      bound_.erase(pin);
      continue;
    }
    if (!record) {
      // D3, D9: the pin was removed; its tab, unless it's closing, joins a
      // Space's Today tabs. It keeps the pin in its tag while Restore Last
      // Closed Tab can bring it back.
      Unbind(tab, /*keep_tag=*/true);
      ListInToday(tab, FallbackSpaceFor(tab), 0);
      continue;
    }
    if (store->ProfileOf(*record) != profile) {
      // D5: it moved to another profile, which reopens the tab there; this
      // one closes.
      continue;
    }
    // It may have moved between a Space and the favorites, or between
    // Spaces, or changed its name.
    for (tabs::TabInterface* member : FamilyOf(tab)) {
      if (!record->container.is_favorites()) {
        EnsureTag(member->GetContents())->space = record->container.space;
      }
    }
    changed_bound_.insert(handle);
    TabChanged(tab->GetContents());
  }
  PostFlush();
}

void ClairSpaceTabs::BoundChanged(const tabs::TabInterface* tab) {
  const std::string pin = PinOf(tab);
  const clair::Pin* record =
      pin.empty() ? nullptr : clair::ClairPinStore::Get()->Find(pin);
  if (record) {
    clair::PinsChanged(record->container);
  }
}

void ClairSpaceTabs::BoundTabUpdated(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  const std::string pin = PinOf(tab);
  if (pin.empty()) {
    return;
  }
  // D2: the pin's title follows its page only at the pinned URL.
  if (IsAtPinnedURL(tab) && !contents->GetTitle().empty()) {
    clair::ClairPinStore::Get()->SetTitle(pin,
                                          base::UTF16ToUTF8(contents->GetTitle()));
  }
  BoundChanged(tab);
}

void ClairSpaceTabs::BoundFaviconUpdated(content::WebContents* contents,
                                         NSImage* icon) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  const std::string pin = PinOf(tab);
  if (pin.empty() || !icon || !IsAtPinnedURL(tab)) {
    return;
  }
  clair::ClairPinStore::Get()->SetIcon(pin, icon);
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::FamilyOf(
    tabs::TabInterface* tab) const {
  std::vector<tabs::TabInterface*> family{tab};
  ClairBrowserWindow* window =
      tab ? ClairBrowserWindow::FromWebContents(tab->GetContents()) : nullptr;
  if (window && window->peeks()) {
    if (tabs::TabInterface* peek = window->peeks()->PeekOf(tab)) {
      family.push_back(peek);
    }
  }
  return family;
}

std::vector<tabs::TabHandle> ClairSpaceTabs::TakeFamily(
    std::vector<tabs::TabHandle>& list,
    tabs::TabInterface* tab) const {
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* member : FamilyOf(tab)) {
    handles.push_back(member->GetHandle());
  }
  std::erase_if(list, [&handles](const tabs::TabHandle& handle) {
    return std::ranges::find(handles, handle) != handles.end();
  });
  return handles;
}

void ClairSpaceTabs::MoveTab(tabs::TabInterface* tab, int index) {
  const std::string space = SpaceOf(tab);
  if (space.empty()) {
    return;
  }
  std::vector<tabs::TabHandle>& list = lists_[space];
  const std::vector<tabs::TabHandle> handles = TakeFamily(list, tab);
  const size_t at = static_cast<size_t>(
      std::clamp(index, 0, static_cast<int>(list.size())));
  list.insert(list.begin() + at, handles.begin(), handles.end());
  ListChanged(space);
}

void ClairSpaceTabs::MoveTabBeside(tabs::TabInterface* tab,
                                   tabs::TabInterface* anchor,
                                   bool after) {
  const std::string space = SpaceOf(tab);
  if (space.empty() || !anchor || anchor == tab || SpaceOf(anchor) != space) {
    return;
  }
  // The anchor's Peek directly follows it, so after the anchor is after its
  // Peek.
  const tabs::TabHandle beside =
      (after ? FamilyOf(anchor).back() : anchor)->GetHandle();
  std::vector<tabs::TabHandle>& list = lists_[space];
  const std::vector<tabs::TabHandle> handles = TakeFamily(list, tab);
  auto it = std::ranges::find(list, beside);
  if (it != list.end() && after) {
    ++it;
  }
  list.insert(it, handles.begin(), handles.end());
  ListChanged(space);
}

void ClairSpaceTabs::SetSpace(tabs::TabInterface* tab,
                              const std::string& space) {
  if (!tab || !is_regular() ||
      !clair::ClairSpaceStore::Get()->Contains(space) || SpaceOf(tab) == space) {
    return;
  }
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* member : FamilyOf(tab)) {
    Remove(member);
    SpaceTag* tag = EnsureTag(member->GetContents());
    tag->space = space;
    tag->rank.reset();
    handles.push_back(member->GetHandle());
  }
  std::vector<tabs::TabHandle>& list = lists_[space];
  list.insert(list.begin(), handles.begin(), handles.end());
  ListChanged(space);
}

void ClairSpaceTabs::PeekLinked(tabs::TabInterface* parent,
                                tabs::TabInterface* peek) {
  if (!peek) {
    return;
  }
  // add-pinned-tabs-and-favorites D2: a bound tab's Peek is in no list; it
  // comes with its pin.
  if (!PinOf(parent).empty()) {
    RemoveFromLists(peek);
    if (std::string space = SpaceOf(parent); !space.empty()) {
      EnsureTag(peek->GetContents())->space = space;
    }
    BoundChanged(parent);
    return;
  }
  const std::string space = SpaceOf(parent);
  if (space.empty()) {
    return;
  }
  Remove(peek);
  EnsureTag(peek->GetContents())->space = space;
  std::vector<tabs::TabHandle>& list = lists_[space];
  auto it = std::ranges::find(list, parent->GetHandle());
  list.insert(it == list.end() ? list.end() : it + 1, peek->GetHandle());
  ListChanged(space);
}

void ClairSpaceTabs::SpaceRemoved(const std::string& space,
                                  const std::string& fallback) {
  auto found = lists_.find(space);
  if (found == lists_.end()) {
    return;
  }
  std::vector<tabs::TabHandle> left = std::move(found->second);
  lists_.erase(found);
  changed_spaces_.erase(space);
  std::vector<tabs::TabHandle> moved;
  for (const tabs::TabHandle& handle : left) {
    if (tabs::TabInterface* tab = handle.Get()) {
      EnsureTag(tab->GetContents())->space = fallback;
      moved.push_back(handle);
    }
  }
  if (moved.empty()) {
    return;
  }
  std::vector<tabs::TabHandle>& list = lists_[fallback];
  list.insert(list.begin(), moved.begin(), moved.end());
  ListChanged(fallback);
}

// --- Moving between windows (share-tabs-across-windows D1, D2) ---

void ClairSpaceTabs::BeginMove(tabs::TabInterface* tab) {
  if (tab) {
    moving_.insert(tab->GetHandle());
  }
}

void ClairSpaceTabs::EndMove(tabs::TabInterface* tab) {
  if (!tab) {
    return;
  }
  moving_.erase(tab->GetHandle());
  // Its `browserID` changed, and the session holds it under another window.
  if (SpaceTag* tag = GetTag(tab->GetContents())) {
    tag->written_space.clear();
    tag->written_rank = -1;
    tag->written_window.clear();
    tag->written_pin.reset();
    tag->written_name.reset();
  }
  if (!PinOf(tab).empty()) {
    changed_bound_.insert(tab->GetHandle());
    BoundChanged(tab);
    PostFlush();
  } else if (tabs::TabInterface* parent = PeekParentOf(tab);
             parent && !PinOf(parent).empty()) {
    BoundChanged(parent);
  }
  ListChanged(SpaceOf(tab));
}

void ClairSpaceTabs::ListPlaceholder(TabStripModel* model,
                                     tabs::TabInterface* tab) {
  if (!tab) {
    return;
  }
  tab->GetContents()->RemoveUserData(kPlaceholderKey);
  // Index 0 puts it at the top of the shown Space's list.
  Insert(model, tab, 0);
}

// --- Pushes (D9) ---

void ClairSpaceTabs::ListChanged(const std::string& space) {
  if (space.empty()) {
    return;
  }
  changed_spaces_.insert(space);
  PostFlush();
}

void ClairSpaceTabs::AllListsChanged() {
  for (const auto& [pin, handle] : bound_) {
    if (tabs::TabInterface* tab = handle.Get()) {
      if (SpaceTag* tag = GetTag(tab->GetContents())) {
        tag->written_window.clear();
      }
      changed_bound_.insert(handle);
    }
  }
  PostFlush();
  for (const auto& [space, list] : lists_) {
    for (const tabs::TabHandle& handle : list) {
      if (tabs::TabInterface* tab = handle.Get()) {
        if (SpaceTag* tag = GetTag(tab->GetContents())) {
          tag->written_window.clear();
        }
      }
    }
    ListChanged(space);
  }
}

void ClairSpaceTabs::TabChanged(content::WebContents* contents) {
  const ClairTabID tab_id = clair::TabIDOf(contents);
  if (tab_id == ClairTabIDNone) {
    return;
  }
  changed_tabs_.insert(static_cast<int32_t>(tab_id));
  PostFlush();
}

void ClairSpaceTabs::PostFlush() {
  if (flush_posted_) {
    return;
  }
  flush_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&ClairSpaceTabs::Flush, weak_factory_.GetWeakPtr()));
}

void ClairSpaceTabs::Flush() {
  flush_posted_ = false;
  std::set<std::string> spaces = std::move(changed_spaces_);
  changed_spaces_.clear();
  std::set<int32_t> changed = std::move(changed_tabs_);
  changed_tabs_.clear();
  for (const std::string& space : spaces) {
    // Handles of tabs that went without a removal, as at shutdown.
    if (auto list = lists_.find(space); list != lists_.end()) {
      std::erase_if(list->second, [](const tabs::TabHandle& handle) {
        return !handle.Get();
      });
    }
    if (is_regular()) {
      WriteSessionTags(space);
    }
    clair::NotifyTabsInSpace(space);
  }
  std::set<tabs::TabHandle> bound = std::move(changed_bound_);
  changed_bound_.clear();
  if (SessionService* service =
          is_regular() ? SessionServiceFactory::GetForProfileIfExisting(profile_)
                       : nullptr) {
    for (const tabs::TabHandle& handle : bound) {
      tabs::TabInterface* tab = handle.Get();
      if (tab && !PinOf(tab).empty()) {
        SpaceTag* tag = EnsureTag(tab->GetContents());
        WriteTabTags(tab, service, tag->space, /*rank=*/-1);
      }
    }
  }
  for (int32_t raw : changed) {
    tabs::TabInterface* tab = tabs::TabHandle(raw).Get();
    if (tab && IsListed(tab)) {
      clair::NotifyTab(Snapshot(tab->GetContents()));
    }
  }
}

// --- Sessions (D6) ---

void ClairSpaceTabs::WriteSessionTags(const std::string& space) {
  auto list = lists_.find(space);
  if (list == lists_.end()) {
    return;
  }
  SessionService* service =
      SessionServiceFactory::GetForProfileIfExisting(profile_);
  // Restored ranks have done their work once the list is written, unless
  // session restore is still creating windows: a later window's tabs find
  // their places among these by comparing ranks, which skip the new tab pages
  // and Peeks it dropped, so they can't be compared with indexes here.
  const bool restoring = SessionRestore::IsRestoring(profile_);
  int index = 0;
  for (const tabs::TabHandle& handle : list->second) {
    tabs::TabInterface* tab = handle.Get();
    if (!tab) {
      continue;
    }
    if (!restoring) {
      EnsureTag(tab->GetContents())->rank.reset();
    }
    WriteTabTags(tab, service, space, index);
    ++index;
  }
}

void ClairSpaceTabs::SessionRestored(Profile* profile, int tab_count) {
  if (profile != profile_) {
    return;
  }
  for (const auto& [space, list] : lists_) {
    for (const tabs::TabHandle& handle : list) {
      if (tabs::TabInterface* tab = handle.Get()) {
        EnsureTag(tab->GetContents())->rank.reset();
      }
    }
  }
}

void ClairSpaceTabs::WriteTabTags(tabs::TabInterface* tab,
                                  SessionService* service,
                                  const std::string& space,
                                  int rank) {
  content::WebContents* contents = tab->GetContents();
  SpaceTag* tag = EnsureTag(contents);
  BrowserWindowInterface* browser = tab->GetBrowserWindowInterface();
  const std::string group = GroupOf(contents);
  // add-pinned-tabs-and-favorites D2, D3: its pin and its name.
  const std::string pin = SessionPinOf(tab);
  const std::string name = NameOf(tab);
  if (!service || !browser ||
      (tag->written_space == space && tag->written_rank == rank &&
       tag->written_window == group && tag->written_pin == pin &&
       tag->written_name == name)) {
    return;
  }
  const SessionID window_id = browser->GetSessionID();
  const SessionID tab_id = sessions::SessionTabHelper::IdForTab(contents);
  if (!window_id.is_valid() || !tab_id.is_valid()) {
    return;
  }
  if (!space.empty()) {
    service->AddTabExtraData(window_id, tab_id, clair::kSpaceSessionKey, space);
  }
  if (rank >= 0) {
    service->AddTabExtraData(window_id, tab_id, clair::kOrderSessionKey,
                             base::NumberToString(rank));
  }
  if (!group.empty()) {
    service->AddTabExtraData(window_id, tab_id, clair::kWindowSessionKey,
                             group);
  }
  // Written even when empty, so an unpinned or unnamed tab doesn't come back
  // with what it had.
  service->AddTabExtraData(window_id, tab_id, clair::kPinSessionKey, pin);
  service->AddTabExtraData(window_id, tab_id, clair::kNameSessionKey, name);
  tag->written_space = space;
  tag->written_rank = rank;
  tag->written_window = group;
  tag->written_pin = pin;
  tag->written_name = name;
}

// --- TabStripModelObserver ---

void ClairSpaceTabs::OnTabStripModelChanged(
    TabStripModel* model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  switch (change.type()) {
    case TabStripModelChange::kInserted:
      for (const auto& inserted : change.GetInsert()->contents) {
        Watch(inserted.contents);
        // share-tabs-across-windows D1: a tab Clair moves keeps its place.
        if (inserted.tab && moving_.contains(inserted.tab->GetHandle())) {
          continue;
        }
        Insert(model, inserted.tab, inserted.index);
      }
      break;
    case TabStripModelChange::kRemoved:
      // A tab moving to another window comes back with its tag (D2).
      for (const auto& removed : change.GetRemove()->contents) {
        if (removed.tab && moving_.contains(removed.tab->GetHandle())) {
          continue;
        }
        Unwatch(removed.contents);
        Remove(removed.tab);
        // share-tabs-across-windows D2: a window showing a still of the tab
        // shows its placeholder as a new tab page.
        if (removed.remove_reason == TabRemovedReason::kDeleted &&
            removed.tab) {
          const tabs::TabHandle handle = removed.tab->GetHandle();
          for (ClairBrowserWindow* window : windows_) {
            if (window->still_tab() == handle) {
              window->StillTabClosed();
            }
          }
        }
      }
      break;
    case TabStripModelChange::kReplaced: {
      const TabStripModelChange::Replace* replace = change.GetReplace();
      Unwatch(replace->old_contents);
      Watch(replace->new_contents);
      // The tab keeps its handle; its Space moves to the new contents.
      if (SpaceTag* old_tag = GetTag(replace->old_contents)) {
        SpaceTag* new_tag = EnsureTag(replace->new_contents);
        new_tag->space = old_tag->space;
        new_tag->rank = old_tag->rank;
        new_tag->pin = old_tag->pin;
        new_tag->name = old_tag->name;
      }
      ListChanged(SpaceOf(replace->tab));
      BoundChanged(replace->tab);
      break;
    }
    case TabStripModelChange::kMoved:
    case TabStripModelChange::kSelectionOnly:
      // The strip's order means nothing to the user (D2).
      break;
  }
}

void ClairSpaceTabs::OnTabChangedAt(tabs::TabInterface* tab,
                                    TabChangeType change_type) {
  TabChanged(tab->GetContents());
}

void ClairSpaceTabs::OnTabStripModelDestroyed(TabStripModel* model) {
  std::erase_if(windows_, [model](ClairBrowserWindow* window) {
    return !window->browser() || window->browser()->tab_strip_model() == model;
  });
}

// --- Infobars and progress ---

void ClairSpaceTabs::Watch(content::WebContents* contents) {
  if (!contents) {
    return;
  }
  auto* manager = infobars::ContentInfoBarManager::FromWebContents(contents);
  if (manager && !infobar_observations_.IsObservingSource(manager)) {
    infobar_observations_.AddObservation(manager);
  }
  if (std::ranges::none_of(progress_observers_, [contents](const auto& observer) {
        return observer->web_contents() == contents;
      })) {
    progress_observers_.push_back(
        std::make_unique<ProgressObserver>(this, contents));
  }
}

void ClairSpaceTabs::Unwatch(content::WebContents* contents) {
  if (!contents) {
    return;
  }
  auto* manager = infobars::ContentInfoBarManager::FromWebContents(contents);
  if (manager && infobar_observations_.IsObservingSource(manager)) {
    infobar_observations_.RemoveObservation(manager);
  }
  std::erase_if(progress_observers_, [contents](const auto& observer) {
    return observer->web_contents() == contents;
  });
}

void ClairSpaceTabs::InfobarChanged(infobars::InfoBar* infobar) {
  if (content::WebContents* contents =
          infobars::ContentInfoBarManager::WebContentsFromInfoBar(infobar)) {
    TabChanged(contents);
  }
}

void ClairSpaceTabs::OnInfoBarAdded(infobars::InfoBar* infobar) {
  if (!infobar->delegate()->AsConfirmInfoBarDelegate()) {
    // replace-browser-window D8: only confirm infobars have a native bar.
    // Others are logged and dismissed once the manager has finished adding
    // this one.
    LOG(WARNING) << "Clair: dismissing an infobar the native window can't "
                    "show (identifier "
                 << static_cast<int>(infobar->delegate()->GetIdentifier())
                 << ")";
    // Its tab may close, taking the infobar and its manager, before then.
    base::WeakPtr<infobars::InfoBar> weak_infobar = infobar->AsWeakPtr();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak_infobar && weak_infobar->owner()) {
        weak_infobar->RemoveSelf();
      }
    });
    return;
  }
  InfobarChanged(infobar);
}

void ClairSpaceTabs::OnInfoBarRemoved(infobars::InfoBar* infobar,
                                      bool animate) {
  InfobarChanged(infobar);
}

void ClairSpaceTabs::OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                                       infobars::InfoBar* new_infobar) {
  InfobarChanged(new_infobar);
}

void ClairSpaceTabs::OnManagerWillBeDestroyed(
    infobars::InfoBarManager* manager) {
  if (infobar_observations_.IsObservingSource(manager)) {
    infobar_observations_.RemoveObservation(manager);
  }
}

// --- The host's Space calls (D7, D9) ----------------------------------------

namespace clair {

namespace {

NSHashTable<id<ClairSpacesObserver>>* Observers() {
  static NSHashTable<id<ClairSpacesObserver>>* observers =
      [NSHashTable weakObjectsHashTable];
  return observers;
}

// add-pinned-tabs-and-favorites D10: pushes each container's pins once per
// run-loop turn, after the tab lists.
class PinPusher : public ClairPinStore::Observer {
 public:
  static PinPusher* Get() {
    static base::NoDestructor<PinPusher> pusher;
    return pusher.get();
  }

  PinPusher() { ClairPinStore::Get()->AddObserver(this); }

  void Changed(const PinContainer& container) {
    pending_.insert(container);
    if (posted_) {
      return;
    }
    posted_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([] { PinPusher::Get()->Flush(); }));
  }

  void Flush() {
    posted_ = false;
    std::set<PinContainer> pending = std::move(pending_);
    pending_.clear();
    for (const PinContainer& container : pending) {
      NSArray<id<ClairPin>>* pins = PinSnapshots(container);
      for (id<ClairSpacesObserver> observer in Observers().allObjects) {
        if (container.is_favorites()) {
          [observer favoritesDidChange:pins
                             ofProfile:base::SysUTF8ToNSString(container.profile)];
        } else {
          [observer pinsDidChange:pins
                          inSpace:base::SysUTF8ToNSString(container.space)];
        }
      }
    }
  }

  // ClairPinStore::Observer:
  void OnPinsChanged(const PinContainer& container) override {
    Changed(container);
  }

 private:
  std::set<PinContainer> pending_;
  bool posted_ = false;
};

void FlushPins() {
  PinPusher::Get()->Flush();
}

// Tells the observers when the store changes.
class StoreWatcher : public ClairSpaceStore::Observer {
 public:
  StoreWatcher() { ClairSpaceStore::Get()->AddObserver(this); }

  // ClairSpaceStore::Observer:
  void OnSpacesChanged() override {
    KeepLastUsedProfileOnASpace();
    NSArray<id<ClairSpace>>* spaces = SpaceSnapshots();
    for (id<ClairSpacesObserver> observer in Observers().allObjects) {
      [observer spacesDidChange:spaces];
    }
  }
};

}  // namespace

ClairTabID TabIDOf(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  return tab ? tab->GetHandle().raw_value() : ClairTabIDNone;
}

NSInteger InfobarIDOf(const infobars::InfoBar* infobar) {
  return reinterpret_cast<NSInteger>(infobar);
}

void AddSpacesObserver(id<ClairSpacesObserver> observer) {
  static base::NoDestructor<StoreWatcher> watcher;
  PinPusher::Get();
  ClairProfiles::Get()->Start();
  [Observers() addObject:observer];
}

void NotifyProfiles(NSArray<id<ClairProfile>>* profiles) {
  for (id<ClairSpacesObserver> observer in Observers().allObjects) {
    [observer profilesDidChange:profiles];
  }
}

void KeepLastUsedProfileOnASpace() {
  ProfileManager* manager = g_browser_process->profile_manager();
  if (!manager) {
    return;
  }
  ClairSpaceStore* store = ClairSpaceStore::Get();
  const std::string last_used =
      manager->GetLastUsedProfileDir().BaseName().AsUTF8Unsafe();
  if (store->SpaceCountOf(last_used) > 0) {
    return;
  }
  const std::string profile = store->ProfileOf(store->last_space());
  if (!profile.empty()) {
    profiles::SetLastUsedProfile(base::FilePath::FromUTF8Unsafe(profile));
  }
}

NSArray<id<ClairSpace>>* SpaceSnapshots() {
  NSMutableArray<id<ClairSpace>>* spaces = [NSMutableArray array];
  for (const Space& space : ClairSpaceStore::Get()->spaces()) {
    [spaces addObject:[[ClairChromiumSpace alloc] initWithSpace:space]];
  }
  return spaces;
}

NSArray<id<ClairTab>>* TabsInSpace(const std::string& space) {
  NSMutableArray<id<ClairTab>>* tabs = [NSMutableArray array];
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    [tabs addObjectsFromArray:lists->Snapshots(space)];
  }
  return tabs;
}

void NotifyTabsInSpace(const std::string& space) {
  if (Observers().count == 0) {
    return;
  }
  NSArray<id<ClairTab>>* tabs = TabsInSpace(space);
  NSString* space_id = base::SysUTF8ToNSString(space);
  for (id<ClairSpacesObserver> observer in Observers().allObjects) {
    [observer tabsDidChange:tabs inSpace:space_id];
  }
}

void NotifyTab(id<ClairTab> tab) {
  for (id<ClairSpacesObserver> observer in Observers().allObjects) {
    [observer tabDidChange:tab];
  }
}

namespace {

// Closes the tabs of a deleted Space in every window, each with its
// leave-page confirmation, and removes it (D7).
void CloseTabsOfDeletedSpace(const std::string& space,
                             const std::string& neighbour) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  if (!store->Contains(space)) {
    return;
  }
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    if (!lists->is_regular()) {
      continue;
    }
    std::vector<tabs::TabHandle> handles;
    for (tabs::TabInterface* tab : lists->PinnedTabsIn(space)) {
      handles.push_back(tab->GetHandle());
    }
    for (tabs::TabInterface* tab : lists->TabsIn(space)) {
      handles.push_back(tab->GetHandle());
    }
    for (const tabs::TabHandle& handle : handles) {
      tabs::TabInterface* tab = handle.Get();
      ClairBrowserWindow* window =
          tab ? ClairBrowserWindow::FromWebContents(tab->GetContents())
              : nullptr;
      TabStripModel* strip =
          window ? window->browser()->tab_strip_model() : nullptr;
      const int strip_index =
          strip ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
      if (strip_index != TabStripModel::kNoTab) {
        strip->CloseWebContentsAt(
            strip_index, TabCloseTypes::CLOSE_USER_GESTURE |
                             TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
      }
    }
  }
  if (store->last_space() == space) {
    store->SetLastSpace(neighbour);
  }
  if (store->Remove(space)) {
    for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
      lists->SpaceRemoved(space, neighbour);
    }
    // add-pinned-tabs-and-favorites D9: its pinned tabs go, for good; a tab
    // still bound to one, as one whose leave-page confirmation is up, joins
    // the neighbour's Today tabs.
    ClairPinStore::Get()->RemoveContainer(PinContainer::OfSpace(space));
  }
}

// add-profiles D9: opens `url` as a tab of `space`, at `rank` in its list, in
// `window`'s strip, without activating it.
tabs::TabInterface* OpenTabInSpace(ClairBrowserWindow* window,
                                   const GURL& url,
                                   const std::string& space,
                                   int rank,
                                   const std::string& pin = std::string(),
                                   const std::string& name = std::string()) {
  Profile* profile = window->browser()->GetProfile();
  std::unique_ptr<content::WebContents> contents =
      content::WebContents::Create(content::WebContents::CreateParams(profile));
  // Its Space and place, before it joins the strip, as a restored tab's, and
  // the pin it's bound to (add-pinned-tabs-and-favorites D5).
  ClairSpaceTabs::SetRestoredTag(contents.get(), space, rank);
  if (!pin.empty() || !name.empty()) {
    ClairSpaceTabs::SetRestoredPinTag(contents.get(), pin, name);
  }
  contents->GetController().LoadURL(
      url.is_valid() ? url : GURL(chrome::kChromeUINewTabURL),
      content::Referrer(), ui::PAGE_TRANSITION_AUTO_TOPLEVEL, std::string());
  content::WebContents* raw = contents.get();
  TabStripModel* strip = window->browser()->tab_strip_model();
  strip->InsertWebContentsAt(strip->count(), std::move(contents),
                             AddTabTypes::ADD_NONE);
  return tabs::TabInterface::MaybeGetFromContents(raw);
}

// add-profiles D9: closes `row` and its Peek at once, without their pages
// asking before leaving. A window with a still of it shows a new tab page
// (share-tabs-across-windows D2).
void CloseReopened(tabs::TabHandle handle) {
  tabs::TabInterface* row = handle.Get();
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
  if (!row || !holder) {
    return;
  }
  for (ClairBrowserWindow* window : ClairBrowserWindow::All()) {
    window->DropPendingTakeOf(row);
  }
  TabStripModel* strip = holder->browser()->tab_strip_model();
  std::vector<tabs::TabHandle> family;
  if (holder->peeks()) {
    if (tabs::TabInterface* peek = holder->peeks()->PeekOf(row)) {
      family.push_back(peek->GetHandle());
    }
  }
  family.push_back(handle);
  for (const tabs::TabHandle& member : family) {
    tabs::TabInterface* tab = member.Get();
    const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
    if (index != TabStripModel::kNoTab) {
      strip->DetachAndDeleteWebContentsAt(index);
    }
  }
}

// add-profiles D9: each group showing `space` on a member of another profile
// than the Space's switches to its member for the Space's profile.
void SwapGroupsShowing(const std::string& space) {
  const std::string profile = ClairSpaceStore::Get()->ProfileOf(space);
  for (ClairWindowGroup* group : ClairWindowGroup::RegularByActivation()) {
    ClairBrowserWindow* shown = group->shown();
    if (shown && group->shown_space() == space &&
        ClairProfiles::IDOf(shown->browser()->GetProfile()) != profile) {
      group->ShowSpace(space);
    }
  }
}

// add-profiles D9: reopens each of `rows`, in order, as a tab of `space` in
// its window group's member for the Space's profile, from `first_rank` on,
// and closes the originals. In a window that showed one of them, the tab
// reopened from it becomes active, and the group shows its member.
void ReopenInProfile(std::vector<tabs::TabHandle> rows,
                     const std::string& space,
                     int first_rank) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  const std::string profile = store->ProfileOf(space);
  ClairProfiles::Get()->Load(
      profile,
      base::BindOnce(
          [](std::vector<tabs::TabHandle> rows, std::string space,
             int first_rank, Profile* loaded) {
            if (!loaded || !ClairSpaceStore::Get()->Contains(space)) {
              return;
            }
            const std::string profile = ClairProfiles::IDOf(loaded);
            int rank = first_rank;
            for (const tabs::TabHandle& handle : rows) {
              tabs::TabInterface* row = handle.Get();
              ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
              ClairWindowGroup* group =
                  holder ? ClairWindowGroup::Of(holder) : nullptr;
              if (!row || !group) {
                continue;
              }
              const bool shown =
                  holder->IsActiveRow(row) && !holder->IsHiddenMember();
              const std::string previous = group->shown_space();
              const GURL url = row->GetContents()->GetVisibleURL();
              const int this_rank = rank++;
              // add-pinned-tabs-and-favorites D5: a bound tab reopens bound
              // to its pin, and a tab keeps its name.
              ClairSpaceTabs* lists =
                  ClairSpaceTabs::ForWebContents(row->GetContents());
              const std::string pin =
                  lists ? lists->PinOf(row) : std::string();
              const std::string name =
                  lists && pin.empty() ? lists->NameOf(row) : std::string();
              // The profile is loaded, so the member comes at once.
              group->EnsureMember(
                  profile,
                  base::BindOnce(
                      [](tabs::TabHandle handle, GURL url, std::string space,
                         int rank, bool shown, std::string previous,
                         std::string pin, std::string name,
                         base::WeakPtr<ClairBrowserWindow> holder,
                         ClairBrowserWindow* member) {
                        if (!member) {
                          return;
                        }
                        // The original lets go of its pin first, so the
                        // reopened tab binds to it.
                        if (tabs::TabInterface* row = handle.Get();
                            row && !pin.empty()) {
                          if (ClairSpaceTabs* lists =
                                  ClairSpaceTabs::ForWebContents(
                                      row->GetContents())) {
                            lists->UnbindForReopen(row);
                          }
                        }
                        tabs::TabInterface* reopened = OpenTabInSpace(
                            member, url, space, rank, pin, name);
                        if (shown && reopened) {
                          ClairWindowGroup* group =
                              ClairWindowGroup::Of(member);
                          if (group && group->shown() != member) {
                            member->BeginSwapIn(previous, group->shown());
                          }
                          member->ActivateTab(reopened);
                          if (group) {
                            group->SwapTo(member, previous);
                          }
                        }
                        // D9: every other group showing the Space swaps to
                        // its member for the Space's profile too, before the
                        // original closes: its outgoing member, hidden, then
                        // shows no still of it to replace.
                        SwapGroupsShowing(space);
                        CloseReopened(handle);
                      },
                      handle, url, space, this_rank, shown, previous, pin,
                      name, holder->GetWeakPtr()));
            }
          },
          std::move(rows), space, first_rank));
}

}  // namespace

void DeleteSpace(const std::string& space) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  std::optional<size_t> index = store->IndexOf(space);
  if (!index || store->spaces().size() <= 1) {
    return;
  }
  // The Space before it, or the one after when it was first.
  const std::string neighbour =
      store->spaces()[*index > 0 ? *index - 1 : 1].id;
  // Each window showing it shows the neighbour first, which may be of another
  // profile, whose member may need its profile loaded (add-profiles D3).
  std::vector<ClairWindowGroup*> showing;
  for (ClairWindowGroup* group : ClairWindowGroup::RegularByActivation()) {
    if (group->shown_space() == space) {
      showing.push_back(group);
    }
  }
  // Its tabs close once every window showing it has moved on, which is at
  // once when none does.
  base::RepeatingClosure barrier = base::BarrierClosure(
      showing.size(),
      base::BindOnce(&CloseTabsOfDeletedSpace, space, neighbour));
  for (ClairWindowGroup* group : showing) {
    group->ShowSpace(neighbour,
                     base::BindOnce(
                         [](base::RepeatingClosure barrier, ClairBrowserWindow*) {
                           barrier.Run();
                         },
                         barrier));
  }
}

void MoveTabToSpace(tabs::TabInterface* tab, const std::string& space) {
  ClairSpaceTabs* lists =
      tab ? ClairSpaceTabs::ForWebContents(tab->GetContents()) : nullptr;
  ClairSpaceStore* store = ClairSpaceStore::Get();
  if (!lists || !lists->is_regular() || !store->Contains(space)) {
    return;
  }
  ClairBrowserWindow* window =
      ClairBrowserWindow::FromWebContents(tab->GetContents());
  // A Peek moves with its parent.
  if (window && window->peeks()) {
    if (tabs::TabInterface* parent = window->peeks()->ParentOf(tab)) {
      tab = parent;
    }
  }
  if (lists->SpaceOf(tab) == space) {
    return;
  }
  // add-pinned-tabs-and-favorites D5: a pinned tab moves with its pin, to the
  // end of the other Space's pinned tabs.
  if (const std::string pin = lists->PinOf(tab); !pin.empty()) {
    MovePin(pin, PinContainer::OfSpace(space),
            std::numeric_limits<size_t>::max());
    return;
  }
  // add-profiles D9: a page can't change profile; it reopens at the top of
  // the other Space, in its profile.
  if (store->ProfileOf(space) != ClairProfiles::IDOf(lists->profile())) {
    ReopenInProfile({tab->GetHandle()}, space, /*first_rank=*/0);
    return;
  }
  // Another window with a still of it picks its next tab, as if the tab had
  // closed there.
  for (ClairBrowserWindow* other : ClairBrowserWindow::All()) {
    if (other != window && other->still_tab() == tab->GetHandle()) {
      other->StillTabClosed();
    }
  }
  const bool follows = window && window->IsActiveRow(tab);
  lists->SetSpace(tab, space);
  // The window follows its active tab, which stays active (D9, replacing
  // add-spaces D7's next-tab choice).
  if (follows) {
    window->FollowActiveTab();
  }
}

void SetSpaceProfile(const std::string& space, const std::string& profile) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  const std::string old_profile = store->ProfileOf(space);
  if (old_profile.empty() || old_profile == profile ||
      !store->SetProfile(space, profile)) {
    return;
  }
  // D9: every tab of the Space, in its order, Peeks left out: the open
  // pinned tabs, which reopen bound to their pins
  // (add-pinned-tabs-and-favorites D5), then the Today tabs.
  std::vector<tabs::TabHandle> rows;
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    if (!lists->is_regular() ||
        ClairProfiles::IDOf(lists->profile()) != old_profile) {
      continue;
    }
    for (tabs::TabInterface* tab : lists->PinnedTabsIn(space)) {
      rows.push_back(tab->GetHandle());
    }
    for (tabs::TabInterface* tab : lists->TabsIn(space)) {
      ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab);
      if (holder && holder->peeks() && holder->peeks()->ParentOf(tab)) {
        continue;
      }
      rows.push_back(tab->GetHandle());
    }
  }
  if (rows.empty()) {
    // No tab to reopen, but a window may still show the Space.
    ClairProfiles::Get()->Load(
        profile, base::BindOnce(
                     [](std::string space, Profile* loaded) {
                       if (loaded && ClairSpaceStore::Get()->Contains(space)) {
                         SwapGroupsShowing(space);
                       }
                     },
                     space));
    return;
  }
  ReopenInProfile(std::move(rows), space, /*first_rank=*/0);
}

// --- Pins (add-pinned-tabs-and-favorites D2 to D7, D9, D10) ---

tabs::TabInterface* BoundTabOf(std::string_view pin) {
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    if (tabs::TabInterface* tab = lists->BoundTab(pin)) {
      return tab;
    }
  }
  return nullptr;
}

NSArray<id<ClairPin>>* PinSnapshots(const PinContainer& container) {
  NSMutableArray<id<ClairPin>>* pins = [NSMutableArray array];
  ClairPinStore* store = ClairPinStore::Get();
  for (const Pin* pin : store->PinsIn(container)) {
    ClairSpaceTabs* holder = nullptr;
    for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
      if (lists->BoundTab(pin->id)) {
        holder = lists;
        break;
      }
    }
    if (!holder) {
      [pins addObject:[[ClairChromiumPin alloc] initWithPin:*pin
                                                       tabs:@[]
                                              isAtPinnedURL:YES]];
      continue;
    }
    [pins addObject:holder->PinSnapshot(*pin)];
  }
  return pins;
}

void PinsChanged(const PinContainer& container) {
  if (container.space.empty() && container.profile.empty()) {
    return;
  }
  PinPusher::Get()->Changed(container);
}

void UpdateWindowTitles() {
  for (ClairBrowserWindow* window : ClairBrowserWindow::All()) {
    window->UpdateTitleBar();
  }
}

void PinTab(tabs::TabInterface* tab, size_t index, bool favorite) {
  ClairSpaceTabs* lists =
      tab ? ClairSpaceTabs::ForWebContents(tab->GetContents()) : nullptr;
  if (!lists || !lists->is_regular()) {
    return;
  }
  const std::string space = lists->SpaceOf(tab);
  if (space.empty() || !lists->PinOf(tab).empty()) {
    return;
  }
  lists->PinTab(tab,
                favorite ? PinContainer::OfProfile(
                               ClairProfiles::IDOf(lists->profile()))
                         : PinContainer::OfSpace(space),
                index);
}

void MovePin(const std::string& pin, const PinContainer& to, size_t index) {
  ClairPinStore* store = ClairPinStore::Get();
  const Pin* record = store->Find(pin);
  if (!record) {
    return;
  }
  const std::string old_profile = store->ProfileOf(*record);
  tabs::TabInterface* bound = BoundTabOf(pin);
  if (!store->Move(pin, to, index)) {
    return;
  }
  record = store->Find(pin);
  if (!bound || !record) {
    return;
  }
  // add-profiles D9: a page can't change profile; the tab reopens in the
  // Space's profile, bound to the pin.
  if (store->ProfileOf(*record) != old_profile) {
    ReopenInProfile({bound->GetHandle()}, record->container.space,
                    /*first_rank=*/0);
    return;
  }
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(bound);
  // A pinned tab that left a Space leaves the stills of it there.
  if (!record->container.is_favorites()) {
    for (ClairBrowserWindow* other : ClairBrowserWindow::All()) {
      if (other != holder && other->still_tab() == bound->GetHandle() &&
          other->shown_space() != record->container.space) {
        other->StillTabClosed();
      }
    }
  }
  if (holder && holder->IsActiveRow(bound)) {
    holder->FollowActiveTab();
  }
}

void RemovePin(const std::string& pin) {
  ClairPinStore* store = ClairPinStore::Get();
  if (!store->Find(pin)) {
    return;
  }
  tabs::TabInterface* bound = BoundTabOf(pin);
  const tabs::TabHandle handle =
      bound ? bound->GetHandle() : tabs::TabHandle::Null();
  // D3: removed before its tab closes, so the tab's own entry in the
  // recently closed list is the newer, and brings the pin back with it.
  store->Remove(pin, /*remember=*/true);
  tabs::TabInterface* tab = handle.Get();
  if (ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab)) {
    holder->CloseTab(tab);
  }
}

void ReturnToPinnedURL(const std::string& pin) {
  const Pin* record = ClairPinStore::Get()->Find(pin);
  tabs::TabInterface* tab = BoundTabOf(pin);
  if (!record || !tab) {
    return;
  }
  // D6: a new navigation the browser starts, so Back returns.
  tab->GetContents()->GetController().LoadURL(
      record->url, content::Referrer(), ui::PAGE_TRANSITION_AUTO_BOOKMARK,
      std::string());
}

void ReplacePinnedURLWithCurrent(const std::string& pin) {
  ClairPinStore* store = ClairPinStore::Get();
  tabs::TabInterface* tab = BoundTabOf(pin);
  if (!store->Find(pin) || !tab) {
    return;
  }
  content::WebContents* contents = tab->GetContents();
  content::NavigationEntry* entry =
      contents->GetController().GetLastCommittedEntry();
  if (!entry || entry->IsInitialEntry()) {
    return;
  }
  store->SetURL(pin, entry->GetURL());
  if (!contents->GetTitle().empty()) {
    store->SetTitle(pin, base::UTF16ToUTF8(contents->GetTitle()));
  }
  if (auto* favicons = favicon::ContentFaviconDriver::FromWebContents(contents);
      favicons && favicons->FaviconIsValid() && !favicons->GetFavicon().IsEmpty()) {
    store->SetIcon(pin, favicons->GetFavicon().ToNSImage());
  }
}

void SetPinnedURL(const std::string& pin, const GURL& url) {
  ClairPinStore::Get()->SetURL(pin, url);
}

void SetPinName(const std::string& pin, const std::string& name) {
  std::string cleaned(base::TrimWhitespaceASCII(name, base::TRIM_ALL));
  ClairPinStore::Get()->SetName(pin, cleaned);
  UpdateWindowTitles();
}

void ClearToday(const std::string& space) {
  // D4: the Space's Today tabs in every window, through the close flow; a
  // Peek closes with its parent.
  std::vector<tabs::TabHandle> rows;
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    if (!lists->is_regular()) {
      continue;
    }
    for (tabs::TabInterface* tab : lists->TabsIn(space)) {
      if (!PeekParentOf(tab)) {
        rows.push_back(tab->GetHandle());
      }
    }
  }
  for (const tabs::TabHandle& handle : rows) {
    tabs::TabInterface* tab = handle.Get();
    if (ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab)) {
      holder->CloseTab(tab);
    }
  }
}

void OpenPin(ClairBrowserWindow* window, const std::string& pin) {
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  ClairPinStore* store = ClairPinStore::Get();
  const Pin* record = store->Find(pin);
  if (!lists || !lists->is_regular() || !record ||
      store->ProfileOf(*record) != ClairProfiles::IDOf(lists->profile())) {
    return;
  }
  // D2: one tab per pin.
  if (tabs::TabInterface* bound = lists->BoundTab(pin)) {
    window->ActivateRow(bound);
    return;
  }
  std::unique_ptr<content::WebContents> contents = content::WebContents::Create(
      content::WebContents::CreateParams(window->browser()->GetProfile()));
  ClairSpaceTabs::SetPendingPin(contents.get(), pin);
  contents->GetController().LoadURL(record->url, content::Referrer(),
                                    ui::PAGE_TRANSITION_AUTO_BOOKMARK,
                                    std::string());
  TabStripModel* strip = window->browser()->tab_strip_model();
  strip->InsertWebContentsAt(strip->count(), std::move(contents),
                             AddTabTypes::ADD_ACTIVE);
}

void Unpin(ClairBrowserWindow* window, const std::string& pin, int index) {
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  ClairPinStore* store = ClairPinStore::Get();
  const Pin* record = store->Find(pin);
  if (!lists || !lists->is_regular() || !record ||
      store->ProfileOf(*record) != ClairProfiles::IDOf(lists->profile())) {
    return;
  }
  // A favorite becomes a Today tab of the Space the window shows.
  const std::string space = record->container.is_favorites()
                                ? window->shown_space()
                                : record->container.space;
  if (!ClairSpaceStore::Get()->Contains(space)) {
    return;
  }
  if (tabs::TabInterface* bound = lists->BoundTab(pin)) {
    lists->UnbindToToday(bound, space, index);
    store->Remove(pin, /*remember=*/false);
    ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(bound);
    if (holder && holder->IsActiveRow(bound)) {
      holder->FollowActiveTab();
    }
    return;
  }
  // D5: a pin without a page opens one, in the background.
  const GURL url = record->url;
  const std::string name = record->name;
  store->Remove(pin, /*remember=*/false);
  OpenTabInSpace(window, url, space, index, std::string(), name);
}

bool RestoreRemovedPin(ClairBrowserWindow* window) {
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  if (!lists || !lists->is_regular()) {
    return false;
  }
  ClairPinStore* store = ClairPinStore::Get();
  const ClairPinStore::Removal* removal =
      store->NewestRemoval(ClairProfiles::IDOf(lists->profile()));
  if (!removal) {
    return false;
  }
  base::Time newest;
  if (sessions::TabRestoreService* service =
          TabRestoreServiceFactory::GetForProfile(window->browser()->GetProfile());
      service && !service->entries().empty()) {
    newest = service->entries().front()->timestamp;
  }
  // D3: the newer of the two comes back.
  if (removal->time <= newest) {
    return false;
  }
  return store->Restore(removal->pin.id);
}

bool HasRemovedPin(ClairBrowserWindow* window) {
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  return lists && lists->is_regular() &&
         ClairPinStore::Get()->NewestRemoval(
             ClairProfiles::IDOf(lists->profile()));
}

namespace {

// When `window`'s profile last closed something Restore Last Closed Tab
// brings back: a tab or window Chromium keeps, or a removed pin.
std::optional<base::Time> NewestClosed(ClairBrowserWindow* window) {
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  if (!lists || !lists->is_regular()) {
    return std::nullopt;
  }
  std::optional<base::Time> newest;
  if (sessions::TabRestoreService* service =
          TabRestoreServiceFactory::GetForProfile(lists->profile());
      service && !service->entries().empty()) {
    newest = service->entries().front()->timestamp;
  }
  if (const ClairPinStore::Removal* removal = ClairPinStore::Get()->NewestRemoval(
          ClairProfiles::IDOf(lists->profile()));
      removal && (!newest || removal->time > *newest)) {
    newest = removal->time;
  }
  return newest;
}

// The member of `window`'s group whose profile closed something last, or
// `window` itself.
ClairBrowserWindow* MemberToRestoreIn(ClairBrowserWindow* window) {
  ClairWindowGroup* group = ClairWindowGroup::Of(window);
  if (!group || !group->is_regular()) {
    return window;
  }
  ClairBrowserWindow* target = window;
  std::optional<base::Time> newest = NewestClosed(window);
  for (ClairBrowserWindow* member : group->members()) {
    if (member == window) {
      continue;
    }
    if (std::optional<base::Time> closed = NewestClosed(member);
        closed && (!newest || *closed > *newest)) {
      newest = closed;
      target = member;
    }
  }
  return target;
}

}  // namespace

bool RestoreLastClosed(ClairBrowserWindow* window) {
  ClairBrowserWindow* target = MemberToRestoreIn(window);
  if (RestoreRemovedPin(target)) {
    return true;
  }
  if (target == window) {
    return false;
  }
  // The restored tab's context shows its browser, a hidden member, which
  // the group switches to (ClairBrowserWindow::Show()).
  chrome::RestoreTab(target->browser());
  return true;
}

bool CanRestoreLastClosed(ClairBrowserWindow* window) {
  ClairWindowGroup* group = ClairWindowGroup::Of(window);
  if (!group) {
    return HasRemovedPin(window);
  }
  for (ClairBrowserWindow* member : group->members()) {
    if (NewestClosed(member)) {
      return true;
    }
  }
  return false;
}

bool IsOtherSite(const GURL& url, const GURL& current) {
  if (!url.is_valid() || !current.is_valid()) {
    return false;
  }
  // As in Arc: another host is another site, subdomains and "www." included;
  // another port isn't.
  return url.scheme() != current.scheme() ||
         url.host() != current.host();
}

bool LeavesFavorite(ClairBrowserWindow* window, const GURL& url) {
  ClairSpaceTabs* lists = window ? window->space_tabs() : nullptr;
  tabs::TabInterface* active =
      window ? window->browser()->tab_strip_model()->GetActiveTab() : nullptr;
  return lists && active && lists->IsFavoriteTab(active) &&
         IsOtherSite(url, active->GetContents()->GetLastCommittedURL());
}

}  // namespace clair

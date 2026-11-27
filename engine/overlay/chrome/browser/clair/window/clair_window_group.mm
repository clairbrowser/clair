// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_window_group.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <map>
#include <set>
#include <utility>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/uuid.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#import "chrome/browser/clair/window/clair_browser_bridge.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_extensions.h"
#import "chrome/browser/clair/window/clair_native_window.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/session_restore.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/startup/startup_browser_creator.h"
#include "url/gurl.h"

namespace {

// The user default ClairUI's Advanced page writes (add-profiles design D6).
NSString* const kRestoreWindowsKey = @"ClairRestoreWindows";

// Every group, most recently active first.
std::vector<ClairWindowGroup*>& Groups() {
  static base::NoDestructor<std::vector<ClairWindowGroup*>> groups;
  return *groups;
}

std::map<const ClairBrowserWindow*, ClairWindowGroup*>& Membership() {
  static base::NoDestructor<std::map<const ClairBrowserWindow*, ClairWindowGroup*>>
      membership;
  return *membership;
}

// The group creating a member, which the new window joins.
ClairWindowGroup* g_joining = nullptr;

// D7: the Space of each profile shown most recently in this run.
std::map<std::string, std::string>& LastShownSpaces() {
  static base::NoDestructor<std::map<std::string, std::string>> spaces;
  return *spaces;
}

// --- Session restore (D6) ---

// The user's setting, read once at launch, or true for a launch that follows
// Chromium's relaunch, such as an update's.
bool g_restore_windows = false;
// The windows session restore created, held until it has finished.
std::vector<base::WeakPtr<ClairBrowserWindow>>& Restored() {
  static base::NoDestructor<std::vector<base::WeakPtr<ClairBrowserWindow>>>
      restored;
  return *restored;
}
// The window session restore activated: the one last active.
base::WeakPtr<ClairBrowserWindow>& LastActivatedByRestore() {
  static base::NoDestructor<base::WeakPtr<ClairBrowserWindow>> window;
  return *window;
}
// Arranges the held windows should session restore never say it has
// finished. Each arrangement stops it; the next held window starts it again.
base::OneShotTimer& ArrangeFallback() {
  static base::NoDestructor<base::OneShotTimer> timer;
  return *timer;
}
// The group the first arrangement of this launch made, with restoring off:
// browsers a later profile's session restore brings join it (D6).
base::WeakPtr<ClairWindowGroup>& RestoreGroup() {
  static base::NoDestructor<base::WeakPtr<ClairWindowGroup>> group;
  return *group;
}

bool IsRestored(const ClairBrowserWindow* window) {
  return std::ranges::any_of(Restored(), [window](const auto& weak) {
    return weak.get() == window;
  });
}

std::string ProfileIDOf(const ClairBrowserWindow* window) {
  return window ? clair::ClairProfiles::IDOf(window->browser()->GetProfile())
                : std::string();
}

// D4: a cover is auxiliary only while it covers: a full-screen primary
// window ordered onto the owner's full-screen Space would go full screen
// itself, on a Space of its own. Back from covering, it's primary again.
void SetCoverBehavior(NSWindow* window, bool covering) {
  const NSWindowCollectionBehavior from =
      covering ? NSWindowCollectionBehaviorFullScreenPrimary
               : NSWindowCollectionBehaviorFullScreenAuxiliary;
  const NSWindowCollectionBehavior to =
      covering ? NSWindowCollectionBehaviorFullScreenAuxiliary
               : NSWindowCollectionBehaviorFullScreenPrimary;
  window.collectionBehavior = (window.collectionBehavior & ~from) | to;
}

}  // namespace

// --- Membership ---

ClairWindowGroup::ClairWindowGroup(std::string id) : id_(std::move(id)) {
  Groups().push_back(this);
}

ClairWindowGroup::~ClairWindowGroup() {
  std::erase(Groups(), this);
}

// static
void ClairWindowGroup::Join(ClairBrowserWindow* window) {
  if (g_joining) {
    g_joining->Add(window);
    return;
  }
  auto* group =
      new ClairWindowGroup(base::Uuid::GenerateRandomV4().AsLowercaseString());
  group->Add(window);
  group->shown_ = window;
  // D6: session restore's windows wait until it has finished.
  if (SessionRestore::IsRestoring(window->browser()->GetProfile())) {
    Restored().push_back(window->GetWeakPtr());
    if (!ArrangeFallback().IsRunning()) {
      ArrangeFallback().Start(
          FROM_HERE, base::Seconds(15),
          base::BindOnce(&ClairWindowGroup::ArrangeRestoredWindows));
    }
  }
}

// static
void ClairWindowGroup::Leave(ClairBrowserWindow* window) {
  ClairWindowGroup* group = Of(window);
  if (!group) {
    return;
  }
  const bool was_shown = group->shown_ == window;
  group->Remove(window);
  if (group->members_.empty()) {
    delete group;
    return;
  }
  if (browser_shutdown::IsTryingToQuit()) {
    return;
  }
  base::WeakPtr<ClairWindowGroup> weak = group->weak_factory_.GetWeakPtr();
  if (group->handing_over_) {
    return;
  }
  if (group->closing_) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&ClairWindowGroup::CloseNext, weak));
  } else if (was_shown) {
    // D13: a shown member that closes, as by a close Clair didn't start of
    // its only tab, closes its group as the user's close does.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ClairWindowGroup> group) {
                         if (group) {
                           group->CloseByUser();
                         }
                       },
                       weak));
  }
}

// static
ClairWindowGroup* ClairWindowGroup::Of(const ClairBrowserWindow* window) {
  auto found = Membership().find(window);
  return found == Membership().end() ? nullptr : found->second;
}

void ClairWindowGroup::Add(ClairBrowserWindow* window) {
  members_.push_back(window);
  Membership()[window] = this;
}

void ClairWindowGroup::Remove(ClairBrowserWindow* window) {
  // A full-screen owner that leaves under its cover leaves the cover as the
  // window, normally.
  OwnerClosing(window);
  std::erase(members_, window);
  Membership().erase(window);
  std::erase_if(holds_startup_show_, [window](const auto& weak) {
    return !weak || weak.get() == window;
  });
  if (cover_ == window) {
    cover_ = nullptr;
  }
  if (fullscreen_owner_ == window) {
    fullscreen_owner_ = nullptr;
  }
  if (shown_ == window) {
    shown_ = members_.empty() ? nullptr : members_.front().get();
    // Shown now without a Reveal(), if the group's close stops.
    if (shown_ && shown_->extensions()) {
      shown_->extensions()->FlushIfStale();
    }
  }
}

void ClairWindowGroup::Adopt(ClairBrowserWindow* window) {
  ClairWindowGroup* from = Of(window);
  if (from == this) {
    return;
  }
  if (from) {
    from->Remove(window);
    if (from->members_.empty()) {
      delete from;
    }
  }
  Add(window);
  // Its tabs' sessions name its old group.
  GroupTagsChanged(window);
}

// static
void ClairWindowGroup::GroupTagsChanged(ClairBrowserWindow* member) {
  if (member && member->space_tabs()) {
    member->space_tabs()->AllListsChanged();
  }
}

void ClairWindowGroup::SetID(std::string id) {
  if (id == id_) {
    return;
  }
  id_ = std::move(id);
  for (ClairBrowserWindow* member : members_) {
    GroupTagsChanged(member);
  }
}

void ClairWindowGroup::TakeIn(ClairBrowserWindow* other, bool at_frame) {
  if (!other || Of(other) == this) {
    return;
  }
  // A second browser of a profile hands its tabs to the first, as a closing
  // window does (share-tabs D4), and closes.
  if (ClairBrowserWindow* same = MemberFor(ProfileIDOf(other))) {
    if (!other->HandTabsTo(same, nullptr)) {
      other->Close();
    }
    return;
  }
  Adopt(other);
  if (at_frame && shown_ && shown_ != other) {
    [other->ns_window() setFrame:shown_->ns_window().frame display:NO];
  }
}

std::vector<ClairBrowserWindow*> ClairWindowGroup::members() const {
  std::vector<ClairBrowserWindow*> members;
  for (ClairBrowserWindow* member : members_) {
    members.push_back(member);
  }
  return members;
}

ClairBrowserWindow* ClairWindowGroup::MemberFor(
    const std::string& profile_id) const {
  for (ClairBrowserWindow* member : members_) {
    if (ProfileIDOf(member) == profile_id && !member->browser()->IsDeleteScheduled()) {
      return member;
    }
  }
  return nullptr;
}

bool ClairWindowGroup::is_regular() const {
  return shown_ && shown_->space_tabs() && shown_->space_tabs()->is_regular();
}

std::string ClairWindowGroup::shown_space() const {
  return shown_ ? shown_->shown_space() : std::string();
}

// static
std::vector<ClairWindowGroup*> ClairWindowGroup::RegularByActivation() {
  std::vector<ClairWindowGroup*> groups;
  for (ClairWindowGroup* group : Groups()) {
    if (group->is_regular() && !group->handing_over_ && !group->IsClosing()) {
      groups.push_back(group);
    }
  }
  return groups;
}

// static
ClairWindowGroup* ClairWindowGroup::MostRecentlyActive(
    const ClairWindowGroup* except) {
  for (ClairWindowGroup* group : RegularByActivation()) {
    if (group != except && group->shown_ &&
        !group->shown_->browser()->IsDeleteScheduled() &&
        !IsRestored(group->shown_)) {
      return group;
    }
  }
  return nullptr;
}

void ClairWindowGroup::Activated() {
  auto it = std::ranges::find(Groups(), this);
  if (it != Groups().end() && it != Groups().begin()) {
    Groups().erase(it);
    Groups().insert(Groups().begin(), this);
  }
}

void ClairWindowGroup::ShownSpaceChanged(ClairBrowserWindow* member) {
  // D6: a window session restore holds hasn't been arranged; what it shows
  // isn't the user's yet.
  if (member != shown_ || !is_regular() || IsRestored(member)) {
    return;
  }
  const std::string space = member->shown_space();
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  if (!store->Contains(space)) {
    return;
  }
  store->SetWindowSpace(id_, space);
  LastShownSpaces()[ProfileIDOf(member)] = space;
}

// --- Switching (D3, D4) ---

void ClairWindowGroup::ShowSpace(
    const std::string& space,
    base::OnceCallback<void(ClairBrowserWindow*)> then,
    tabs::TabHandle tab) {
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  if (!is_regular() || !store->Contains(space)) {
    if (then) {
      std::move(then).Run(nullptr);
    }
    return;
  }
  const std::string profile = store->ProfileOf(space);
  // The group switches on purpose: start-up's shows are over for it.
  holds_startup_show_.clear();
  if (ProfileIDOf(shown_) == profile) {
    shown_->ShowSpace(space, /*again=*/false, tab.Get());
    if (then) {
      std::move(then).Run(shown_);
    }
    return;
  }
  const std::string previous = shown_space();
  EnsureMember(
      profile,
      base::BindOnce(
          [](base::WeakPtr<ClairWindowGroup> group, std::string space,
             std::string previous,
             base::OnceCallback<void(ClairBrowserWindow*)> then,
             tabs::TabHandle tab, ClairBrowserWindow* member) {
            if (!group || !member) {
              if (then) {
                std::move(then).Run(nullptr);
              }
              return;
            }
            // ClairUI hears that the window shows `space` coming from the
            // group's earlier Space, in place of the shown member, before
            // the member's tab shows it.
            member->BeginSwapIn(previous, group->shown_);
            member->ShowSpace(space, /*again=*/true, tab.Get());
            group->SwapTo(member, previous);
            if (then) {
              std::move(then).Run(member);
            }
          },
          weak_factory_.GetWeakPtr(), space, previous, std::move(then), tab));
}

void ClairWindowGroup::EnsureMember(
    const std::string& profile_id,
    base::OnceCallback<void(ClairBrowserWindow*)> done) {
  if (ClairBrowserWindow* member = MemberFor(profile_id)) {
    std::move(done).Run(member);
    return;
  }
  clair::ClairProfiles::Get()->Load(
      profile_id,
      base::BindOnce(
          [](base::WeakPtr<ClairWindowGroup> group, std::string profile_id,
             base::OnceCallback<void(ClairBrowserWindow*)> done,
             Profile* profile) {
            if (!group || !profile || !group->shown_) {
              std::move(done).Run(nullptr);
              return;
            }
            // Loaded meanwhile by another request.
            if (ClairBrowserWindow* member = group->MemberFor(profile_id)) {
              std::move(done).Run(member);
              return;
            }
            BrowserWindowCreateParams params(*profile,
                                             /*from_user_gesture=*/true);
            params.initial_bounds = group->shown_->GetBounds();
            BrowserWindowInterface* browser = nullptr;
            {
              base::AutoReset<ClairWindowGroup*> joining(&g_joining,
                                                         group.get());
              browser = CreateBrowserWindow(std::move(params));
            }
            std::move(done).Run(browser ? ClairBrowserWindow::FromBrowser(browser)
                                        : nullptr);
          },
          weak_factory_.GetWeakPtr(), profile_id, std::move(done)));
}

void ClairWindowGroup::SwapTo(ClairBrowserWindow* member,
                              const std::string& previous_space) {
  if (!member || member == shown_ || Of(member) != this) {
    return;
  }
  if (IsFullscreen()) {
    Cover(member);
    // The cover took the key window.
    clair::ClairSpaceStore::Get()->SetLastSpace(member->shown_space());
    ShownSpaceChanged(member);
    return;
  }
  ClairBrowserWindow* old = shown_;
  NSWindow* in = member->ns_window();
  NSWindow* out = old ? old->ns_window() : nil;
  const bool make_key = !out || out.keyWindow || out.mainWindow;
  if (out) {
    [in setFrame:out.frame display:NO];
  }
  shown_ = member;
  // ClairUI hears of the Space, and takes the outgoing window's sidebar,
  // before the window shows.
  [member->bridge() flush];
  const NSWindowAnimationBehavior in_behavior = in.animationBehavior;
  const NSWindowAnimationBehavior out_behavior = out.animationBehavior;
  in.animationBehavior = NSWindowAnimationBehaviorNone;
  out.animationBehavior = NSWindowAnimationBehaviorNone;
  [NSAnimationContext beginGrouping];
  NSAnimationContext.currentContext.duration = 0;
  member->Reveal(out, make_key);
  if (old) {
    old->Conceal(/*order_out=*/true);
  }
  [NSAnimationContext endGrouping];
  in.animationBehavior = in_behavior;
  out.animationBehavior = out_behavior;
  // The Space a new window shows (add-spaces D1): the swap took the key
  // window, whether or not AppKit reports the key change.
  if (make_key) {
    clair::ClairSpaceStore::Get()->SetLastSpace(member->shown_space());
  }
  ShownSpaceChanged(member);
}

void ClairWindowGroup::ShowMember(ClairBrowserWindow* member) {
  if (!member || member == shown_ || Of(member) != this || !is_regular()) {
    return;
  }
  const std::string previous = shown_space();
  // The Space it showed, or else its active tab's.
  std::string space = member->shown_space();
  if (!clair::ClairSpaceStore::Get()->Contains(space)) {
    tabs::TabInterface* active =
        member->browser()->tab_strip_model()->GetActiveTab();
    space = active && member->space_tabs()
                ? member->space_tabs()->IntendedSpaceOf(active)
                : std::string();
  }
  if (space.empty()) {
    return;
  }
  member->BeginSwapIn(previous, shown_);
  member->ShowSpace(space, /*again=*/true);
  SwapTo(member, previous);
}

ClairBrowserWindow* ClairWindowGroup::fullscreen_owner() const {
  return fullscreen_owner_;
}

bool ClairWindowGroup::IsFullscreen() const {
  return fullscreen_owner_ &&
         (fullscreen_owner_->ns_window().styleMask & NSWindowStyleMaskFullScreen);
}

void ClairWindowGroup::Cover(ClairBrowserWindow* member) {
  ClairBrowserWindow* owner = fullscreen_owner_;
  if (!owner) {
    return;
  }
  if (member == owner) {
    Uncover();
    shown_ = owner;
    [owner->bridge() flush];
    owner->Reveal(nil, /*make_key=*/true);
    return;
  }
  NSWindow* owner_window = owner->ns_window();
  NSWindow* window = member->ns_window();
  ClairBrowserWindow* previous_cover = cover_;
  SetCoverBehavior(window, /*covering=*/true);
  // The owner's corners and window controls mustn't show around it, and it
  // lies over the menu bar's place too.
  member->SetCovering(true);
  [window setFrame:owner_window.frame display:NO];
  shown_ = member;
  cover_ = member;
  [member->bridge() flush];
  member->JoinActiveSpace();
  [owner_window addChildWindow:window ordered:NSWindowAbove];
  member->Reveal(nil, /*make_key=*/true);
  if (previous_cover && previous_cover != member) {
    [owner_window removeChildWindow:previous_cover->ns_window()];
    EndCovering(previous_cover);
    previous_cover->Conceal(/*order_out=*/true);
  } else if (!previous_cover) {
    // The owner stays in place under the cover; its pages are hidden.
    owner->Conceal(/*order_out=*/false);
  }
}

void ClairWindowGroup::Uncover() {
  ClairBrowserWindow* cover = cover_;
  if (!cover || !fullscreen_owner_) {
    return;
  }
  cover_ = nullptr;
  [fullscreen_owner_->ns_window() removeChildWindow:cover->ns_window()];
  EndCovering(cover);
  cover->Conceal(/*order_out=*/true);
}

// static
void ClairWindowGroup::EndCovering(ClairBrowserWindow* cover) {
  cover->SetCovering(false);
  SetCoverBehavior(cover->ns_window(), /*covering=*/false);
}

void ClairWindowGroup::OwnerClosing(ClairBrowserWindow* member) {
  if (!member || member != fullscreen_owner_ || !cover_) {
    return;
  }
  // Before the owner is ordered out, which would take its child window
  // with it.
  ClairBrowserWindow* cover = cover_;
  cover_ = nullptr;
  fullscreen_owner_ = nullptr;
  [member->ns_window() removeChildWindow:cover->ns_window()];
  EndCovering(cover);
  shown_ = cover;
  cover->Reveal(nil, /*make_key=*/true);
}

void ClairWindowGroup::FullscreenChanged(ClairBrowserWindow* member,
                                         bool entered) {
  if (entered) {
    if (member == shown_ && !cover_) {
      fullscreen_owner_ = member;
    }
    return;
  }
  if (member != fullscreen_owner_) {
    return;
  }
  fullscreen_owner_ = nullptr;
  ClairBrowserWindow* cover = cover_;
  if (!cover) {
    return;
  }
  // D4: the cover becomes the window, at the owner's restored frame, and the
  // owner is ordered out: a normal swap.
  cover_ = nullptr;
  NSWindow* owner_window = member->ns_window();
  NSWindow* window = cover->ns_window();
  [owner_window removeChildWindow:window];
  EndCovering(cover);
  [window setFrame:owner_window.frame display:YES];
  shown_ = cover;
  cover->Reveal(owner_window, /*make_key=*/true);
  member->Conceal(/*order_out=*/true);
}

// --- Closing (D5, D13) ---

void ClairWindowGroup::CloseByUser(tabs::TabInterface* closing) {
  if (IsClosing() || handing_over_) {
    return;
  }
  base::WeakPtr<ClairWindowGroup> weak = weak_factory_.GetWeakPtr();
  ClairWindowGroup* target = is_regular() && !browser_shutdown::IsTryingToQuit()
                                 ? MostRecentlyActive(this)
                                 : nullptr;
  if (!target) {
    // Chromium's close flow, member by member, hidden ones first: each that
    // leaves closes the next. Handing tabs on isn't closing: each member
    // closes once its strip empties.
    closing_ = true;
    CloseNext();
    return;
  }
  const tabs::TabHandle closing_handle =
      closing ? closing->GetHandle() : tabs::TabHandle::Null();
  // D5: each member's tabs go to the other group's member for that profile,
  // which the other group creates hidden if it has none. Its profile is
  // loaded, so that's at once.
  for (ClairBrowserWindow* member : members()) {
    const std::string profile = ProfileIDOf(member);
    target->EnsureMember(
        profile, base::BindOnce(
                     [](base::WeakPtr<ClairBrowserWindow> from,
                        tabs::TabHandle closing, ClairBrowserWindow* to) {
                       if (!from) {
                         return;
                       }
                       if (!to || !from->HandTabsTo(to, closing.Get())) {
                         // Nothing to hand on: it closes as Chromium would.
                         from->Close();
                       }
                     },
                     member->GetWeakPtr(), closing_handle));
  }
  if (!weak) {
    return;
  }
  // The new tab page of an emptied Space closes with the window (D13).
  if (tabs::TabInterface* tab = closing_handle.Get()) {
    if (ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab);
        holder && Of(holder) == this && !holder->browser()->IsDeleteScheduled()) {
      holder->CloseTabWithoutChoosing(tab);
    }
  }
}

void ClairWindowGroup::CloseCancelled(ClairBrowserWindow* member) {
  if (Of(member) == this) {
    closing_ = false;
  }
}

void ClairWindowGroup::CloseNext() {
  if (!closing_) {
    return;
  }
  ClairBrowserWindow* next = nullptr;
  for (ClairBrowserWindow* member : members_) {
    if (member != shown_ && !member->browser()->IsDeleteScheduled()) {
      next = member;
      break;
    }
  }
  if (!next && shown_ && !shown_->browser()->IsDeleteScheduled()) {
    next = shown_;
  }
  if (!next) {
    return;
  }
  // A page that asks before leaving asks where the user can see it.
  if (next != shown_ && next->NeedsBeforeUnload()) {
    ShowMember(next);
  }
  next->Close();
}

void ClairWindowGroup::MaybeCloseEmptyHiddenMember(ClairBrowserWindow* member) {
  // The full-screen owner under a cover holds the group's full screen (D4).
  if (!member || member == fullscreen_owner_ || IsClosing() ||
      !IsHidden(member) || IsRestored(member) ||
      member->HasRealTabs() || member->browser()->IsDeleteScheduled()) {
    return;
  }
  member->Close();
}

// --- Opening (D7, D8) ---

// static
std::string ClairWindowGroup::LastShownSpaceOf(const std::string& profile_id) {
  auto found = LastShownSpaces().find(profile_id);
  if (found == LastShownSpaces().end() ||
      clair::ClairSpaceStore::Get()->ProfileOf(found->second) != profile_id) {
    return std::string();
  }
  return found->second;
}

// static
std::string ClairWindowGroup::SpaceForNewWindow(Profile* profile) {
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  const std::string profile_id = clair::ClairProfiles::IDOf(profile);
  const std::string last = store->last_space();
  if (store->ProfileOf(last) == profile_id) {
    return last;
  }
  return SpaceOfProfile(profile_id);
}

// static
std::string ClairWindowGroup::SpaceOfProfile(const std::string& profile_id) {
  if (std::string space = LastShownSpaceOf(profile_id); !space.empty()) {
    return space;
  }
  for (const clair::Space& space : clair::ClairSpaceStore::Get()->spaces()) {
    if (space.profile == profile_id) {
      return space.id;
    }
  }
  return std::string();
}

// static
void ClairWindowGroup::OpenInSpace(
    const std::string& space,
    const GURL& url,
    base::OnceCallback<void(ClairBrowserWindow*)> then) {
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  if (!store->Contains(space)) {
    if (then) {
      std::move(then).Run(nullptr);
    }
    return;
  }
  if (ClairWindowGroup* group = MostRecentlyActive(nullptr)) {
    group->ShowSpace(
        space, base::BindOnce(
                   [](GURL url, base::OnceCallback<void(ClairBrowserWindow*)> then,
                      ClairBrowserWindow* member) {
                     if (member) {
                       member->OpenInShownSpace(url);
                       member->Activate();
                     }
                     if (then) {
                       std::move(then).Run(member);
                     }
                   },
                   url, std::move(then)));
    return;
  }
  // No window: a new one, on the Space.
  clair::ClairProfiles::Get()->Load(
      store->ProfileOf(space),
      base::BindOnce(
          [](std::string space, GURL url,
             base::OnceCallback<void(ClairBrowserWindow*)> then,
             Profile* profile) {
            ClairBrowserWindow* window = nullptr;
            if (profile && clair::ClairSpaceStore::Get()->Contains(space)) {
              BrowserWindowInterface* browser =
                  CreateBrowserWindow(BrowserWindowCreateParams(
                      *profile, /*from_user_gesture=*/true));
              window = browser ? ClairBrowserWindow::FromBrowser(browser)
                               : nullptr;
            }
            if (window) {
              window->ShowSpaceOnNewTab(space, url);
              window->Show();
            }
            if (then) {
              std::move(then).Run(window);
            }
          },
          space, url, std::move(then)));
}

// static
void ClairWindowGroup::HandOverToLastSpace(ClairBrowserWindow* window) {
  ClairWindowGroup* group = Of(window);
  if (!group || group->handing_over_ || window->browser()->IsDeleteScheduled()) {
    return;
  }
  // Its group takes no part from now on.
  group->handing_over_ = true;
  const std::string space = clair::ClairSpaceStore::Get()->last_space();
  std::vector<GURL> urls = window->PageURLs();
  if (urls.empty()) {
    urls.push_back(GURL());
  }
  // One window: the first page opens as any link does, which may wait for a
  // profile to load, and the rest follow it there.
  const GURL first = urls.front();
  urls.erase(urls.begin());
  OpenInSpace(space, first,
              base::BindOnce(
                  [](std::vector<GURL> rest, ClairBrowserWindow* member) {
                    if (!member) {
                      return;
                    }
                    for (const GURL& url : rest) {
                      member->OpenInShownSpace(url);
                    }
                  },
                  std::move(urls)));
  window->Close();
}

// --- Session restore (D6) ---

// static
void ClairWindowGroup::Start() {
  static bool started = false;
  if (started) {
    return;
  }
  started = true;
  // A relaunch, such as Restart and Update or an idle install, brings back
  // every window whatever the setting (software-updates spec, "Relaunch
  // preserves the browsing session").
  g_restore_windows =
      [NSUserDefaults.standardUserDefaults boolForKey:kRestoreWindowsKey] ||
      StartupBrowserCreator::WasRestarted();
  static base::NoDestructor<base::CallbackListSubscription> subscription(
      SessionRestore::RegisterOnSessionRestoredCallback(
          base::BindRepeating(&ClairWindowGroup::SessionRestored)));
}

// static
bool ClairWindowGroup::HoldsShow(ClairBrowserWindow* window) {
  return IsRestored(window);
}

// static
bool ClairWindowGroup::TakeStartupShow(const ClairBrowserWindow* window) {
  ClairWindowGroup* group = Of(window);
  if (!group || !group->IsHidden(window)) {
    return false;
  }
  auto held = std::ranges::find_if(
      group->holds_startup_show_,
      [window](const auto& weak) { return weak.get() == window; });
  if (held == group->holds_startup_show_.end()) {
    return false;
  }
  // Start-up's Show() and Activate() come together: both are absorbed, and
  // the hold ends after the current task.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairWindowGroup> group,
                        base::WeakPtr<ClairBrowserWindow> window) {
                       if (group) {
                         std::erase_if(group->holds_startup_show_,
                                       [&window](const auto& weak) {
                                         return !weak || weak.get() == window.get();
                                       });
                       }
                     },
                     group->weak_factory_.GetWeakPtr(), *held));
  return true;
}

// static
void ClairWindowGroup::NoteRestoreActivation(ClairBrowserWindow* window) {
  if (IsRestored(window)) {
    LastActivatedByRestore() = window->GetWeakPtr();
  }
}

// static
void ClairWindowGroup::SessionRestored(Profile* profile, int tab_count) {
  // After the current task, when every profile session restore started on
  // has been restored.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce([] {
        for (const auto& weak : Restored()) {
          if (weak && SessionRestore::IsRestoring(weak->browser()->GetProfile())) {
            return;
          }
        }
        ArrangeRestoredWindows();
      }));
}

// static
void ClairWindowGroup::ArrangeRestoredWindows() {
  std::vector<ClairBrowserWindow*> windows;
  for (const auto& weak : Restored()) {
    if (weak && !weak->browser()->IsDeleteScheduled()) {
      windows.push_back(weak.get());
    }
  }
  ClairBrowserWindow* last_active = LastActivatedByRestore().get();
  Restored().clear();
  LastActivatedByRestore() = nullptr;
  ArrangeFallback().Stop();
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();

  std::vector<ClairBrowserWindow*> regular;
  for (ClairBrowserWindow* window : windows) {
    if (window->space_tabs() && window->space_tabs()->is_regular()) {
      regular.push_back(window);
    } else {
      window->Show();
    }
  }

  if (g_restore_windows) {
    // On: each window comes back as it was, its members gathered by the
    // group's tag on their tabs.
    std::map<std::string, std::vector<ClairBrowserWindow*>> by_tag;
    for (ClairBrowserWindow* window : regular) {
      const std::string tag = window->RestoredGroupTag();
      if (tag.empty()) {
        window->Show();
      } else {
        by_tag[tag].push_back(window);
      }
    }
    for (auto& [tag, members] : by_tag) {
      // Session restore restores each profile in turn: a group an earlier
      // arrangement made for this tag takes these members, hidden, and
      // shows the one of its Space's profile.
      ClairWindowGroup* existing = nullptr;
      for (ClairWindowGroup* candidate : Groups()) {
        if (candidate->id_ == tag &&
            std::ranges::none_of(members, [candidate](ClairBrowserWindow* m) {
              return Of(m) == candidate;
            })) {
          existing = candidate;
          break;
        }
      }
      if (existing && existing->shown_) {
        const std::string space = store->WindowSpace(tag);
        for (ClairBrowserWindow* member : members) {
          existing->TakeIn(member, /*at_frame=*/true);
          if (Of(member) == existing && !space.empty() &&
              store->ProfileOf(space) == ProfileIDOf(member)) {
            member->ShowRestoredSpace(space);
            existing->ShowMember(member);
          }
        }
        continue;
      }
      ClairBrowserWindow* lead = members.front();
      ClairWindowGroup* group = Of(lead);
      if (!group) {
        continue;
      }
      if (std::ranges::none_of(Groups(), [&tag](ClairWindowGroup* other) {
            return other->id_ == tag;
          })) {
        group->SetID(tag);
      }
      for (ClairBrowserWindow* other : members) {
        group->TakeIn(other, /*at_frame=*/false);
      }
      // The member of the Space the window showed, on the tab Chromium
      // restored as its selected one.
      const std::string space = store->WindowSpace(tag);
      ClairBrowserWindow* shown =
          space.empty() ? nullptr : group->MemberFor(store->ProfileOf(space));
      if (!shown) {
        shown = lead;
      }
      group->shown_ = shown;
      if (!space.empty() && store->ProfileOf(space) == ProfileIDOf(shown)) {
        shown->ShowRestoredSpace(space);
      } else {
        shown->ShowRestoredSpace(shown->shown_space());
      }
      for (ClairBrowserWindow* member : group->members()) {
        if (member != shown) {
          [member->ns_window() setFrame:shown->ns_window().frame display:NO];
        }
      }
      shown->Show();
      // A member standing in for one of a profile session restore hasn't
      // reached yet leaves the group's Space as it was.
      if (space.empty() || store->ProfileOf(space) == ProfileIDOf(shown)) {
        group->ShownSpaceChanged(shown);
      }
    }
  } else if (ClairWindowGroup* earlier = RestoreGroup().get();
             earlier && earlier->shown_ && !regular.empty()) {
    // A later profile's session restore: its browsers join the window the
    // first arrangement made, hidden.
    for (ClairBrowserWindow* other : regular) {
      earlier->TakeIn(other, /*at_frame=*/true);
    }
  } else if (!regular.empty()) {
    // Off, as Arc by default: one window, at the frame of the one last
    // active, on the Space last shown, on a new tab page.
    ClairBrowserWindow* lead =
        last_active && std::ranges::find(regular, last_active) != regular.end()
            ? last_active
            : regular.front();
    ClairWindowGroup* group = Of(lead);
    if (group) {
      RestoreGroup() = group->weak_factory_.GetWeakPtr();
    }
    for (ClairBrowserWindow* other : regular) {
      if (group) {
        group->TakeIn(other, /*at_frame=*/false);
      }
    }
    if (group) {
      const std::string space = store->last_space();
      const NSRect frame = lead->ns_window().frame;
      group->EnsureMember(
          store->ProfileOf(space),
          base::BindOnce(
              [](base::WeakPtr<ClairWindowGroup> group, std::string space,
                 NSRect frame, ClairBrowserWindow* member) {
                if (!group) {
                  return;
                }
                if (!member) {
                  member = group->shown_;
                  space = member ? member->shown_space() : std::string();
                }
                if (!member) {
                  return;
                }
                group->shown_ = member;
                [member->ns_window() setFrame:frame display:NO];
                const bool opened = member->ShowSpaceOnLaunchNewTab(space);
                member->Show();
                // On Chromium's new tab page alone, ClairUI opens the command
                // bar; asking as well would close it.
                if (opened) {
                  member->OpenCommandBarWhenShown();
                }
                group->ShownSpaceChanged(member);
              },
              group->weak_factory_.GetWeakPtr(), space, frame));
    }
  }

  // Start-up still shows and activates the browsers it restored; one left
  // hidden absorbs the first such call, until its group next switches.
  for (ClairBrowserWindow* window : windows) {
    if (ClairWindowGroup* group = Of(window)) {
      group->holds_startup_show_.push_back(window->GetWeakPtr());
    }
  }

  std::set<std::string> ids;
  for (ClairWindowGroup* group : Groups()) {
    ids.insert(group->id_);
  }
  store->KeepWindows(ids);
}

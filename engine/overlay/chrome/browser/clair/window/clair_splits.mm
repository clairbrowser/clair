// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_splits.h"

#include <algorithm>
#include <cmath>
#include <set>
#include <string>
#include <utility>

#include "base/auto_reset.h"
#include "base/functional/bind.h"
#include "base/task/single_thread_task_runner.h"
#import "chrome/browser/clair/clair_pin_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/sessions/session_restore.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/split_tab_metrics.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/common/webui_url_constants.h"
#include "components/split_tabs/split_tab_visual_data.h"
#include "components/tabs/public/split_tab_data.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/referrer.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace {

// The strip holding `tab`, or null.
TabStripModel* StripOf(const tabs::TabInterface* tab) {
  BrowserWindowInterface* browser =
      tab ? tab->GetBrowserWindowInterface() : nullptr;
  return browser ? browser->GetTabStripModel() : nullptr;
}

// The ratio the divider allows (ClairHost.h, -setSplitRatio:ofTab:).
double ClampRatio(double ratio) {
  return std::isfinite(ratio) ? std::clamp(ratio, 0.05, 0.95) : 0.5;
}

split_tabs::SplitTabVisualData SideBySide(double ratio) {
  return split_tabs::SplitTabVisualData(split_tabs::SplitTabLayout::kSideBySide,
                                        ClampRatio(ratio));
}

}  // namespace

// D4: tells the splits when a pane's page takes keyboard focus, as when the
// user clicks in it, as Chromium's MultiContentsView does.
class ClairSplits::FocusWatcher : public content::WebContentsObserver {
 public:
  FocusWatcher(ClairSplits* owner, content::WebContents* contents)
      : content::WebContentsObserver(contents), owner_(owner) {}

  void OnWebContentsFocused(
      content::RenderWidgetHost* render_widget_host) override {
    owner_->PaneFocused(web_contents());
  }

 private:
  const raw_ptr<ClairSplits> owner_;
};

ClairSplits::ClairSplits(ClairBrowserWindow* window)
    : window_(window), model_(window->browser()->tab_strip_model()) {
  model_->AddObserver(this);
  // A window that session restore filled before this existed watches its
  // splits' panes.
  for (const split_tabs::SplitTabId& split : model_->ListSplits()) {
    for (tabs::TabInterface* tab : model_->GetSplitData(split)->ListTabs()) {
      Watch(tab);
    }
  }
}

ClairSplits::~ClairSplits() {
  if (model_) {
    model_->RemoveObserver(this);
  }
}

// --- Queries ---

// static
std::vector<tabs::TabInterface*> ClairSplits::PanesOf(
    const tabs::TabInterface* tab) {
  TabStripModel* strip = StripOf(tab);
  if (!strip || !tab->IsSplit()) {
    return {};
  }
  const std::optional<split_tabs::SplitTabId> split = tab->GetSplit();
  if (!split || !strip->ContainsSplit(*split)) {
    return {};
  }
  std::vector<tabs::TabInterface*> panes =
      strip->GetSplitData(*split)->ListTabs();
  return panes.size() == 2 ? panes : std::vector<tabs::TabInterface*>();
}

// static
tabs::TabInterface* ClairSplits::PartnerOf(const tabs::TabInterface* tab) {
  for (tabs::TabInterface* pane : PanesOf(tab)) {
    if (pane != tab) {
      return pane;
    }
  }
  return nullptr;
}

// static
bool ClairSplits::IsLeading(const tabs::TabInterface* tab) {
  const std::vector<tabs::TabInterface*> panes = PanesOf(tab);
  return !panes.empty() && panes.front() == tab;
}

// static
double ClairSplits::RatioOf(const tabs::TabInterface* tab) {
  TabStripModel* strip = StripOf(tab);
  if (!strip || PanesOf(tab).empty()) {
    return 0.5;
  }
  return strip->GetSplitData(*tab->GetSplit())->visual_data()->split_ratio();
}

// static
tabs::TabInterface* ClairSplits::LastFocusedPane(tabs::TabInterface* tab) {
  tabs::TabInterface* last = tab;
  for (tabs::TabInterface* pane : PanesOf(tab)) {
    if (pane->IsActivated()) {
      return pane;
    }
    if (pane->GetLastActiveTime() > last->GetLastActiveTime()) {
      last = pane;
    }
  }
  return last;
}

int ClairSplits::IndexOf(const tabs::TabInterface* tab) const {
  return model_ && tab ? model_->GetIndexOfTab(tab) : TabStripModel::kNoTab;
}

// --- Commands ---

bool ClairSplits::Make(tabs::TabInterface* tab,
                       tabs::TabInterface* other,
                       bool other_leading,
                       double ratio,
                       tabs::TabInterface* focus) {
  const int tab_index = IndexOf(tab);
  const int other_index = IndexOf(other);
  ClairPeeks* peeks = window_->peeks();
  if (tab_index == TabStripModel::kNoTab ||
      other_index == TabStripModel::kNoTab || tab == other || tab->IsSplit() ||
      other->IsSplit() ||
      (peeks && (peeks->ParentOf(tab) || peeks->ParentOf(other)))) {
    return false;
  }
  std::vector<tabs::TabInterface*> panes;
  {
    base::AutoReset<bool> changing(&changing_, true);
    const split_tabs::SplitTabId split = strip()->AddToNewSplit(
        {tab_index, other_index}, SideBySide(ratio),
        split_tabs::SplitTabCreatedSource::kTabContextMenu);
    // AddToNewSplit keeps the strip's order; the leading pane is the one
    // asked for.
    tabs::TabInterface* leading = other_leading ? other : tab;
    if (strip()->GetSplitData(split)->ListTabs().front() != leading) {
      strip()->ReverseTabsInSplit(split);
    }
    panes = strip()->GetSplitData(split)->ListTabs();
  }
  if (focus) {
    ActivateTab(focus);
  }
  UpdateVisibility(panes);
  Changed(panes);
  return true;
}

void ClairSplits::MakeWithNewTab(tabs::TabInterface* tab) {
  const int index = IndexOf(tab);
  ClairPeeks* peeks = window_->peeks();
  if (index == TabStripModel::kNoTab || tab->IsSplit() ||
      (peeks && peeks->ParentOf(tab))) {
    return;
  }
  // A new tab page right after the tab, in the background until the split
  // shows it.
  NavigateParams params(window_->browser(), GURL(chrome::kChromeUINewTabURL),
                        ui::PAGE_TRANSITION_TYPED);
  params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
  params.tabstrip_index = index + 1;
  params.tabstrip_add_types = AddTabTypes::ADD_FORCE_INDEX;
  params.window_action = NavigateParams::WindowAction::kNoAction;
  Navigate(&params);
  content::WebContents* contents = params.navigated_or_inserted_contents;
  tabs::TabInterface* new_tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  if (!new_tab) {
    return;
  }
  // Its row is the split's: after the tab's in Today, or at the top when the
  // tab is a pinned tab's or a favorite's.
  if (ClairSpaceTabs* lists = window_->space_tabs()) {
    if (!lists->SpaceOf(tab).empty() && lists->PinOf(tab).empty()) {
      lists->MoveTabBeside(new_tab, tab, /*after=*/true);
    }
  }
  Make(tab, new_tab, /*other_leading=*/false, 0.5, new_tab);
}

void ClairSplits::Replace(tabs::TabInterface* pane,
                          tabs::TabInterface* replacement) {
  tabs::TabInterface* partner = PartnerOf(pane);
  ClairPeeks* peeks = window_->peeks();
  if (!partner || !replacement || replacement == pane ||
      replacement == partner || replacement->IsSplit() ||
      IndexOf(replacement) == TabStripModel::kNoTab ||
      (peeks && peeks->ParentOf(replacement))) {
    return;
  }
  const bool pane_leading = IsLeading(pane);
  const split_tabs::SplitTabId split = *pane->GetSplit();
  const double ratio = RatioOf(pane);
  std::vector<tabs::TabInterface*> panes;
  {
    base::AutoReset<bool> changing(&changing_, true);
    // Chromium's kReplace closes the replaced tab; Clair keeps it, so the
    // split ends and comes back, with its ID and ratio, around the other
    // pane and the replacement.
    strip()->RemoveSplit(split);
    std::vector<int> indices = {IndexOf(partner), IndexOf(replacement)};
    std::ranges::sort(indices);
    strip()->RestoreSplit(split, indices, SideBySide(ratio));
    tabs::TabInterface* leading = pane_leading ? replacement : partner;
    if (strip()->GetSplitData(split)->ListTabs().front() != leading) {
      strip()->ReverseTabsInSplit(split);
    }
    panes = strip()->GetSplitData(split)->ListTabs();
  }
  ActivateTab(replacement);
  // D8: the replaced tab is the row right below the split's.
  if (ClairSpaceTabs* lists = window_->space_tabs();
      lists && !lists->SpaceOf(pane).empty() && lists->PinOf(pane).empty()) {
    tabs::TabInterface* anchor = panes.back();
    if (!lists->SpaceOf(anchor).empty() && lists->PinOf(anchor).empty()) {
      lists->MoveTabBeside(pane, anchor, /*after=*/true);
    }
  }
  panes.push_back(pane);
  UpdateVisibility(panes);
  Changed(panes);
}

void ClairSplits::Swap(tabs::TabInterface* tab) {
  const std::vector<tabs::TabInterface*> panes = PanesOf(tab);
  if (panes.empty() || IndexOf(tab) == TabStripModel::kNoTab) {
    return;
  }
  {
    base::AutoReset<bool> changing(&changing_, true);
    strip()->ReverseTabsInSplit(*tab->GetSplit());
  }
  // D10: a pinned or favorited split's pins follow their panes.
  if (ClairSpaceTabs* lists = window_->space_tabs()) {
    clair::ClairPinStore* store = clair::ClairPinStore::Get();
    const clair::Pin* leading = store->Find(lists->PinOf(panes[0]));
    const clair::Pin* trailing = store->Find(lists->PinOf(panes[1]));
    if (leading && trailing && !leading->split.empty() &&
        leading->split == trailing->split) {
      store->SwapSplitPanes(leading->split);
    }
  }
  Changed(panes);
}

void ClairSplits::Separate(tabs::TabInterface* tab) {
  const std::vector<tabs::TabInterface*> panes = PanesOf(tab);
  if (panes.empty() || IndexOf(tab) == TabStripModel::kNoTab) {
    return;
  }
  {
    base::AutoReset<bool> changing(&changing_, true);
    strip()->RemoveSplit(*tab->GetSplit());
  }
  UpdateVisibility(panes);
  Changed(panes);
}

void ClairSplits::SetRatio(tabs::TabInterface* tab, double ratio) {
  if (PanesOf(tab).empty() || IndexOf(tab) == TabStripModel::kNoTab) {
    return;
  }
  strip()->UpdateSplitRatio(*tab->GetSplit(), ClampRatio(ratio));
}

// --- Links (D6) ---

bool ClairSplits::OpenLink(content::WebContents* source,
                           const content::OpenURLParams& params,
                           base::OnceCallback<void(content::NavigationHandle&)>&
                               navigation_handle_callback,
                           content::WebContents** result) {
  tabs::TabInterface* source_tab =
      source ? tabs::TabInterface::MaybeGetFromContents(source) : nullptr;
  if (IndexOf(source_tab) == TabStripModel::kNoTab) {
    return false;
  }
  ClairPeeks* peeks = window_->peeks();
  content::WebContents* target = nullptr;
  if (peeks && peeks->ParentOf(source_tab)) {
    // In a Peek, Option+click is a plain click.
    target = source;
  } else if (tabs::TabInterface* partner = PartnerOf(source_tab)) {
    // In a split, the link loads in the other pane, which Back returns from.
    target = partner->GetContents();
  } else {
    // A new tab right after the page, in the background, then the trailing,
    // focused pane of a split with it. Its row keeps the page's place.
    NavigateParams nav_params(window_->browser(), params.url, params.transition);
    nav_params.FillNavigateParamsFromOpenURLParams(params);
    nav_params.source_contents = source;
    nav_params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
    nav_params.tabstrip_index = IndexOf(source_tab) + 1;
    nav_params.tabstrip_add_types =
        AddTabTypes::ADD_FORCE_INDEX | AddTabTypes::ADD_INHERIT_OPENER;
    nav_params.window_action = NavigateParams::WindowAction::kNoAction;
    base::WeakPtr<content::NavigationHandle> handle = Navigate(&nav_params);
    if (navigation_handle_callback && handle) {
      std::move(navigation_handle_callback).Run(*handle);
    }
    *result = nav_params.navigated_or_inserted_contents;
    SplitWithNewPage(source_tab, *result);
    return true;
  }
  content::NavigationController::LoadURLParams load_params(params);
  base::WeakPtr<content::NavigationHandle> handle =
      target->GetController().LoadURLWithParams(load_params);
  if (navigation_handle_callback && handle) {
    std::move(navigation_handle_callback).Run(*handle);
  }
  if (target != source) {
    ActivateTab(tabs::TabInterface::MaybeGetFromContents(target));
  }
  // The source, so WebContentsImpl::OpenURL() takes no new contents, as
  // Chromium's own split-pane navigation returns.
  *result = source;
  return true;
}

bool ClairSplits::OpenLink(content::WebContents* source,
                           std::unique_ptr<content::WebContents>& new_contents,
                           const GURL& target_url,
                           content::WebContents** result) {
  tabs::TabInterface* source_tab =
      source ? tabs::TabInterface::MaybeGetFromContents(source) : nullptr;
  if (IndexOf(source_tab) == TabStripModel::kNoTab) {
    return false;
  }
  ClairPeeks* peeks = window_->peeks();
  content::WebContents* target = nullptr;
  if (peeks && peeks->ParentOf(source_tab)) {
    target = source;
  } else if (tabs::TabInterface* partner = PartnerOf(source_tab)) {
    target = partner->GetContents();
  } else if (new_contents) {
    // As for a link without a target: its contents, right after the page.
    NavigateParams nav_params(window_->browser(), std::move(new_contents));
    nav_params.source_contents = source;
    nav_params.url = target_url;
    // Already past the popup blocker, as chrome::AddWebContents says.
    nav_params.user_gesture = true;
    nav_params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
    nav_params.tabstrip_index = IndexOf(source_tab) + 1;
    nav_params.tabstrip_add_types =
        AddTabTypes::ADD_FORCE_INDEX | AddTabTypes::ADD_INHERIT_OPENER;
    nav_params.window_action = NavigateParams::WindowAction::kNoAction;
    Navigate(&nav_params);
    *result = nav_params.navigated_or_inserted_contents;
    SplitWithNewPage(source_tab, *result);
    return true;
  } else {
    return false;
  }
  if (target_url.is_valid()) {
    target->GetController().LoadURL(target_url, content::Referrer(),
                                    ui::PAGE_TRANSITION_LINK, std::string());
  }
  if (target != source) {
    ActivateTab(tabs::TabInterface::MaybeGetFromContents(target));
  }
  *result = nullptr;
  return true;
}

void ClairSplits::SplitWithNewPage(tabs::TabInterface* source,
                                   content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  if (!tab || IndexOf(tab) == TabStripModel::kNoTab) {
    return;
  }
  // From a pinned tab or favorite, whose row isn't in Today, the split's row
  // is the new tab's, at the top.
  if (ClairSpaceTabs* lists = window_->space_tabs();
      lists && (!lists->PinOf(source).empty() || lists->SpaceOf(source).empty())) {
    lists->MoveTab(tab, 0);
  }
  Make(source, tab, /*other_leading=*/false, 0.5, tab);
}

// --- Focus and visibility (D4, D5) ---

void ClairSplits::PaneFocused(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  if (!tab || !tab->IsSplit() || tab->IsActivated() ||
      IndexOf(tab) == TabStripModel::kNoTab) {
    return;
  }
  // Not from inside the page's focus notification.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairSplits> splits,
                        tabs::TabHandle handle) {
                       tabs::TabInterface* pane = handle.Get();
                       if (splits && pane && pane->IsSplit() &&
                           !pane->IsActivated()) {
                         splits->ActivateTab(pane);
                       }
                     },
                     weak_factory_.GetWeakPtr(), tab->GetHandle()));
}

void ClairSplits::Watch(tabs::TabInterface* tab) {
  if (!tab || watchers_.contains(tab->GetHandle())) {
    return;
  }
  watchers_[tab->GetHandle()] =
      std::make_unique<FocusWatcher>(this, tab->GetContents());
}

void ClairSplits::Unwatch(const tabs::TabInterface* tab) {
  if (tab) {
    watchers_.erase(tab->GetHandle());
  }
}

void ClairSplits::UpdateVisibility(
    const std::vector<tabs::TabInterface*>& panes) {
  content::WebContents* active = model_ ? model_->GetActiveWebContents() : nullptr;
  if (!active) {
    return;
  }
  const std::set<content::WebContents*> shown = window_->PagesShownWith(active);
  for (tabs::TabInterface* tab : panes) {
    if (!tab || IndexOf(tab) == TabStripModel::kNoTab) {
      continue;
    }
    content::WebContents* contents = tab->GetContents();
    contents->UpdateWebContentsVisibility(
        shown.contains(contents) && window_->IsVisible()
            ? content::Visibility::VISIBLE
            : content::Visibility::HIDDEN);
  }
}

void ClairSplits::LeadWith(split_tabs::SplitTabId split,
                           tabs::TabHandle leading) {
  tabs::TabInterface* tab = leading.Get();
  if (!model_ || !tab || !model_->ContainsSplit(split) ||
      tab->GetSplit() != split || IsLeading(tab)) {
    return;
  }
  base::AutoReset<bool> changing(&changing_, true);
  model_->ReverseTabsInSplit(split);
  Changed(PanesOf(tab));
}

void ClairSplits::KeepPinnedRatio(split_tabs::SplitTabId split) {
  ClairSpaceTabs* lists = window_->space_tabs();
  if (!lists || !model_ || !model_->ContainsSplit(split)) {
    return;
  }
  const std::vector<tabs::TabInterface*> panes =
      model_->GetSplitData(split)->ListTabs();
  if (panes.size() != 2) {
    return;
  }
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  const clair::Pin* leading = store->Find(lists->PinOf(panes[0]));
  const clair::Pin* trailing = store->Find(lists->PinOf(panes[1]));
  if (leading && trailing && !leading->split.empty() &&
      leading->split == trailing->split) {
    store->SetSplitRatio(
        leading->split,
        model_->GetSplitData(split)->visual_data()->split_ratio());
  }
}

void ClairSplits::Changed(const std::vector<tabs::TabInterface*>& panes) {
  if (ClairSpaceTabs* lists = window_->space_tabs()) {
    for (tabs::TabInterface* tab : panes) {
      if (tab) {
        lists->SplitChanged(tab);
      }
    }
  }
}

void ClairSplits::ActivateTab(tabs::TabInterface* tab) {
  const int index = IndexOf(tab);
  if (index != TabStripModel::kNoTab) {
    model_->ActivateTabAt(index,
                          TabStripUserGestureDetails(
                              TabStripUserGestureDetails::GestureType::kOther));
  }
}

// --- TabStripModelObserver ---

void ClairSplits::OnTabStripModelChanged(
    TabStripModel* model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  if (change.type() == TabStripModelChange::kRemoved) {
    for (const auto& removed : change.GetRemove()->contents) {
      Unwatch(removed.tab);
    }
  }
  if (!selection.active_tab_changed() || !selection.old_tab ||
      !selection.new_tab) {
    return;
  }
  // Arc: focusing the other pane closes the Peek open over a pane
  // (arc-reference, "A Peek in a split").
  ClairPeeks* peeks = window_->peeks();
  tabs::TabInterface* parent =
      peeks ? peeks->ParentOf(selection.old_tab.get()) : nullptr;
  if (parent && PartnerOf(parent) == selection.new_tab.get()) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ClairBrowserWindow> window,
                          tabs::TabHandle peek) {
                         if (window && window->peeks() && peek.Get()) {
                           window->peeks()->Close(peek.Get());
                         }
                       },
                       window_->GetWeakPtr(), selection.old_tab->GetHandle()));
  }
}

void ClairSplits::OnSplitTabChanged(const SplitTabChange& change) {
  if (change.model != model_) {
    return;
  }
  std::vector<tabs::TabInterface*> changed;
  switch (change.type) {
    case SplitTabChange::Type::kAdded: {
      const SplitTabChange::AddedChange* added = change.GetAddedChange();
      for (const auto& [tab, index] : added->tabs()) {
        changed.push_back(tab);
        Watch(tab);
      }
      // D6: a split Chromium made, from Option+click or the link's context
      // menu, puts the page the link was clicked in, the active tab then,
      // in the leading pane. Session restore and Reopen Closed Tab keep the
      // order they saved.
      tabs::TabInterface* active = model_->GetActiveTab();
      if (!changing_ &&
          added->reason() ==
              SplitTabChange::SplitTabAddReason::kNewSplitTabAdded &&
          !SessionRestore::IsRestoring(window_->browser()->GetProfile()) &&
          active && std::ranges::find(changed, active) != changed.end() &&
          changed.front() != active) {
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE,
            base::BindOnce(&ClairSplits::LeadWith, weak_factory_.GetWeakPtr(),
                           change.split_id, active->GetHandle()));
      }
      break;
    }
    case SplitTabChange::Type::kRemoved:
      for (const auto& [tab, index] : change.GetRemovedChange()->tabs()) {
        changed.push_back(tab);
        Unwatch(tab);
      }
      break;
    case SplitTabChange::Type::kContentsChanged:
      for (const auto& [tab, index] :
           change.GetContentsChange()->prev_tabs()) {
        changed.push_back(tab);
        Unwatch(tab);
      }
      for (const auto& [tab, index] : change.GetContentsChange()->new_tabs()) {
        changed.push_back(tab);
        Watch(tab);
      }
      break;
    case SplitTabChange::Type::kVisualsChanged:
      if (model_->ContainsSplit(change.split_id)) {
        changed = model_->GetSplitData(change.split_id)->ListTabs();
        if (!change.GetVisualsChange()->is_intermediate()) {
          KeepPinnedRatio(change.split_id);
        }
      }
      break;
  }
  // Not from inside the strip's notification: its pages' visibility and the
  // lists' pushes follow once it's done.
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* tab : changed) {
    if (tab) {
      handles.push_back(tab->GetHandle());
    }
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairSplits> splits,
                        std::vector<tabs::TabHandle> handles) {
                       if (!splits) {
                         return;
                       }
                       std::vector<tabs::TabInterface*> panes;
                       for (const tabs::TabHandle& handle : handles) {
                         if (tabs::TabInterface* tab = handle.Get()) {
                           panes.push_back(tab);
                         }
                       }
                       splits->UpdateVisibility(panes);
                       splits->Changed(panes);
                       if (ClairPeeks* peeks = splits->window_->peeks()) {
                         peeks->SplitsChanged();
                       }
                     },
                     weak_factory_.GetWeakPtr(), std::move(handles)));
}

void ClairSplits::OnTabStripModelDestroyed(TabStripModel* model) {
  watchers_.clear();
  model_ = nullptr;
}

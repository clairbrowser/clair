// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPLITS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPLITS_H_

#include <map>
#include <memory>
#include <optional>
#include <vector>

#include "base/functional/callback_forward.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/split_tabs/split_tab_id.h"
#include "components/tabs/public/tab_interface.h"
#include "ui/base/window_open_disposition.h"

class ClairBrowserWindow;
class GURL;
class TabStripModel;

namespace content {
class NavigationHandle;
class WebContents;
struct OpenURLParams;
}  // namespace content

// One native window's split view (add-split-view design D1). A Clair split
// is a Chromium split of two adjacent tabs in the window's strip: its ID is
// the SplitTabId, its ratio the split's ratio, and its pane order the strip's
// order. The active tab is the focused pane. This makes, changes and ends
// splits, focuses the pane the user clicks in (D4), opens Option+clicked
// links (D6) and keeps a pinned split's ratio in its record (D10).
class ClairSplits : public TabStripModelObserver {
 public:
  explicit ClairSplits(ClairBrowserWindow* window);
  ClairSplits(const ClairSplits&) = delete;
  ClairSplits& operator=(const ClairSplits&) = delete;
  ~ClairSplits() override;

  // --- Any tab of a native window ---
  // The other tab of `tab`'s split, or null outside a split.
  static tabs::TabInterface* PartnerOf(const tabs::TabInterface* tab);
  // The split's two tabs, leading pane first; empty outside a split.
  static std::vector<tabs::TabInterface*> PanesOf(const tabs::TabInterface* tab);
  // Whether `tab` is a split's leading pane.
  static bool IsLeading(const tabs::TabInterface* tab);
  // The leading pane's share of the width; 0.5 outside a split.
  static double RatioOf(const tabs::TabInterface* tab);
  // The pane of `tab`'s split the user looked at last, or `tab` outside a
  // split (spec "Selecting the split row").
  static tabs::TabInterface* LastFocusedPane(tabs::TabInterface* tab);

  // --- This window's tabs ---
  // D2: makes a split of `tab` and `other`, `other` leading when
  // `other_leading`, with `ratio`. `focus`, one of them or null, becomes
  // active. Both must be in this window's strip, and neither a Peek or in a
  // split. Returns whether it made the split.
  bool Make(tabs::TabInterface* tab,
            tabs::TabInterface* other,
            bool other_leading,
            double ratio,
            tabs::TabInterface* focus);
  // D2, D13b: a new tab page as the trailing, focused pane of `tab`'s split.
  void MakeWithNewTab(tabs::TabInterface* tab);
  // D8: `replacement` takes `pane`'s place in its split, focused; `pane`
  // leaves the split with its page.
  void Replace(tabs::TabInterface* pane, tabs::TabInterface* replacement);
  // Move Left and Move Right: swaps the panes, the focused one staying
  // focused.
  void Swap(tabs::TabInterface* tab);
  // Separate Tabs: ends `tab`'s split, both tabs keeping their pages, and
  // shows the focused pane's tab alone.
  void Separate(tabs::TabInterface* tab);
  void SetRatio(tabs::TabInterface* tab, double ratio);

  // D6: a link Option+clicked in `source`, a page of this window, which
  // reached the browser as NEW_SPLIT_VIEW: in a Peek it loads there, as a
  // plain click; in a split's pane it loads in the other pane, as a new
  // navigation, and focuses it; otherwise it opens in a new tab beside the
  // page, the trailing, focused pane of a split with it. Returns false when
  // `source` isn't this window's.
  bool OpenLink(content::WebContents* source,
                const content::OpenURLParams& params,
                base::OnceCallback<void(content::NavigationHandle&)>&
                    navigation_handle_callback,
                content::WebContents** result);
  // The same for a link with a target, whose contents Chromium made first;
  // they go when the link loads in the other pane or the Peek, and become the
  // new pane otherwise.
  bool OpenLink(content::WebContents* source,
                std::unique_ptr<content::WebContents>& new_contents,
                const GURL& target_url,
                content::WebContents** result);

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;
  void OnSplitTabChanged(const SplitTabChange& change) override;
  void OnTabStripModelDestroyed(TabStripModel* model) override;

 private:
  class FocusWatcher;

  TabStripModel* strip() const { return model_; }
  int IndexOf(const tabs::TabInterface* tab) const;
  // D6: the page `contents` a link opened beside `source` becomes the
  // trailing, focused pane of a split with it.
  void SplitWithNewPage(tabs::TabInterface* source,
                        content::WebContents* contents);
  // D4: a pane's page took keyboard focus, as from a click in it.
  void PaneFocused(content::WebContents* contents);
  void Watch(tabs::TabInterface* tab);
  void Unwatch(const tabs::TabInterface* tab);
  // D6: a split Chromium made puts the tab that was active, the one the link
  // was clicked in, in the leading pane.
  void LeadWith(split_tabs::SplitTabId split, tabs::TabHandle leading);
  // D5: both panes of the shown split are visible, and a page leaving it
  // isn't unless the window shows it otherwise.
  void UpdateVisibility(const std::vector<tabs::TabInterface*>& panes);
  // D10: a pinned or favorited split's ratio follows its open tabs'.
  void KeepPinnedRatio(split_tabs::SplitTabId split);
  void Changed(const std::vector<tabs::TabInterface*>& panes);
  void ActivateTab(tabs::TabInterface* tab);

  const raw_ptr<ClairBrowserWindow> window_;
  raw_ptr<TabStripModel> model_;
  std::map<tabs::TabHandle, std::unique_ptr<FocusWatcher>> watchers_;
  // While this changes splits itself.
  bool changing_ = false;
  base::WeakPtrFactory<ClairSplits> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_SPLITS_H_

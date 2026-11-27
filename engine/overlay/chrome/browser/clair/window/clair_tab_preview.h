// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_TAB_PREVIEW_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_TAB_PREVIEW_H_

#include "content/public/browser/web_contents_user_data.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/geometry/size_f.h"

namespace content {
class WebContents;
}  // namespace content

// The tab switcher's preview of a tab's page (add-tab-switcher-and-tabs-menu
// design D4): the page as it was when a window last hid it, kept on its
// WebContents, so it goes with the tab between windows and is freed with it.
// One per tab, replaced on each hide.
class ClairTabPreview : public content::WebContentsUserData<ClairTabPreview> {
 public:
  // The card's shape and the width a preview is kept at: 2× the card's
  // 157.5 points, so it stays sharp on a Retina screen.
  static constexpr int kWidth = 315;
  static constexpr double kAspect = 3.0 / 2.0;

  ClairTabPreview(const ClairTabPreview&) = delete;
  ClairTabPreview& operator=(const ClairTabPreview&) = delete;
  ~ClairTabPreview() override;

  // Keeps `copy` of `contents`'s page as its preview: the page's top, cut to
  // the card's shape and scaled to kWidth. An empty copy keeps the one before.
  static void Keep(content::WebContents* contents, const SkBitmap& copy);
  // The preview kept for `contents`, or an empty bitmap.
  static SkBitmap Get(content::WebContents* contents);

  // `copy`'s top, cut to `shape`'s width-to-height ratio (all of it when it's
  // wider than that), scaled down to `width` pixels when it's wider. Empty
  // for an empty copy or shape.
  static SkBitmap CutFromTop(const SkBitmap& copy,
                             const gfx::SizeF& shape,
                             int width);

 private:
  friend class content::WebContentsUserData<ClairTabPreview>;
  explicit ClairTabPreview(content::WebContents* contents);

  SkBitmap bitmap_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_TAB_PREVIEW_H_

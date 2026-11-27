// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_tab_preview.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "content/public/browser/web_contents.h"
#include "skia/ext/image_operations.h"
#include "third_party/skia/include/core/SkRect.h"

ClairTabPreview::ClairTabPreview(content::WebContents* contents)
    : content::WebContentsUserData<ClairTabPreview>(*contents) {}

ClairTabPreview::~ClairTabPreview() = default;

// static
void ClairTabPreview::Keep(content::WebContents* contents,
                           const SkBitmap& copy) {
  if (!contents) {
    return;
  }
  SkBitmap preview = CutFromTop(
      copy, gfx::SizeF(static_cast<float>(kAspect), 1.0f), kWidth);
  if (preview.drawsNothing()) {
    return;
  }
  GetOrCreateForWebContents(contents)->bitmap_ = std::move(preview);
}

// static
SkBitmap ClairTabPreview::Get(content::WebContents* contents) {
  ClairTabPreview* preview = contents ? FromWebContents(contents) : nullptr;
  return preview ? preview->bitmap_ : SkBitmap();
}

// static
SkBitmap ClairTabPreview::CutFromTop(const SkBitmap& copy,
                                     const gfx::SizeF& shape,
                                     int width) {
  if (copy.drawsNothing() || shape.IsEmpty() || width <= 0) {
    return SkBitmap();
  }
  // The page's top, fitted to the card's width (D4, `tab-switcher` "Cards").
  const int height = std::min(
      copy.height(),
      std::max(1, static_cast<int>(std::lround(copy.width() * shape.height() /
                                                shape.width()))));
  SkBitmap top;
  if (!copy.extractSubset(&top, SkIRect::MakeWH(copy.width(), height))) {
    return SkBitmap();
  }
  if (top.width() <= width) {
    // A bitmap of its own, so the whole page's copy can go.
    SkBitmap own;
    if (!own.tryAllocPixels(top.info()) ||
        !top.readPixels(own.pixmap(), 0, 0)) {
      return SkBitmap();
    }
    own.setImmutable();
    return own;
  }
  const int scaled_height = std::max(
      1, static_cast<int>(std::lround(static_cast<double>(height) * width /
                                      top.width())));
  SkBitmap scaled = skia::ImageOperations::Resize(
      top, skia::ImageOperations::RESIZE_GOOD, width, scaled_height);
  scaled.setImmutable();
  return scaled;
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(ClairTabPreview);

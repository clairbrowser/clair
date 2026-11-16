// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "ui/views/cocoa/clair_native_parent.h"

#import <AppKit/AppKit.h>

#include "base/apple/foundation_util.h"
#import "components/remote_cocoa/app_shim/native_widget_mac_nswindow.h"
#import "ui/base/cocoa/command_dispatcher.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"

namespace views {

namespace {

// Ordering a child window out removes it from its parent, and adding a hidden
// window as a child would order it in, so the widget is attached on each
// show. Deletes itself with the widget.
class NativeParentAttacher : public WidgetObserver {
 public:
  NativeParentAttacher(Widget* widget, NSWindow* parent) : parent_(parent) {
    widget->AddObserver(this);
    Attach(widget);
  }

  void Attach(Widget* widget) {
    NSWindow* child = widget->GetNativeWindow().GetNativeNSWindow();
    NSWindow* parent = parent_;
    if (!child || !parent || !child.visible) {
      return;
    }
    // Menu commands and their shortcuts, such as Close Tab, pass from a Views
    // window to its parent only while the parent looks key
    // (commandDispatchParent, native_widget_mac_nswindow.mm). A Views parent
    // keeps looking key while its child has focus; the native window doesn't,
    // so a page's alert would take Cmd+W and the File menu's tab commands away
    // from the window, and a page that alerts in a loop could only be closed
    // from the sidebar.
    NativeWidgetMacNSWindow* views_child =
        base::apple::ObjCCast<NativeWidgetMacNSWindow>(child);
    if (views_child &&
        [parent conformsToProtocol:@protocol(CommandDispatchingWindow)]) {
      views_child.commandDispatchParentOverride =
          static_cast<NSWindow<CommandDispatchingWindow>*>(parent);
    }
    if (child.parentWindow == parent) {
      return;
    }
    // A parentless window-modal dialog floats at the modal panel level, above
    // other apps' windows; as a child it belongs to its browser window.
    if (child.level == NSModalPanelWindowLevel) {
      child.level = parent.level;
    }
    [child.parentWindow removeChildWindow:child];
    [parent addChildWindow:child ordered:NSWindowAbove];
  }

  // WidgetObserver:
  void OnWidgetVisibilityChanged(Widget* widget, bool visible) override {
    if (visible) {
      Attach(widget);
    }
  }

  void OnWidgetDestroying(Widget* widget) override {
    widget->RemoveObserver(this);
    delete this;
  }

 private:
  __weak NSWindow* parent_;
};

}  // namespace

void ClairAttachToNativeParent(Widget* widget, gfx::NativeView parent) {
  NSWindow* window = parent.GetNativeNSView().window;
  static Class native_window_class = NSClassFromString(@"ClairNativeWindow");
  if (!widget || !native_window_class ||
      ![window isKindOfClass:native_window_class]) {
    return;
  }
  // A window-modal dialog is made titled so that it can be a sheet, with its
  // content under the title bar (native_widget_mac.mm, StyleMaskForParams).
  // Without a Views parent it can't be a sheet, and the title bar would cover
  // the top of the dialog, so it's made transparent.
  NSWindow* child = widget->GetNativeWindow().GetNativeNSWindow();
  const NSWindowStyleMask sheet_mask =
      NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView;
  if ((child.styleMask & sheet_mask) == sheet_mask) {
    child.titlebarAppearsTransparent = YES;
    child.titleVisibility = NSWindowTitleHidden;
  }
  new NativeParentAttacher(widget, window);
}

}  // namespace views

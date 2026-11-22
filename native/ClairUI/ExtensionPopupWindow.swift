// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// An extension's popup page, in a small titled window that first opens beside
/// the sidebar button that opened it (arc-extension-experience D6), or, while
/// the toolbar shows, at a fixed place over it (add-page-toolbar D6). It's a
/// child window rather than an NSPopover, whose material tints the page it
/// hosts (Crest found on macOS 27). A click elsewhere, Esc, its close button,
/// or the browser window moving dismisses it.
final class ExtensionPopupWindow: NSWindow {
  static let gap: CGFloat = 6
  static let screenMargin: CGFloat = 8
  /// Arc's popups from the toolbar: the window's top-trailing corner at the
  /// card's top edge, this far in from its trailing edge, whichever tile
  /// opened it.
  static let toolbarInset: CGFloat = 40

  /// Where the popup first opens.
  enum Placement: Equatable {
    /// Beside the button that opened it.
    case besideAnchor
    /// With its frame's top-trailing corner here, in the parent window's
    /// coordinates.
    case topTrailing(NSPoint)
  }

  private weak var parentWindowRef: NSWindow?
  /// The button, in the parent window's coordinates. A click on it only
  /// closes the popup.
  private let anchor: NSRect
  private let placement: Placement
  private var onDismiss: (() -> Void)?
  private var monitor: Any?
  /// Set while dismiss() closes the window, so close() doesn't start it again.
  private var isDismissing = false

  init(
    page: NSView, size: NSSize, name: String, parent: NSWindow, anchor: NSRect, placement: Placement = .besideAnchor,
    onDismiss: @escaping () -> Void
  ) {
    self.parentWindowRef = parent
    self.anchor = anchor
    self.placement = placement
    self.onDismiss = onDismiss
    super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    animationBehavior = .none
    collectionBehavior = [.transient, .ignoresCycle]
    // Only VoiceOver and the window list read the name.
    title = name
    titleVisibility = .hidden
    let container = NSView(frame: NSRect(origin: .zero, size: size))
    container.autoresizesSubviews = true
    page.frame = container.bounds
    page.autoresizingMask = [.width, .height]
    container.addSubview(page)
    contentView = container
    setAccessibilityIdentifier("clair.extensionPopup")
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  func present() {
    guard let parent = parentWindowRef else { return }
    switch placement {
    case .besideAnchor:
      placeBesideAnchor()
    case .topTrailing(let corner):
      let screenCorner = parent.convertPoint(toScreen: corner)
      let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
      setFrame(Self.frame(size: frame.size, topTrailing: screenCorner, visible: visible), display: true)
    }
    parent.addChildWindow(self, ordered: .above)
    makeKeyAndOrderFront(nil)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) {
      [weak self] event in
      guard let self else { return event }
      // A confirmation the popup's own page asked for: it stays open to hear
      // the answer.
      if event.window?.isSheet == true {
        return event
      }
      if event.type == .keyDown {
        if event.keyCode == 53 {  // Esc
          self.dismiss()
          return nil
        }
        return event
      }
      if event.window === self {
        return event
      }
      // A click on the button that opened the popup only closes it.
      let onButton =
        event.window === self.parentWindowRef && event.type == .leftMouseDown
        && self.anchor.insetBy(dx: -2, dy: -2).contains(event.locationInWindow)
      self.dismiss()
      return onButton ? nil : event
    }
  }

  /// The close button: the same as any other way the user closes it. The
  /// button closes the window directly, not through performClose(_:), so
  /// this is where its click arrives.
  override func close() {
    if isDismissing {
      super.close()
    } else {
      dismiss()
    }
  }

  /// The page resized itself: the window keeps its top-leading corner, which
  /// may not be beside the button any more if the user dragged it, or, over
  /// the toolbar, its top-trailing corner, as Arc's popups do.
  func resize(to size: NSSize) {
    let outer = frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    setFrame(onScreen(Self.resized(frame, to: outer, placement: placement), on: screen), display: true)
  }

  /// `frame` resized to `size`, keeping the corner its placement keeps.
  static func resized(_ frame: NSRect, to size: NSSize, placement: Placement) -> NSRect {
    let x = placement == .besideAnchor ? frame.minX : frame.maxX - size.width
    return NSRect(x: x, y: frame.maxY - size.height, width: size.width, height: size.height)
  }

  /// Puts the popup beside the button.
  private func placeBesideAnchor() {
    guard let parent = parentWindowRef else { return }
    let button = parent.convertToScreen(anchor)
    let size = frame.size
    let frame = NSRect(x: button.maxX + Self.gap, y: button.maxY - size.height, width: size.width, height: size.height)
    // Not the popup's own screen: until it's placed, that's the primary display.
    setFrame(onScreen(frame, on: parent.screen), display: true)
  }

  /// A popup of `size` with its top-trailing corner at `corner`, on screen
  /// coordinates, kept inside `visible`.
  static func frame(size: NSSize, topTrailing corner: NSPoint, visible: NSRect) -> NSRect {
    let frame = NSRect(x: corner.x - size.width, y: corner.y - size.height, width: size.width, height: size.height)
    return clamp(frame, to: visible)
  }

  private func onScreen(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
    Self.clamp(frame, to: (screen ?? NSScreen.main)?.visibleFrame ?? .infinite)
  }

  private static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
    var frame = frame
    frame.origin.x = min(max(frame.minX, visible.minX + screenMargin), visible.maxX - screenMargin - frame.width)
    frame.origin.y = min(max(frame.minY, visible.minY + screenMargin), visible.maxY - screenMargin - frame.height)
    return frame
  }

  /// Closes the popup; `notify` tells Chromium the user closed it.
  func dismiss(notify: Bool = true) {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    parent?.removeChildWindow(self)
    orderOut(nil)
    // The page belongs to Chromium; let go of it.
    contentView?.subviews.forEach { $0.removeFromSuperview() }
    contentView = NSView()
    isDismissing = true
    close()
    let callback = onDismiss
    onDismiss = nil
    if notify {
      callback?()
    }
  }
}

// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// The favorites' drop target: an AppKit view over the grid or the empty
/// box, since SwiftUI's drops can't reach the drag image. Over it, a dragged
/// row or tile turns into the tile it would become, the size of the slot it
/// would take, as in Arc, and the drag is a move, with no "+" on the pointer.
/// Clicks go through it to the tiles.
struct FavoritesDropArea: NSViewRepresentable {
  /// The slot a drop at a point, from the area's top-leading corner, takes.
  let slot: (CGPoint) -> Int
  /// The size of a tile in that slot.
  let tileSize: (Int) -> CGSize
  /// The icon of what's dragged.
  let icon: (SidebarDragItem) -> NSImage?
  /// The slot the drag is over, or nil once it leaves or drops.
  let onTarget: (Int?) -> Void
  let onDrop: (SidebarDragItem, Int) -> Void

  func makeNSView(context: Context) -> FavoritesDropView {
    let view = FavoritesDropView()
    view.area = self
    return view
  }

  func updateNSView(_ view: FavoritesDropView, context: Context) {
    view.area = self
    view.colorScheme = context.environment.colorScheme
  }
}

final class FavoritesDropView: NSView {
  var area: FavoritesDropArea?
  var colorScheme: ColorScheme = .light

  /// What's dragged, read once it enters.
  private var item: SidebarDragItem?
  /// Each dragging item's own image and its frame from the pointer, to put
  /// back if the drag leaves.
  private var originals: [Int: (offset: CGPoint, size: CGSize, components: [NSDraggingImageComponent])] = [:]
  /// The tile the image shows, by slot size, so it's drawn once per size.
  private var tile: (size: CGSize, image: NSImage)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([NSPasteboard.PasteboardType(SidebarDragItem.type.identifier)])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override var isFlipped: Bool { true }

  // Clicks, hovers and menus go to the tiles beneath.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let payload = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(SidebarDragItem.type.identifier))
    item = payload.flatMap(SidebarDragItem.init(payload:))
    originals = [:]
    return update(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    update(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    if let sender { restore(sender) }
    area?.onTarget(nil)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let item, let area else { return false }
    let slot = area.slot(convert(sender.draggingLocation, from: nil))
    area.onTarget(nil)
    area.onDrop(item, slot)
    return true
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) {
    item = nil
    originals = [:]
    area?.onTarget(nil)
  }

  private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let item, let area else { return [] }
    let point = convert(sender.draggingLocation, from: nil)
    let slot = area.slot(point)
    area.onTarget(slot)
    morph(sender, at: point, into: tileImage(for: item, size: area.tileSize(slot)))
    // A move, which every sidebar drag allows, draws no badge.
    return sender.draggingSourceOperationMask.contains(.move) ? .move : .generic
  }

  private func tileImage(for item: SidebarDragItem, size: CGSize) -> NSImage? {
    if let tile, tile.size == size { return tile.image }
    guard let area, size.width > 0, size.height > 0 else { return nil }
    let renderer = ImageRenderer(content: DraggedTile(icon: area.icon(item), size: size, colorScheme: colorScheme))
    renderer.scale = window?.backingScaleFactor ?? 2
    guard let image = renderer.nsImage else { return nil }
    tile = (size, image)
    return image
  }

  /// Shows `image`, centred on the pointer, for every dragging item.
  private func morph(_ sender: any NSDraggingInfo, at point: CGPoint, into image: NSImage?) {
    guard let image else { return }
    sender.enumerateDraggingItems(
      options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]
    ) { [self] draggingItem, index, _ in
      if originals[index] == nil {
        let frame = draggingItem.draggingFrame
        originals[index] = (
          CGPoint(x: frame.minX - point.x, y: frame.minY - point.y), frame.size, draggingItem.imageComponents ?? []
        )
      }
      let size = image.size
      draggingItem.setDraggingFrame(
        NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
        contents: image)
    }
  }

  /// Puts each dragging item's own image back, as far from the pointer as
  /// it was.
  private func restore(_ sender: any NSDraggingInfo) {
    guard !originals.isEmpty else { return }
    let point = convert(sender.draggingLocation, from: nil)
    sender.enumerateDraggingItems(
      options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]
    ) { [self] draggingItem, index, _ in
      guard let original = originals[index] else { return }
      let components = original.components
      draggingItem.draggingFrame = NSRect(
        origin: CGPoint(x: point.x + original.offset.x, y: point.y + original.offset.y), size: original.size)
      draggingItem.imageComponentsProvider = { components }
    }
    originals = [:]
  }
}

/// The tile a dragged row or tile shows over the favorites: a selected tile
/// with its icon, lifted.
struct DraggedTile: View {
  let icon: NSImage?
  let size: CGSize
  let colorScheme: ColorScheme

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: FavoriteTile.cornerRadius, style: .continuous)
        .fill(PinFill.tile(colorScheme, hovered: false, selected: true))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
      PinIcon(icon: icon, size: FavoriteTile.iconSize)
    }
    .frame(width: size.width, height: size.height)
    // Room for the shadow.
    .padding(4)
    .environment(\.colorScheme, colorScheme)
  }
}

/// The area above the Space header while a profile has no favorites and the
/// "Drag to add Favorites" box doesn't show (show-favorites-drop-zone D1): a
/// sidebar drag entering it opens the drop zone, as in Arc, and a drop there
/// makes the first favorite. Like `FavoritesDropArea`, clicks go through it.
struct FavoritesDropTrigger: NSViewRepresentable {
  let onEnter: () -> Void
  let onDrop: (SidebarDragItem) -> Void

  func makeNSView(context: Context) -> FavoritesDropTriggerView {
    let view = FavoritesDropTriggerView()
    view.trigger = self
    return view
  }

  func updateNSView(_ view: FavoritesDropTriggerView, context: Context) {
    view.trigger = self
  }
}

final class FavoritesDropTriggerView: NSView {
  var trigger: FavoritesDropTrigger?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([NSPasteboard.PasteboardType(SidebarDragItem.type.identifier)])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  // Clicks, hovers and the window drag go to the views beneath.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard item(of: sender) != nil else { return [] }
    trigger?.onEnter()
    return operation(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    operation(sender)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let item = item(of: sender), let trigger else { return false }
    trigger.onDrop(item)
    return true
  }

  private func item(of sender: any NSDraggingInfo) -> SidebarDragItem? {
    sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(SidebarDragItem.type.identifier))
      .flatMap(SidebarDragItem.init(payload:))
  }

  // A move, which every sidebar drag allows, draws no badge.
  private func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
    sender.draggingSourceOperationMask.contains(.move) ? .move : .generic
  }
}

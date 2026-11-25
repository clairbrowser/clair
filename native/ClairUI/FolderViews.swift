// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// A folder's row in the pinned section (add-tab-folders design D4, D5): its
/// icon and name, the hover pill, a click that opens or closes it, and the −
/// button, "Close This Folder", while any of its tabs is open. A drop on the
/// row's middle makes the dragged row the folder's first tab.
struct FolderRow: View {
  let folder: any ClairFolder
  var moveTargets: [any ClairSpace] = []
  /// The rename in progress on this row, if any.
  var rename: RowRename?
  weak var actions: (any SidebarActions)?

  @State private var isHovered = false
  /// Whether a row or tile dragged over the row's middle would land in it.
  @State private var isDropTarget = false
  @Environment(\.colorScheme) private var colorScheme

  /// Arc's folder name: the row's font, bold.
  static let nameNSFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
  static let nameFont = Font(nameNSFont)
  /// How far a folder's tabs are indented, as Arc's.
  static let indent: CGFloat = 16

  var body: some View {
    let folderID = folder.folderID
    HStack(spacing: TabRow.titleGap) {
      // Arc's icon is wider than a favicon, centred where favicons are, so
      // the name lines up with the tabs' titles.
      FolderIcon(state: PinsLogic.folderIcon(folder))
        .frame(width: FolderIcon.width, height: TabRow.iconSize)
        .padding(.horizontal, (TabRow.iconSize - FolderIcon.width) / 2)
        // The folder's state, which the row can't carry as a value.
        .accessibilityElement()
        .accessibilityLabel(FolderIcon.label(PinsLogic.folderIcon(folder)))
        .accessibilityIdentifier("clair.folderIcon")
      if let rename {
        RenameField(
          text: folder.name, placeholder: PinsLogic.folderNamePlaceholder, rename: rename, current: folder.name,
          font: Self.nameNSFont,
          change: { draft, current in PinsLogic.folderNameChange(draft: draft, current: current ?? "") }
        ) { change in
          actions?.endRenaming(.folder(folderID), change: change)
        }
      } else {
        Text(folder.name).font(Self.nameFont).lineLimit(1)
          .accessibilityIdentifier("clair.folderName")
      }
      Spacer(minLength: 0)
      if PinsLogic.showsCloseFolder(folder, isHovered: isHovered) && rename == nil {
        IconButton(
          systemImage: "minus", help: PinsLogic.closeFolderHelp, size: TabRow.closeSize, glyphSize: 12,
          glyphWeight: .bold, dimsWhenInactive: false
        ) {
          actions?.closeTabs(inFolder: folderID)
        }
        .padding(.trailing, TabRow.closeTrailing - TabRow.horizontalPadding)
        .accessibilityIdentifier("clair.folderClose")
      }
    }
    .padding(.horizontal, TabRow.horizontalPadding)
    .frame(height: TabRow.pillHeight)
    .background {
      if isHovered || isDropTarget {
        RoundedRectangle(cornerRadius: TabRow.cornerRadius, style: .continuous).fill(SidebarFill.hover(colorScheme))
      }
    }
    .padding(.top, TabRow.pillInset)
    .padding(.bottom, TabRow.pillInset + TabRow.spacing)
    .contentShape(Rectangle())
    .onTapGesture {
      guard rename == nil else { return }
      actions?.toggleFolder(folderID)
    }
    .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: menuItems))
    // D5: the row's middle half takes drops; its edges are the list's gaps.
    .overlay {
      GeometryReader { geometry in
        FolderDropArea(
          onTarget: { isDropTarget = $0 },
          onDrop: { item in actions?.drop(item, on: .folder(folderID, 0)) }
        )
        .frame(height: geometry.size.height / 2)
        .offset(y: geometry.size.height / 4)
      }
    }
    .onHover { isHovered = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(folder.name)
    .accessibilityIdentifier("clair.folderRow")
  }

  /// The folder's menu (tab-folders spec, "Folder menu").
  private var menuItems: [RowClickCatcher.Item] {
    let folderID = folder.folderID
    return PinsLogic.folderMenu(name: folder.name, canMoveToSpace: !moveTargets.isEmpty).map { item in
      guard let item else { return .separator }
      switch item.command {
      case .moveToSpace:
        return .submenu(
          item.title,
          moveTargets.map { space in
            let spaceID = space.spaceID
            return .action(SpacesLogic.label(of: space)) { [weak actions] in
              actions?.moveFolder(folderID, toSpace: spaceID)
            }
          })
      default:
        return .action(item.title) { [weak actions] in
          switch item.command {
          case .turnIntoSpace: actions?.turnFolderIntoSpace(folderID)
          case .rename: actions?.beginRenaming(RowRename(row: .folder(folderID), selectsAll: true, caret: nil))
          case .duplicate: actions?.duplicateFolder(folderID)
          case .deleteFolder: actions?.deleteFolder(folderID)
          default: break
          }
        }
      }
    }
  }
}

/// A folder's icon, drawn: open while the folder is open, closed while it's
/// closed, with "•••" inside while it's closed and one of its tabs is open,
/// as Arc's. SF Symbols has no open folder.
struct FolderIcon: View {
  let state: PinsLogic.FolderIcon

  /// The box the paths are drawn in, which is Arc's icon's size in points.
  static let box = CGSize(width: 20, height: 18)
  static let width = box.width

  /// What VoiceOver, and the runtime suite, read for each state.
  static func label(_ state: PinsLogic.FolderIcon) -> String {
    switch state {
    case .open: "Open"
    case .closed: "Closed"
    case .closedWithOpenTabs: "Closed, with open tabs"
    }
  }
  /// The outline's width, in points of the box.
  static let lineWidth: CGFloat = 1.5

  var body: some View {
    Canvas { context, size in
      let box = Self.box
      let scale = min(size.width / box.width, size.height / box.height)
      context.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
      context.scaleBy(x: scale, y: scale)
      let style = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
      let shading = GraphicsContext.Shading.foreground
      switch state {
      case .open:
        context.stroke(Self.openBack, with: shading, style: style)
        context.stroke(Self.openFront, with: shading, style: style)
      case .closed, .closedWithOpenTabs:
        context.stroke(Self.closed, with: shading, style: style)
        if state == .closedWithOpenTabs {
          for x in [6.6, 10.0, 13.4] {
            context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: 11.6 - 1.1, width: 2.2, height: 2.2)), with: shading)
          }
        }
      }
    }
  }

  /// A closed folder: the body with its tab, and the line under the tab.
  static let closed: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 1.75, y: 7))
    path.addLine(to: CGPoint(x: 1.75, y: 3.6))
    path.addQuadCurve(to: CGPoint(x: 3.35, y: 2), control: CGPoint(x: 1.75, y: 2))
    path.addLine(to: CGPoint(x: 6.9, y: 2))
    path.addLine(to: CGPoint(x: 8.6, y: 4))
    path.addLine(to: CGPoint(x: 16.65, y: 4))
    path.addQuadCurve(to: CGPoint(x: 18.25, y: 5.6), control: CGPoint(x: 18.25, y: 4))
    path.addLine(to: CGPoint(x: 18.25, y: 14.65))
    path.addQuadCurve(to: CGPoint(x: 16.65, y: 16.25), control: CGPoint(x: 18.25, y: 16.25))
    path.addLine(to: CGPoint(x: 3.35, y: 16.25))
    path.addQuadCurve(to: CGPoint(x: 1.75, y: 14.65), control: CGPoint(x: 1.75, y: 16.25))
    path.closeSubpath()
    path.move(to: CGPoint(x: 1.75, y: 7))
    path.addLine(to: CGPoint(x: 18.25, y: 7))
    return path
  }()

  /// An open folder: the back with its tab, and the front flap leaning out.
  static let openBack: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 1.75, y: 16.25))
    path.addLine(to: CGPoint(x: 1.75, y: 3.6))
    path.addQuadCurve(to: CGPoint(x: 3.35, y: 2), control: CGPoint(x: 1.75, y: 2))
    path.addLine(to: CGPoint(x: 6.9, y: 2))
    path.addLine(to: CGPoint(x: 8.6, y: 4))
    path.addLine(to: CGPoint(x: 14.9, y: 4))
    path.addQuadCurve(to: CGPoint(x: 16.5, y: 5.6), control: CGPoint(x: 16.5, y: 4))
    path.addLine(to: CGPoint(x: 16.5, y: 7.25))
    return path
  }()

  static let openFront: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 1.75, y: 16.25))
    path.addLine(to: CGPoint(x: 4.6, y: 8.4))
    path.addQuadCurve(to: CGPoint(x: 6.1, y: 7.25), control: CGPoint(x: 4.95, y: 7.25))
    path.addLine(to: CGPoint(x: 18.6, y: 7.25))
    path.addQuadCurve(to: CGPoint(x: 19.1, y: 8.1), control: CGPoint(x: 19.4, y: 7.25))
    path.addLine(to: CGPoint(x: 16.4, y: 15.4))
    path.addQuadCurve(to: CGPoint(x: 15.2, y: 16.25), control: CGPoint(x: 16.1, y: 16.25))
    path.closeSubpath()
    return path
  }()
}

/// The middle of a folder's row as a drop target (add-tab-folders D5): an
/// AppKit view, since the list's table view takes drags before a SwiftUI
/// drop target on a row is asked. Clicks, hovers and menus go through it to
/// the row, and drags near the row's edges reach the list's gaps.
struct FolderDropArea: NSViewRepresentable {
  /// Whether a row or tile that can land in the folder is over it.
  let onTarget: (Bool) -> Void
  let onDrop: (SidebarDragItem) -> Void

  func makeNSView(context: Context) -> FolderDropView {
    let view = FolderDropView()
    view.area = self
    return view
  }

  func updateNSView(_ view: FolderDropView, context: Context) {
    view.area = self
  }
}

final class FolderDropView: NSView {
  var area: FolderDropArea?
  private var item: SidebarDragItem?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([NSPasteboard.PasteboardType(SidebarDragItem.type.identifier)])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    item = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(SidebarDragItem.type.identifier))
      .flatMap(SidebarDragItem.init(payload:))
    return operation(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    operation(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    area?.onTarget(false)
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) {
    item = nil
    area?.onTarget(false)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let item, Self.accepts(item), let area else { return false }
    area.onTarget(false)
    area.onDrop(item)
    return true
  }

  /// A folder holds no folders (D1).
  static func accepts(_ item: SidebarDragItem) -> Bool {
    if case .folder = item { return false }
    return true
  }

  private func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let item, Self.accepts(item) else {
      area?.onTarget(false)
      return []
    }
    area?.onTarget(true)
    // A move, which every sidebar drag allows, draws no badge.
    return sender.draggingSourceOperationMask.contains(.move) ? .move : .generic
  }
}

/// Gives the list's table view the sidebar's own menu (add-tab-folders D10),
/// for right-clicks that land on no row: each row's own catcher takes the
/// clicks on it first. Put it inside a row, where it can reach the table.
struct TableMenuInstaller: NSViewRepresentable {
  /// The menu's items, or nil for none, as in incognito and guest windows.
  let items: [RowClickCatcher.Item]?

  func makeNSView(context: Context) -> InstallerView {
    InstallerView()
  }

  func updateNSView(_ view: InstallerView, context: Context) {
    view.items = items
    view.install()
  }

  final class InstallerView: NSView, NSMenuDelegate {
    var items: [RowClickCatcher.Item]?
    /// Runs the items' actions.
    private let target = RowClickCatcher.CatcherView()
    private lazy var sidebarMenu: NSMenu = {
      let menu = NSMenu()
      menu.delegate = self
      return menu
    }()

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      install()
    }

    // Clicks go to the row.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func install() {
      guard let table = enclosingScrollView?.documentView as? NSTableView else { return }
      table.menu = items == nil ? nil : sidebarMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
      menu.removeAllItems()
      menu.autoenablesItems = false
      let built = RowClickCatcher.CatcherView.menu(items ?? [], target: target)
      for item in built.items {
        built.removeItem(item)
        menu.addItem(item)
      }
    }
  }
}

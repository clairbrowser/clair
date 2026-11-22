// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import SwiftUI

/// The bookmark dialog (add-bookmarks-menu design D4, D5): Dia's controls on
/// a Clair dialog. Its content is a Name row and a Folder row, Remove its
/// leading button and Done its one button. Adding and editing share it; only
/// the title differs. Done, Return and Esc save, as Esc does in Dia.
@MainActor
enum BookmarkDialog {
  // MARK: Wording

  static let addedTitle = "Bookmark Added"
  static let editTitle = "Edit Bookmark"
  static let nameLabel = "Name"
  static let folderLabel = "Folder"
  /// What the dialog calls Other Bookmarks (D6).
  static let rootFolderTitle = "Bookmarks"
  static let newFolder = "New Folder…"
  static let newFolderPlaceholder = "New folder name…"
  static let cancelNewFolder = "Cancel New Folder"
  static let manageBookmarks = "Manage Bookmarks"
  static let remove = "Remove"
  static let done = "Done"

  // MARK: Metrics, from Dia's (dia-reference/README.md)

  static let labelWidth: CGFloat = 68
  static let rowHeight: CGFloat = 36
  static let rowSpacing: CGFloat = 12
  static let fieldCornerRadius: CGFloat = 8

  static func title(isNew: Bool) -> String {
    isNew ? addedTitle : editTitle
  }

  static func page(state: BookmarkDialogState) -> ClairDialogPage {
    ClairDialogPage(
      title: title(isNew: state.isNew),
      content: AnyView(BookmarkDialogContent(state: state)),
      buttons: [ClairDialogButton(title: done, role: .default)],
      leadingButton: ClairDialogButton(
        title: remove, role: .cancel,
        action: { dialog in
          state.remove()
          dialog.answer(.cancelled)
        }),
      escapePressesDefault: true)
  }

  /// Shows the dialog for `bookmark` on `presenter`'s window. However it
  /// closes, apart from Remove, it saves the name and folder through
  /// `browser`. Manage Bookmarks in the folder popup saves, closes, then runs
  /// `manageBookmarks`.
  @discardableResult
  static func show(
    _ bookmark: any ClairBookmark, browser: any ClairBrowser, on presenter: ClairDialogPresenter,
    manageBookmarks: @escaping @MainActor () -> Void = performManageBookmarks
  ) -> (ClairDialog, BookmarkDialogState) {
    let state = BookmarkDialogState(bookmark: bookmark, browser: browser)
    let dialog = ClairDialog(page(state: state))
    state.onDone = { [weak dialog] in
      dialog?.answer(.accepted)
    }
    presenter.show(dialog) { _ in
      guard !state.isRemoved else { return }
      state.save()
      if state.opensManager {
        manageBookmarks()
      }
    }
    return (dialog, state)
  }

  /// Runs the main menu's Manage Bookmarks item, as Option+Cmd+B does, so it
  /// switches to an open `chrome://bookmarks` tab rather than adding one.
  static func performManageBookmarks() {
    guard let item = MainMenuTitles.item(withTag: MainMenuTitles.bookmarkManagerTag, in: NSApp.mainMenu),
      let menu = item.menu
    else { return }
    menu.performActionForItem(at: menu.index(of: item))
  }
}

/// What the bookmark dialog is editing: the name, the folder, and the New
/// Folder… field while it shows.
@MainActor
@Observable
final class BookmarkDialogState {
  /// A folder in the popup, "Bookmarks" for Other Bookmarks itself.
  struct Folder: Equatable {
    let id: BookmarkFolderID
    let title: String
    let depth: Int
  }

  enum Field: Hashable {
    case name
    case newFolder
  }

  let bookmarkID: BookmarkID
  let isNew: Bool
  var name: String
  private(set) var folders: [Folder] = []
  private(set) var folderID: BookmarkFolderID
  /// Whether the folder popup is the New Folder… field.
  private(set) var isAddingFolder = false
  var newFolderName = ""
  /// Bumped with the field that should take keyboard focus.
  private(set) var focusRequest: (field: Field, count: Int) = (.name, 0)
  /// Remove deleted the bookmark: closing saves nothing.
  private(set) var isRemoved = false
  /// Manage Bookmarks closed the dialog: the manager opens once it's saved.
  private(set) var opensManager = false
  /// Closes the dialog as Done does.
  @ObservationIgnored var onDone: (@MainActor () -> Void)?

  @ObservationIgnored private weak var browser: (any ClairBrowser)?

  init(bookmark: any ClairBookmark, browser: any ClairBrowser) {
    bookmarkID = bookmark.bookmarkID
    isNew = bookmark.isNew
    name = bookmark.title
    folderID = bookmark.folderID
    self.browser = browser
    reloadFolders()
  }

  /// The popup's folders, from the browser: Other Bookmarks first, as
  /// "Bookmarks", and its folders under it.
  func reloadFolders() {
    folders = (browser?.bookmarkFolders ?? []).map { folder in
      Folder(
        id: folder.folderID, title: folder.depth == 0 ? BookmarkDialog.rootFolderTitle : folder.title,
        depth: folder.depth)
    }
  }

  func chooseFolder(_ id: BookmarkFolderID) {
    if folders.contains(where: { $0.id == id }) {
      folderID = id
    }
  }

  /// New Folder…: the popup turns into a field.
  func beginNewFolder() {
    newFolderName = ""
    isAddingFolder = true
    focus(.newFolder)
  }

  /// ×, or Esc in the field: the popup comes back unchanged.
  func cancelNewFolder() {
    isAddingFolder = false
    newFolderName = ""
    focus(.name)
  }

  /// Return in the field: adds the folder to Bookmarks and selects it, with
  /// focus back in Name. A name that's empty once trimmed does nothing.
  func commitNewFolder() {
    guard let browser else { return }
    let title = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    let id = browser.addBookmarkFolder(title)
    guard id != ClairBookmarkFolderIDNone else { return }
    reloadFolders()
    chooseFolder(id)
    isAddingFolder = false
    newFolderName = ""
    focus(.name)
  }

  /// Manage Bookmarks in the popup: saves and closes, then opens the manager.
  func chooseManageBookmarks() {
    opensManager = true
    onDone?()
  }

  /// Return in Name.
  func submitName() {
    onDone?()
  }

  func save() {
    browser?.updateBookmark(bookmarkID, title: name, folder: folderID)
  }

  func remove() {
    isRemoved = true
    browser?.removeBookmark(bookmarkID)
  }

  private func focus(_ field: Field) {
    focusRequest = (field, focusRequest.count + 1)
  }
}

/// The dialog's two rows: Name and its field, Folder and its popup or the
/// New Folder… field.
struct BookmarkDialogContent: View {
  @Bindable var state: BookmarkDialogState
  @FocusState private var focusedField: BookmarkDialogState.Field?

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: BookmarkDialog.rowSpacing) {
      GridRow {
        label(BookmarkDialog.nameLabel)
        BookmarkFieldBox(isFocused: focusedField == .name) {
          TextField(BookmarkDialog.nameLabel, text: $state.name)
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .name)
            .onSubmit { state.submitName() }
            .accessibilityIdentifier("clair.bookmarkName")
        }
      }
      GridRow {
        label(BookmarkDialog.folderLabel)
        if state.isAddingFolder {
          BookmarkFieldBox(isFocused: focusedField == .newFolder) {
            HStack(spacing: 6) {
              TextField(BookmarkDialog.newFolderPlaceholder, text: $state.newFolderName)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .newFolder)
                .onSubmit { state.commitNewFolder() }
                .onExitCommand { state.cancelNewFolder() }
                .onAppear { focusedField = .newFolder }
                .accessibilityLabel(BookmarkDialog.newFolderPlaceholder)
                .accessibilityIdentifier("clair.bookmarkNewFolderName")
              Button {
                state.cancelNewFolder()
              } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(.secondary)
                  .frame(width: 20, height: 20)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.borderless)
              .help(BookmarkDialog.cancelNewFolder)
              .accessibilityLabel(BookmarkDialog.cancelNewFolder)
              .accessibilityIdentifier("clair.bookmarkNewFolderCancel")
            }
          }
        } else {
          BookmarkFieldBox(isFocused: false, horizontalPadding: 4) {
            BookmarkFolderPopup(
              folders: state.folders, selection: state.folderID,
              onChoose: { state.chooseFolder($0) },
              onNewFolder: { state.beginNewFolder() },
              onManageBookmarks: { state.chooseManageBookmarks() })
          }
        }
      }
    }
    .font(.system(size: 14))
    .onChange(of: state.focusRequest.count) {
      focusedField = state.focusRequest.field
    }
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
      .frame(width: BookmarkDialog.labelWidth, alignment: .leading)
  }
}

/// Dia's field box: 36 pt tall, rounded, with a light fill and the accent
/// focus ring.
private struct BookmarkFieldBox<Content: View>: View {
  var isFocused: Bool
  var horizontalPadding: CGFloat = 10
  @ViewBuilder let content: Content
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: BookmarkDialog.fieldCornerRadius, style: .continuous)
    content
      .padding(.horizontal, horizontalPadding)
      .frame(maxWidth: .infinity, minHeight: BookmarkDialog.rowHeight, maxHeight: BookmarkDialog.rowHeight)
      .background(shape.fill(ClairDialogView.listBackground(colorScheme)))
      .overlay(
        shape.strokeBorder(
          isFocused ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
          lineWidth: isFocused ? 2 : 1))
  }
}

/// The Folder popup (D5): "Bookmarks", its folders indented one level per
/// depth, the bookmark's folder checked, then New Folder…, a divider and
/// Manage Bookmarks. An `NSPopUpButton`, for the menu's indentation and
/// checkmark.
struct BookmarkFolderPopup: NSViewRepresentable {
  let folders: [BookmarkDialogState.Folder]
  let selection: BookmarkFolderID
  let onChoose: @MainActor (BookmarkFolderID) -> Void
  let onNewFolder: @MainActor () -> Void
  let onManageBookmarks: @MainActor () -> Void

  /// The items that aren't folders.
  enum Action: String {
    case newFolder
    case manageBookmarks
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSPopUpButton {
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    popup.isBordered = false
    popup.font = .systemFont(ofSize: 14)
    popup.target = context.coordinator
    popup.action = #selector(Coordinator.chose(_:))
    popup.setAccessibilityIdentifier("clair.bookmarkFolder")
    popup.setAccessibilityLabel(BookmarkDialog.folderLabel)
    return popup
  }

  func updateNSView(_ popup: NSPopUpButton, context: Context) {
    context.coordinator.popup = self
    Self.fill(popup.menu ?? NSMenu(), folders: folders)
    Self.select(selection, in: popup)
  }

  /// The menu's items, in Dia's order.
  static func fill(_ menu: NSMenu, folders: [BookmarkDialogState.Folder]) {
    menu.removeAllItems()
    for folder in folders {
      let item = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
      item.indentationLevel = min(folder.depth, 15)
      item.representedObject = NSNumber(value: folder.id)
      menu.addItem(item)
    }
    let newFolder = NSMenuItem(title: BookmarkDialog.newFolder, action: nil, keyEquivalent: "")
    newFolder.representedObject = Action.newFolder.rawValue
    menu.addItem(newFolder)
    menu.addItem(.separator())
    let manage = NSMenuItem(title: BookmarkDialog.manageBookmarks, action: nil, keyEquivalent: "")
    manage.representedObject = Action.manageBookmarks.rawValue
    menu.addItem(manage)
  }

  /// Selects the folder `id`, which shows it checked; none for a folder the
  /// popup doesn't list.
  static func select(_ id: BookmarkFolderID, in popup: NSPopUpButton) {
    let index = popup.itemArray.firstIndex { ($0.representedObject as? NSNumber)?.int64Value == id }
    popup.selectItem(at: index ?? -1)
  }

  @MainActor
  final class Coordinator: NSObject {
    var popup: BookmarkFolderPopup?

    @objc func chose(_ sender: NSPopUpButton) {
      guard let popup, let item = sender.selectedItem else { return }
      if let id = item.representedObject as? NSNumber {
        popup.onChoose(id.int64Value)
        return
      }
      // An action leaves the folder selected.
      BookmarkFolderPopup.select(popup.selection, in: sender)
      switch (item.representedObject as? String).flatMap(Action.init(rawValue:)) {
      case .newFolder: popup.onNewFolder()
      case .manageBookmarks: popup.onManageBookmarks()
      case nil: break
      }
    }
  }
}

// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI
import Testing

@testable import ClairUI

/// The bookmark dialog against the fake host, one case for each scenario of
/// the `bookmarks` spec from "Bookmark dialog" to "New folder in the bookmark
/// dialog" (add-bookmarks-menu design D4, D5).
@MainActor
final class BookmarkDialogTests {
  private let browser = FakeBrowser()
  private var store: FakeBookmarkStore { browser.host.bookmarks }
  private var answers: [ClairDialogAnswer] = []
  private var managerOpenings = 0
  private var presenter: ClairDialogPresenter!
  private let reading: BookmarkFolderID
  private let bookmarkID: BookmarkID

  init() {
    presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    reading = browser.host.bookmarks.addFolder("Reading")
    bookmarkID = browser.host.bookmarks.add("Example Domain", url: "https://example.com/")
  }

  private func show(isNew: Bool = true) -> (ClairDialog, BookmarkDialogState) {
    let bookmark = store.bookmark(bookmarkID, isNew: isNew)!
    let shown = BookmarkDialog.show(bookmark, browser: browser, on: presenter) { [unowned self] in
      managerOpenings += 1
    }
    return shown
  }

  private func views<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
    guard let view else { return [] }
    return ([view as? T].compactMap { $0 }) + view.subviews.flatMap { views(type, in: $0) }
  }

  // MARK: Bookmark dialog

  @Test func layoutHasTheTitleRowsAndButtons() throws {
    let (added, _) = show(isNew: true)
    #expect(added.page.title == "Bookmark Added")
    #expect(added.page.buttons.map(\.title) == ["Done"])
    #expect(added.page.buttons.first?.role == .default)
    #expect(added.page.leadingButton?.title == "Remove")
    #expect(added.page.escapePressesDefault)
    #expect(added.page.icon == nil)
    #expect(BookmarkDialog.page(state: BookmarkDialogState(bookmark: store.bookmark(bookmarkID)!, browser: browser))
      .title == "Edit Bookmark")

    let window = ClairDialogWindow(dialog: added)
    window.contentView?.layoutSubtreeIfNeeded()
    let fields = views(NSTextField.self, in: window.contentView).filter(\.isEditable)
    #expect(fields.count == 1)
    let popup = try #require(views(NSPopUpButton.self, in: window.contentView).first)
    #expect(popup.accessibilityIdentifier() == "clair.bookmarkFolder")
    #expect(popup.titleOfSelectedItem == "Bookmarks")
    // The Name row is above the Folder row.
    let field = try #require(fields.first)
    let fieldFrame = field.convert(field.bounds, to: nil)
    let popupFrame = popup.convert(popup.bounds, to: nil)
    #expect(fieldFrame.minY > popupFrame.maxY)
  }

  @Test func nameOpensFocusedAndSelected() throws {
    let (dialog, state) = show()
    let window = ClairDialogWindow(dialog: dialog)
    window.contentView?.layoutSubtreeIfNeeded()
    window.focusFirstField()
    let editor = try #require(window.firstResponder as? NSTextView)
    #expect(editor.string == "Example Domain")
    #expect(editor.selectedRange() == NSRange(location: 0, length: (state.name as NSString).length))
  }

  // MARK: Saving and removing in the bookmark dialog

  @Test func returnSavesTheName() {
    let (_, state) = show()
    state.name = "Reading"
    state.submitName()
    #expect(store.bookmark(bookmarkID)?.title == "Reading")
    #expect(presenter.showing == nil)
  }

  @Test func escKeepsTheEdits() {
    let (dialog, state) = show()
    state.name = "Reading"
    ClairDialogWindow(dialog: dialog).cancelOperation(nil)
    #expect(store.bookmark(bookmarkID)?.title == "Reading")
    #expect(presenter.showing == nil)
  }

  @Test func anEmptyNameSavesThePagesTitle() {
    browser.addTab(title: "Example Domain", url: "https://example.com/")
    let (_, state) = show()
    state.name = ""
    state.submitName()
    #expect(store.bookmark(bookmarkID)?.title == "Example Domain")
  }

  @Test func removeDeletesTheBookmark() {
    let (dialog, _) = show()
    dialog.pressLeading()
    #expect(store.bookmark(bookmarkID) == nil)
    #expect(presenter.showing == nil)
    // Nothing is saved after it.
    #expect(store.commands == ["remove \(bookmarkID)"])
  }

  @Test func closingTheWindowSaves() {
    let (_, state) = show()
    state.name = "Reading"
    presenter.cancelAll()
    #expect(store.bookmark(bookmarkID)?.title == "Reading")
  }

  // MARK: Choosing a folder in the bookmark dialog

  @Test func folderPopupListsBookmarksThenItsFolders() {
    store.addFolder("In the bar", in: FakeBookmarkStore.barID)
    let (_, state) = show()
    #expect(state.folders.map(\.title) == ["Bookmarks", "Reading"])
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    BookmarkFolderPopup.fill(popup.menu!, folders: state.folders)
    BookmarkFolderPopup.select(state.folderID, in: popup)
    #expect(
      popup.itemArray.map { $0.isSeparatorItem ? "-" : $0.title } == [
        "Bookmarks", "Reading", "New Folder…", "-", "Manage Bookmarks",
      ])
    #expect(popup.itemArray.prefix(2).map(\.indentationLevel) == [0, 1])
    #expect(popup.selectedItem?.title == "Bookmarks")
    #expect(popup.selectedItem?.state == .on)
    #expect(popup.item(at: 1)?.state == .off)
  }

  @Test func choosingAFolderAndDoneMovesTheBookmark() {
    let (dialog, state) = show()
    state.chooseFolder(reading)
    dialog.press(dialog.page.buttons[0])
    #expect(store.bookmark(bookmarkID)?.folderID == reading)
  }

  @Test func manageBookmarksSavesClosesThenOpensTheManager() {
    let (_, state) = show()
    state.name = "Reading"
    state.chooseManageBookmarks()
    #expect(presenter.showing == nil)
    #expect(store.bookmark(bookmarkID)?.title == "Reading")
    #expect(managerOpenings == 1)
  }

  // MARK: New folder in the bookmark dialog

  @Test func newFolderIsCreatedAndSelected() {
    let (dialog, state) = show()
    state.beginNewFolder()
    #expect(state.isAddingFolder)
    #expect(state.focusRequest.field == .newFolder)
    state.newFolderName = "Recipes"
    state.commitNewFolder()
    #expect(!state.isAddingFolder)
    #expect(state.focusRequest.field == .name)
    #expect(presenter.showing === dialog)
    #expect(state.folders.map(\.title) == ["Bookmarks", "Reading", "Recipes"])
    dialog.press(dialog.page.buttons[0])
    let recipes = store.folders.first { $0.title == "Recipes" }?.folderID
    #expect(recipes != nil)
    #expect(store.bookmark(bookmarkID)?.folderID == recipes)
  }

  @Test func anEmptyNewFolderNameDoesNothing() {
    let (_, state) = show()
    state.beginNewFolder()
    state.newFolderName = "  "
    state.commitNewFolder()
    #expect(state.isAddingFolder)
    #expect(store.folders.count == 2)
  }

  @Test func cancellingANewFolderBringsThePopupBack() {
    let (_, state) = show()
    state.chooseFolder(reading)
    state.beginNewFolder()
    state.newFolderName = "Recipes"
    state.cancelNewFolder()
    #expect(!state.isAddingFolder)
    #expect(state.folderID == reading)
    #expect(store.folders.map(\.title) == ["Other bookmarks", "Reading"])
    #expect(!store.commands.contains { $0.hasPrefix("addFolder") })
  }
}

/// The Bookmarks Bar notice (add-bookmarks-menu design D6).
@MainActor
struct BookmarksBarNoticeTests {
  @Test func hasTheTitleMessageAndOneOK() {
    let page = BookmarksBarNotice.page()
    #expect(page.title == "Heads Up")
    #expect(
      page.message
        == "Clair doesn't have a bookmarks bar, so bookmarks saved or imported there are moved to the Bookmarks menu.")
    #expect(page.buttons.map(\.title) == ["OK"])
    #expect(page.buttons.first?.shortcut == .defaultAction)
    #expect(page.leadingButton == nil)
    #expect(page.icon == nil)
  }

  @Test func returnAndEscChooseOK() {
    var answers: [ClairDialogAnswer] = []
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    for key in ["return", "esc"] {
      let dialog = ClairDialog(BookmarksBarNotice.page())
      presenter.show(dialog) { answers.append($0) }
      if key == "return" {
        dialog.press(dialog.page.buttons[0])
      } else {
        ClairDialogWindow(dialog: dialog).cancelOperation(nil)
      }
    }
    #expect(answers == [.accepted, .accepted])
  }

  @Test func showsOnceWhileItWaits() {
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    BookmarksBarNotice.show(on: presenter)
    BookmarksBarNotice.show(on: presenter)
    presenter.showing?.answer(.accepted)
    #expect(presenter.showing == nil)
  }

  @Test func windowShowsItThroughItsDialogs() {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces,
      preferences: SidebarPreferences(defaults: UserDefaults(suiteName: "BookmarksBarNoticeTests")!))
    browser.clairWindow = controller
    controller.showBookmarksBarNotice()
    #expect(controller.dialogs.showing?.page.title == "Heads Up")
  }
}

/// The command bar's row icons (add-bookmarks-menu design D8).
@MainActor
struct SuggestionSymbolTests {
  @Test func eachKindHasItsSymbol() {
    let symbols = [SuggestionKind.search, .URL, .history, .openTab, .bookmark].map { kind in
      SuggestionRow(suggestion: FakeSuggestion(id: 1, kind: kind, contents: "A"), isSelected: false).symbol
    }
    #expect(symbols == ["magnifyingglass", "globe", "clock", "square.on.square", "bookmark"])
    #expect(NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil) != nil)
  }

  /// The bookmark icon has no text, so VoiceOver reads "Bookmark" last.
  @Test func bookmarkRowsReadAsBookmarks() {
    let bookmark = FakeSuggestion(id: 1, kind: .bookmark, contents: "Clair", destination: "https://example.com/")
    let history = FakeSuggestion(id: 2, kind: .history, contents: "Clair", destination: "https://example.com/")
    #expect(SuggestionRow(suggestion: bookmark, isSelected: false).accessibilityText == "Clair, example.com, Bookmark")
    #expect(SuggestionRow(suggestion: history, isSelected: false).accessibilityText == "Clair, example.com")
  }
}

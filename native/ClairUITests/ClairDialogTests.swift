// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI
import Testing

@testable import ClairUI

@MainActor
final class ClairDialogTests {
  private var begun: [ClairDialog] = []
  private var ended: [ClairDialog] = []
  private var answers: [String] = []
  private var presenter: ClairDialogPresenter!

  init() {
    presenter = ClairDialogPresenter(
      host: .init(
        begin: { [unowned self] in begun.append($0) },
        end: { [unowned self] in ended.append($0) }))
  }

  private func dialog(_ title: String, buttons: [ClairDialogButton]? = nil) -> ClairDialog {
    ClairDialog(
      ClairDialogPage(
        title: title,
        buttons: buttons ?? [.init(title: "Cancel", role: .cancel), .init(title: "OK", role: .default)]))
  }

  private func show(_ dialog: ClairDialog) {
    presenter.show(dialog) { [unowned self] answer in answers.append("\(dialog.page.title) \(answer)") }
  }

  // MARK: Buttons

  @Test func rolesMapToEscAndReturn() {
    let cancel = ClairDialogButton(title: "Cancel", role: .cancel)
    let ok = ClairDialogButton(title: "OK", role: .default)
    #expect(cancel.shortcut == .cancelAction)
    #expect(cancel.keyLabel == "ESC")
    #expect(!cancel.isDefault)
    #expect(ok.shortcut == .defaultAction)
    #expect(ok.keyLabel == "↩")
    #expect(ok.isDefault)
    #expect(!ok.isDestructive)
  }

  @Test func destructiveDefaultIsMarkedDestructive() {
    let remove = ClairDialogButton(title: "Remove", role: .destructive)
    #expect(remove.isDestructive)
    #expect(remove.isDefault)
    #expect(remove.shortcut == .defaultAction)
  }

  /// add-link-rules D6: a page's leading button takes neither Esc nor
  /// Return, whatever its role.
  @Test func leadingButtonTakesNeitherKey() {
    var pressed = 0
    let leading = ClairDialogButton(title: "Add Rule", role: .default, action: { _ in pressed += 1 })
    #expect(leading.shortcut(isLeading: true) == nil)
    #expect(ClairDialogButton(title: "Always", role: .cancel).shortcut(isLeading: true) == nil)
    #expect(leading.shortcut(isLeading: false) == .defaultAction)
    let shown = ClairDialog(ClairDialogPage(title: "A", buttons: [.init(title: "Done", role: .default)], leadingButton: leading))
    show(shown)
    ClairDialogWindow(dialog: shown).cancelOperation(nil)
    #expect(pressed == 0)
    #expect(answers == [])
  }

  /// add-link-rules D6: Cancel turned into "Discard Changes" is red, keeps
  /// Esc and its place, and answers `.cancelled`.
  @Test func destructiveCancelKeepsEsc() {
    let discard = ClairDialogButton(title: "Discard Changes", role: .cancel, isDestructive: true)
    #expect(discard.isDestructive)
    #expect(!discard.isDefault)
    #expect(discard.shortcut == .cancelAction)
    #expect(discard.keyLabel == "ESC")
    #expect(discard.identifier == "clair.dialogCancel")
    let shown = dialog("Rules", buttons: [discard, .init(title: "Done", role: .default)])
    show(shown)
    ClairDialogWindow(dialog: shown).cancelOperation(nil)
    #expect(answers == ["Rules cancelled"])
  }

  @Test func pageWidthDefaultsToTheCards() {
    #expect(ClairDialogPage(title: "A", buttons: []).width == nil)
    #expect(ClairDialogView.contentWidth(forCardWidth: ClairDialogView.width) == ClairDialogView.contentWidth)
    let wide = ClairDialog(ClairDialogPage(title: "Link Rules", buttons: [], width: 640))
    let window = ClairDialogWindow(dialog: wide)
    #expect(window.frame.width == 640)
  }

  @Test func leadingButtonAnswersOnlyThroughItsAction() {
    var pressed = 0
    let page = ClairDialogPage(
      title: "A", buttons: [.init(title: "Cancel", role: .cancel)],
      leadingButton: .init(title: "Always", role: .cancel, action: { _ in pressed += 1 }))
    let shown = ClairDialog(page)
    show(shown)
    shown.pressLeading()
    #expect(pressed == 1)
    #expect(answers == [])
    #expect(presenter.showing === shown)
    let silent = ClairDialog(ClairDialogPage(title: "B", buttons: [], leadingButton: .init(title: "X", role: .cancel)))
    silent.pressLeading()
    #expect(answers == [])
  }

  // MARK: Stepped dialogs (dialogs "Stepped dialogs")

  private func steppedPage(back: Bool, onBack: (@MainActor (ClairDialog) -> Void)? = nil) -> ClairDialogPage {
    ClairDialogPage(
      title: "Step", buttons: [.init(title: "Cancel", role: .cancel), .init(title: "Import", role: .default)],
      width: 520, isStepped: true, backButton: back ? .init(title: "Back", role: .cancel, action: onBack) : nil)
  }

  @Test func aMiddleStepPutsCancelLeadingAndBackBeforeTheDefault() {
    let row = ClairDialogRow(steppedPage(back: true))
    #expect(row.leading.map(\.button.title) == ["Cancel"])
    #expect(row.leading.map(\.kind) == [.keyed])
    #expect(row.leading.first?.button.shortcut == .cancelAction)
    #expect(row.trailing.map(\.button.title) == ["Back", "Import"])
    #expect(row.trailing.map(\.kind) == [.back, .keyed])
    #expect(row.trailing.last?.button.shortcut == .defaultAction)
  }

  @Test func theFirstStepHasNoBack() {
    let row = ClairDialogRow(steppedPage(back: false))
    #expect(row.leading.map(\.button.title) == ["Cancel"])
    #expect(row.trailing.map(\.button.title) == ["Import"])
  }

  @Test func anOrdinaryDialogKeepsItsButtonsTogether() {
    let row = ClairDialogRow(ClairDialogPage(title: "A", buttons: [.init(title: "Cancel", role: .cancel), .init(title: "OK", role: .default)]))
    #expect(row.leading.isEmpty)
    #expect(row.trailing.map(\.button.title) == ["Cancel", "OK"])
  }

  @Test func escClosesRatherThanGoingBack() {
    var backs = 0
    let shown = ClairDialog(steppedPage(back: true, onBack: { _ in backs += 1 }))
    show(shown)
    ClairDialogWindow(dialog: shown).cancelOperation(nil)
    #expect(backs == 0)
    #expect(answers == ["Step cancelled"])
  }

  @Test func backTakesNoKeyAndAnswersOnlyThroughItsAction() {
    var backs = 0
    let page = steppedPage(back: true, onBack: { _ in backs += 1 })
    // Back shows no key; Return stays the default button's.
    #expect(page.backButton?.shortcut(isLeading: true) == nil)
    let shown = ClairDialog(page)
    show(shown)
    shown.pressBack()
    #expect(backs == 1)
    #expect(answers == [])
    // Return presses the default button, not Back.
    shown.press(page.buttons[1])
    #expect(backs == 1)
    #expect(answers == ["Step accepted"])
  }

  @Test func theCardKeepsItsWidthFromStepToStep() {
    let shown = ClairDialog(steppedPage(back: false))
    let window = ClairDialogWindow(dialog: shown)
    #expect(window.frame.width == 520)
    shown.swap(to: steppedPage(back: true))
    #expect(ClairDialogWindow(dialog: shown).frame.width == 520)
  }

  @Test func containsFindsShownAndWaitingDialogs() {
    show(dialog("A"))
    show(dialog("B"))
    #expect(presenter.contains { $0.page.title == "A" })
    #expect(presenter.contains { $0.page.title == "B" })
    #expect(!presenter.contains { $0.page.title == "C" })
  }

  // MARK: Quit confirmation (native-quit-confirmation)

  @Test func quitDialogIsWordedAndLaidOutAsDias() {
    let page = QuitConfirmation.page(icon: nil)
    #expect(page.title == "Are you sure you want to quit Clair?")
    #expect(page.message == "You may lose unsaved work in your tabs.")
    #expect(page.leadingButton?.title == "Always quit")
    #expect(page.buttons.map(\.title) == ["Cancel", "Quit"])
    #expect(page.buttons.map(\.role) == [.cancel, .destructive])
  }

  @Test func quitDialogAnswers() {
    let host = FakeHost()
    QuitConfirmation.show(on: presenter, host: host, icon: nil)
    // A second Cmd+Q while it shows adds nothing.
    QuitConfirmation.show(on: presenter, host: host, icon: nil)
    #expect(begun.count == 1)
    presenter.showing?.answer(.cancelled)
    #expect(host.quitCount == 0)
    #expect(host.warnsBeforeQuitting)

    QuitConfirmation.show(on: presenter, host: host, icon: nil)
    presenter.showing?.answer(.accepted)
    #expect(host.quitCount == 1)
    #expect(host.warnsBeforeQuitting)

    QuitConfirmation.show(on: presenter, host: host, icon: nil)
    presenter.showing?.pressLeading()
    #expect(host.quitCount == 2)
    #expect(!host.warnsBeforeQuitting)
  }

  @Test func disabledDefaultHasNoReturn() {
    let ok = ClairDialogButton(title: "OK", role: .default, isEnabled: false)
    #expect(ok.shortcut == nil)
    let remove = ClairDialogButton(title: "Remove", role: .destructive, isEnabled: false)
    #expect(remove.shortcut == nil)
  }

  @Test func pressingButtonsAnswersWithTheirRole() {
    let first = dialog("A")
    show(first)
    first.press(first.page.buttons[1])
    let second = dialog("B")
    show(second)
    second.press(second.page.buttons[0])
    #expect(answers == ["A accepted", "B cancelled"])
    #expect(ended.map(\.page.title) == ["A", "B"])
  }

  @Test func disabledButtonDoesNothing() {
    let shown = dialog("A", buttons: [.init(title: "OK", role: .default, isEnabled: false)])
    show(shown)
    shown.press(shown.page.buttons[0])
    #expect(answers == [])
    #expect(presenter.showing === shown)
  }

  // MARK: Presenter

  @Test func secondRequestWaitsForTheFirst() {
    let first = dialog("A")
    show(first)
    show(dialog("B"))
    #expect(begun.map(\.page.title) == ["A"])
    first.answer(.accepted)
    #expect(begun.map(\.page.title) == ["A", "B"])
    #expect(presenter.showing === begun[1])
  }

  @Test func answersOnce() {
    let shown = dialog("A")
    show(shown)
    shown.answer(.accepted)
    shown.answer(.cancelled)
    #expect(answers == ["A accepted"])
    #expect(ended.count == 1)
  }

  @Test func dismissedDialogIsNotAnswered() {
    let first = dialog("A")
    let second = dialog("B")
    let third = dialog("C")
    show(first)
    show(second)
    show(third)
    presenter.dismiss(second)
    presenter.dismiss(first)
    #expect(ended.map(\.page.title) == ["A"])
    first.answer(.accepted)
    #expect(answers == [])
    // The next one still waiting takes its place.
    #expect(begun.map(\.page.title) == ["A", "C"])
  }

  @Test func cancelAllCancelsEveryPendingRequest() {
    show(dialog("A"))
    show(dialog("B"))
    presenter.cancelAll()
    #expect(ended.map(\.page.title) == ["A"])
    #expect(answers == ["A cancelled", "B cancelled"])
    #expect(begun.count == 1)
    #expect(presenter.showing == nil)
  }

  @Test func completionCanAskAgain() {
    let first = dialog("A")
    presenter.show(first) { [unowned self] _ in show(dialog("Again")) }
    first.answer(.accepted)
    #expect(begun.map(\.page.title) == ["A", "Again"])
  }

  // MARK: Swapping content

  @Test func swapsContentAndReturns() {
    let shown = dialog("Manage")
    show(shown)
    shown.swap(
      to: ClairDialogPage(
        title: "Delete?",
        buttons: [
          .init(title: "Cancel", role: .cancel, action: { $0.swapBack() }),
          .init(title: "Delete", role: .destructive, action: { $0.swapBack() }),
        ]))
    #expect(shown.page.title == "Delete?")
    shown.press(shown.page.buttons[0])
    #expect(shown.page.title == "Manage")
    #expect(answers == [])
    shown.swapBack()
    #expect(shown.page.title == "Manage")
  }

  @Test func updateChangesTheShownPage() {
    let shown = dialog("Name", buttons: [.init(title: "OK", role: .default, isEnabled: false)])
    shown.update { $0.buttons[0].isEnabled = true }
    #expect(shown.page.buttons[0].shortcut == .defaultAction)
  }

  // MARK: The sheet

  @Test func sheetIsClearAndBorderless() {
    let window = ClairDialogWindow(dialog: dialog("A"))
    #expect(window.styleMask == .borderless)
    #expect(!window.isOpaque)
    #expect(window.backgroundColor == .clear)
    #expect(window.canBecomeKey)
    #expect(window.title == "A")
    #expect(window.accessibilityTitle() == "A")
    #expect(window.frame.width == ClairDialogView.width)
  }

  @Test func escCancelsThroughTheWindow() {
    let shown = dialog("A")
    show(shown)
    ClairDialogWindow(dialog: shown).cancelOperation(nil)
    #expect(answers == ["A cancelled"])
  }

  @Test func firstFieldGetsFocus() {
    var page = ClairDialogPage(title: "Name", buttons: [.init(title: "OK", role: .default)])
    page.content = AnyView(TextField("Name", text: .constant("")))
    let window = ClairDialogWindow(dialog: ClairDialog(page))
    window.contentView?.layoutSubtreeIfNeeded()
    window.focusFirstField()
    let editor = window.firstResponder as? NSTextView
    #expect((editor?.delegate as? NSTextField) != nil)
  }
}

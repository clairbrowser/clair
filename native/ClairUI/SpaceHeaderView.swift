// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// What the Space views ask the window to do (add-spaces design D10).
@MainActor
protocol SpaceActions: AnyObject {
  func showSpace(_ spaceID: SpaceID)
  /// The New Space form, in place of the header and the list.
  func beginNewSpace()
  func cancelNewSpace()
  /// `profile` nil uses the profile of the Space the window shows.
  func createSpace(named name: String, icon: String?, profile: ProfileID?)
  /// "New Profile…" in the form's profile popup: the new profile is chosen.
  func newProfileForNewSpace()
  /// Asks first when the Space has tabs (profiles spec, "Changing a Space's
  /// profile").
  func setProfile(_ profileID: ProfileID, forSpace spaceID: SpaceID)
  /// "New Profile…" in Set Profile: creates a profile and gives it to the
  /// Space.
  func newProfile(forSpace spaceID: SpaceID)
  /// Inline renaming and the icon field in the header.
  func beginRenamingSpace()
  func beginChangingSpaceIcon()
  func endEditingSpaceHeader()
  func renameSpace(_ spaceID: SpaceID, to name: String)
  func setIcon(_ icon: String?, forSpace spaceID: SpaceID)
  /// Asks first when the Space has tabs.
  func deleteSpace(_ spaceID: SpaceID)
  func moveSpace(_ spaceID: SpaceID, to index: Int)
  func moveTab(_ tab: TabID, toSpace spaceID: SpaceID)
  func manageSpaces()
}

/// What the Space header is editing, if anything.
enum SpaceHeaderEdit: Equatable {
  case renaming
  case icon
}

/// The current Space's icon and name above the tab list, as in Arc: the icon
/// 26 pt across from 13 pt in, the name 18 pt high after it, or from 13 pt in
/// without an icon. Right-clicking it opens its menu; Rename Space… turns the
/// name into a field, with "Done" where Arc's More button is.
struct SpaceHeaderView: View {
  let model: BrowserWindowModel
  /// The Space it shows: the window's, or the one sliding out.
  let space: (any ClairSpace)?
  weak var actions: (any SpaceActions)?
  /// Whether the Space's pinned section is collapsed, which keeps the
  /// chevron showing, pointing sideways (pinned-tabs spec, "Collapsing the
  /// pinned section").
  var pinsCollapsed = false
  /// The chevron's click; nil for a header without one.
  var onToggleCollapse: (() -> Void)?

  static let height: CGFloat = 32
  /// Room under the header, so the name's centre sits 41 pt above the "New
  /// Tab" row's, as in Arc.
  static let bottomGap: CGFloat = 4.5
  static let leading: CGFloat = 16
  static let iconSize: CGFloat = 26
  static let nameGap: CGFloat = 2
  /// Arc's name: 13 pt semibold, in the sidebar's secondary grey.
  static let nameNSFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
  static let nameFont = Font(nameNSFont)

  @State private var draft = ""
  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Where the name starts while the chevron shows.
  static let chevronLeading: CGFloat = 44
  /// Arc's, recorded at 60 fps: the pill shows and goes at once, while the
  /// name slides aside, and back, in about 85 ms as the chevron fades.
  static let chevronSlide = Animation.easeInOut(duration: 0.085)
  /// Collapsing or expanding the pinned section: Arc's, recorded at 60 fps,
  /// also about 85 ms; none with Reduce Motion.
  static var collapseAnimation: Animation? {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : chevronSlide
  }

  /// The More button: 24 pt, 6 pt in from the pill's trailing edge, as in
  /// Arc, with the name kept clear of it.
  static let moreSize: CGFloat = 24
  static let moreTrailing: CGFloat = 14
  static let moreGlyphSize: CGFloat = 13
  private static let trailing: CGFloat = 13
  private static let trailingWithMore: CGFloat = moreTrailing + moreSize + 4

  private var showsMore: Bool { isHovered && edit == nil && space != nil }

  private var showsChevron: Bool {
    onToggleCollapse != nil && edit == nil && (isHovered || pinsCollapsed)
  }

  private var isCurrent: Bool { space?.spaceID == model.shownSpaceID }
  private var edit: SpaceHeaderEdit? { isCurrent ? model.spaceHeaderEdit : nil }

  var body: some View {
    HStack(spacing: Self.nameGap) {
      if edit == .icon || space?.icon != nil {
        icon
      }
      if edit == .renaming {
        SpaceNameField(
          text: space?.name ?? "", font: Self.nameNSFont,
          onChange: { draft = $0 }, onSubmit: commitName, onCancel: { actions?.endEditingSpaceHeader() }
        )
        .onAppear { draft = space?.name ?? "" }
        Button("Done") { commitName() }
          .buttonStyle(.borderless)
          .font(.system(size: 12, weight: .medium))
          .accessibilityIdentifier("clair.spaceRenameDone")
      } else {
        Text(space?.name ?? "")
          .font(Self.nameFont)
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("clair.spaceName")
        Spacer(minLength: 0)
      }
    }
    // Arc's header under the pointer, while the Space has pinned tabs: a
    // pill, the chevron at x=20.5 and the name slid from x=17 to x=45; the
    // chevron stays, pointing sideways, while the pinned tabs are collapsed.
    .padding(.leading, showsChevron ? Self.chevronLeading : Self.leading)
    .animation(reduceMotion ? nil : Self.chevronSlide, value: showsChevron)
    .padding(.trailing, showsMore ? Self.trailingWithMore : Self.trailing)
    // The name makes room for the More button as the button fades in.
    .animation(reduceMotion ? nil : sidebarHoverFade, value: showsMore)
    .frame(height: Self.height)
    .background {
      if isHovered && edit == nil && onToggleCollapse != nil {
        RoundedRectangle(cornerRadius: TabRow.cornerRadius, style: .continuous)
          .fill(SidebarFill.hover(colorScheme))
          .padding(.horizontal, 8)
      }
    }
    .contentShape(Rectangle())
    // A click anywhere on the header collapses or expands the pinned
    // section, as in Arc.
    .gesture(TapGesture().onEnded { onToggleCollapse?() }, isEnabled: edit == nil && onToggleCollapse != nil)
    .overlay(alignment: .leading) {
      ZStack(alignment: .leading) { chevron }
        .animation(reduceMotion ? nil : Self.chevronSlide, value: showsChevron)
    }
    .overlay(alignment: .trailing) {
      if edit == nil && space != nil {
        moreButton
      }
    }
    .onHover { isHovered = $0 }
    .padding(.bottom, Self.bottomGap)
    .overlay {
      if edit == nil {
        RowClickCatcher(onMiddleClick: {}, menuItems: menuItems)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.spaceHeader")
  }

  /// The collapse chevron, fading in as the name slides aside.
  @ViewBuilder private var chevron: some View {
    if let onToggleCollapse, showsChevron {
      Button(action: onToggleCollapse) {
        Image(systemName: "chevron.down")
          .font(.system(size: 12.5, weight: .bold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(pinsCollapsed ? -90 : 0))
          .frame(width: 12, height: Self.height)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.leading, 20)
      .tooltip(pinsCollapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs")
      .accessibilityLabel(pinsCollapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs")
      .accessibilityIdentifier("clair.pinnedChevron")
      .transition(.opacity)
    }
  }

  /// Arc's More button, which opens the header's menu. It stays in the view
  /// while hidden, so an open menu isn't taken away with it.
  private var moreButton: some View {
    IconMenu(help: "More", size: Self.moreSize) {
      RowMenuContent(items: menuItems)
    } label: {
      SymbolGlyph(systemImage: "ellipsis", size: Self.moreGlyphSize, weight: .bold)
    }
    .padding(.trailing, Self.moreTrailing)
    .opacity(showsMore ? 1 : 0)
    .animation(reduceMotion ? nil : sidebarHoverFade, value: showsMore)
    // Out of VoiceOver's way while it isn't showing; right-clicking the
    // header offers the same menu.
    .accessibilityHidden(!showsMore)
    .accessibilityIdentifier("clair.spaceMore")
  }

  @ViewBuilder private var icon: some View {
    SpaceIconField(
      icon: space?.icon, size: 18, isEditing: edit == .icon,
      onChange: { icon in
        if let space { actions?.setIcon(icon, forSpace: space.spaceID) }
      },
      onEnd: { actions?.endEditingSpaceHeader() }
    )
    .frame(width: Self.iconSize, height: Self.iconSize)
    .overlay {
      // Arc shows a dashed square where the icon goes while the picker is
      // open.
      if edit == .icon {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
          .foregroundStyle(.secondary)
          .allowsHitTesting(false)
      }
    }
  }

  private func commitName() {
    // An empty name keeps the earlier one.
    if let space {
      actions?.renameSpace(space.spaceID, to: draft)
    }
    actions?.endEditingSpaceHeader()
  }

  /// The header's menu (spaces spec, "Space header").
  private var menuItems: [RowClickCatcher.Item] {
    guard let space else { return [] }
    return SpacesLogic.headerMenu(spaceCount: model.spaces.spaces.count).map { item in
      guard let item else { return .separator }
      guard item.isEnabled else { return .disabled(item.title) }
      if item.command == .setProfile {
        return .submenu(item.title, Self.profileItems(for: space, in: model.spaces, actions: actions))
      }
      return .action(item.title) { [weak actions] in
        switch item.command {
        case .changeIcon: actions?.beginChangingSpaceIcon()
        case .rename: actions?.beginRenamingSpace()
        case .setProfile: break
        case .manage: actions?.manageSpaces()
        case .delete: actions?.deleteSpace(space.spaceID)
        }
      }
    }
  }

  /// Set Profile's items for `space` (add-profiles D10).
  static func profileItems(for space: any ClairSpace, in spaces: SpacesModel, actions: (any SpaceActions)?)
    -> [RowClickCatcher.Item]
  {
    let spaceID = space.spaceID
    return SpacesLogic.profileMenu(spaces.profiles, checked: space.profileID).map { item in
      guard let item else { return .separator }
      switch item.command {
      case .profile(let profileID):
        let choose: () -> Void = { [weak actions] in actions?.setProfile(profileID, forSpace: spaceID) }
        return item.isChecked ? .checked(item.title, {}) : .action(item.title, choose)
      case .newProfile:
        return .action(item.title) { [weak actions] in actions?.newProfile(forSpace: spaceID) }
      }
    }
  }
}

/// A row's menu items as SwiftUI menu content, for a menu button that offers
/// the same menu as right-clicking the row.
struct RowMenuContent: View {
  let items: [RowClickCatcher.Item]

  var body: some View {
    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
      switch item {
      case .action(let title, let run):
        Button(title, action: run)
      case .checked(let title, let run):
        Toggle(title, isOn: Binding(get: { true }, set: { _ in run() }))
      case .disabled(let title):
        Button(title) {}.disabled(true)
      case .submenu(let title, let items):
        Menu(title) { RowMenuContent(items: items) }
      case .separator:
        Divider()
      }
    }
  }
}

/// The Space's name as a field. It takes the keyboard itself once it's in the
/// window, as a row's rename field does: SwiftUI's focus, taking it from
/// another field such as the command bar's, can leave it with the sidebar's
/// list instead, where typing goes nowhere.
private struct SpaceNameField: NSViewRepresentable {
  let text: String
  let font: NSFont
  let onChange: (String) -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = RenameField.FocusingField(string: text)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = font
    field.placeholderString = "Space name"
    field.lineBreakMode = .byTruncatingTail
    field.cell?.usesSingleLineMode = true
    field.delegate = context.coordinator
    field.setAccessibilityIdentifier("clair.spaceNameField")
    field.onWindow = { [weak field] in
      guard let field, let window = field.window, window.makeFirstResponder(field) else { return }
      field.currentEditor()?.selectAll(nil)
    }
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: SpaceNameField

    init(_ parent: SpaceNameField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.onChange(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      switch selector {
      case #selector(NSResponder.insertNewline(_:)):
        parent.onChange(textView.string)
        parent.onSubmit()
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        parent.onCancel()
        return true
      default:
        return false
      }
    }
  }
}

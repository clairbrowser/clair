// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// Where the browser controls show, as the "Location bar" row offers it
/// (add-page-toolbar D9).
enum LocationBarChoice: String, CaseIterable {
  case toolbar
  case sidebar

  var label: String {
    switch self {
    case .toolbar: "Toolbar"
    case .sidebar: "Sidebar"
    }
  }

  var showsToolbar: Bool { self == .toolbar }

  init(showsToolbar: Bool) {
    self = showsToolbar ? .toolbar : .sidebar
  }
}

/// A drawing of a Clair window in one layout (add-page-toolbar D9), from
/// SwiftUI shapes in the window's own points, so it's sharp at any size and
/// its proportions are Clair's: the sidebar's default width, the card's
/// inset and the toolbar's height. Its colours are semantic, so it follows
/// the appearance and the accent colour.
struct LayoutThumbnail: View {
  let choice: LocationBarChoice

  /// The window it draws, in points: its proportions are the thumbnail's.
  static let window = CGSize(width: 760, height: 484)
  static let cornerRadius: CGFloat = 10
  /// The glyphs are drawn larger than life, so they read at Settings' size.
  static let dot: CGFloat = 20

  var body: some View {
    GeometryReader { proxy in
      let scale = proxy.size.width / Self.window.width
      drawing
        .frame(width: Self.window.width, height: Self.window.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
    }
    .aspectRatio(Self.window.width / Self.window.height, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private var drawing: some View {
    let sidebar = SidebarState.defaultWidth
    let inset = WindowLayout.shownInset
    let card = CGRect(
      x: sidebar, y: inset, width: Self.window.width - sidebar - inset, height: Self.window.height - 2 * inset)
    let toolbar = ToolbarArrangement.height * 1.4
    return ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(Color(nsColor: Self.windowTint))
      windowControls
      if choice == .sidebar {
        sidebarControls(width: sidebar)
      }
      tabRows(width: sidebar, top: choice == .sidebar ? 110 : 64)
      // The card, with the toolbar across its top in that layout.
      ZStack(alignment: .topLeading) {
        Rectangle().fill(Color(nsColor: .textBackgroundColor))
        if choice == .toolbar {
          Rectangle().fill(Color(nsColor: ToolbarFill.background)).frame(height: toolbar)
          Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 2).offset(y: toolbar)
          toolbarControls(width: card.width, height: toolbar)
        }
      }
      .frame(width: card.width, height: card.height, alignment: .topLeading)
      .clipShape(.rect(cornerRadius: PageCardView.cornerRadius * 1.5, style: .continuous))
      .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
      .offset(x: card.minX, y: card.minY)
    }
    .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
  }

  /// The window's own tint: the sidebar's material, light grey, or Arc's
  /// near-black in Dark Mode.
  static let windowTint = NSColor(name: nil) { appearance in
    appearance.isDark ? SidebarTint.dark : NSColor(white: 0.84, alpha: 1)
  }

  private var controlFill: Color { Color.secondary.opacity(0.85) }

  private func dot(_ x: CGFloat, _ y: CGFloat, size: CGFloat = dot) -> some View {
    Circle().fill(controlFill).frame(width: size, height: size).offset(x: x - size / 2, y: y - size / 2)
  }

  private var windowControls: some View {
    ForEach(0..<3, id: \.self) { index in
      Circle().fill(Color.secondary.opacity(0.35)).frame(width: 18, height: 18)
        .offset(x: 13 + CGFloat(index) * 23, y: 15)
    }
  }

  /// The top row's toggle, back, forward and reload, and the URL field.
  private func sidebarControls(width: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(0..<4, id: \.self) { index in
        dot(index == 0 ? 97 : width - 22 - CGFloat(3 - index) * 34, 24)
      }
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.primary.opacity(0.13))
        .frame(width: width - 16, height: 40)
        .offset(x: 8, y: 50)
      Capsule().fill(Color.secondary.opacity(0.6))
        .frame(width: width * 0.45, height: 12)
        .offset(x: 22, y: 64)
    }
  }

  /// The toolbar's toggle, back, forward and reload, its host and its site
  /// controls, at their places on the card.
  private func toolbarControls(width: CGFloat, height: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(ToolbarArrangement.leadingCentres.enumerated()), id: \.offset) { _, x in
        dot(x * 1.3, height / 2)
      }
      Capsule().fill(Color.secondary.opacity(0.6))
        .frame(width: 120, height: 12)
        .offset(x: width / 2 - 60, y: height / 2 - 6)
      dot(width - 28, height / 2)
    }
  }

  /// Three tabs, the first one active.
  private func tabRows(width: CGFloat, top: CGFloat) -> some View {
    ForEach(0..<3, id: \.self) { index in
      let y = top + CGFloat(index) * 48
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(index == 0 ? Color(nsColor: .textBackgroundColor).opacity(0.9) : Color.clear)
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(index == 0 ? 0.9 : 0.5))
            .frame(width: 18, height: 18)
          Capsule().fill(Color.secondary.opacity(0.4)).frame(width: width * (0.5 - CGFloat(index) * 0.08), height: 10)
        }
        .padding(.leading, 12)
      }
      .frame(width: width - 16, height: 40)
      .offset(x: 8, y: y)
    }
  }
}

/// The "Location bar" row's choice (add-page-toolbar D9): the two drawings
/// side by side, each with its name, the chosen one ringed in the accent
/// colour with its name in bold. It takes its size from its container, so a
/// first-run screen can show it larger.
struct LocationBarPicker: View {
  @Binding var showsToolbar: Bool

  static let spacing: CGFloat = 14
  /// What VoiceOver reads for the pair, and the runtime suite finds.
  static let label = "Location bar"
  static let identifier = "clair.locationBar"

  /// One choice as the row shows it.
  struct Option: Equatable {
    let choice: LocationBarChoice
    let isChosen: Bool
    var label: String { choice.label }
    var identifier: String { "\(LocationBarPicker.identifier).\(choice.rawValue)" }
  }

  static func options(showsToolbar: Bool) -> [Option] {
    let chosen = LocationBarChoice(showsToolbar: showsToolbar)
    return LocationBarChoice.allCases.map { Option(choice: $0, isChosen: $0 == chosen) }
  }

  func choose(_ choice: LocationBarChoice) {
    showsToolbar = choice.showsToolbar
  }

  var body: some View {
    HStack(alignment: .top, spacing: Self.spacing) {
      ForEach(Self.options(showsToolbar: showsToolbar), id: \.choice) { option in
        let choice = option.choice
        let isChosen = option.isChosen
        Button {
          choose(choice)
        } label: {
          VStack(spacing: 6) {
            LayoutThumbnail(choice: choice)
              .padding(3)
              .overlay {
                RoundedRectangle(cornerRadius: LayoutThumbnail.cornerRadius / 2 + 4, style: .continuous)
                  .strokeBorder(isChosen ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isChosen ? 3 : 1)
              }
            Text(choice.label)
              .font(.callout)
              .fontWeight(isChosen ? .semibold : .regular)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier(option.identifier)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Self.label)
    .accessibilityIdentifier(Self.identifier)
  }
}

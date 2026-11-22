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

/// A close-up of a Clair window's top-left corner in one layout
/// (add-page-toolbar D9): the window controls in their colours, the browser
/// controls' own symbols where that layout puts them, and the start of the
/// tab list and the page. It's drawn in the window's own points, at Clair's
/// metrics (the sidebar's default width, the card's inset, the toolbar's
/// height and slots), and scaled to fit, so it's sharp at any size. Its
/// colours are semantic, so it follows the appearance and the accent colour.
struct LayoutThumbnail: View {
  let choice: LocationBarChoice

  /// The part of the window it shows, in points from the top-left corner:
  /// wide enough for the toolbar's reload.
  static let viewport = CGSize(width: 404, height: 258)
  /// The desktop showing above and left of the window, so its corner reads.
  static let margin: CGFloat = 12
  static let cornerRadius: CGFloat = 7
  /// The window's own corner, as macOS 27 draws it.
  static let windowCornerRadius: CGFloat = 16
  /// The symbols are drawn a little larger than life, so they read at
  /// Settings' size.
  static let glyphSize: CGFloat = 19
  /// The close, minimise and zoom buttons' colours.
  static let windowControlColours: [Color] = [
    Color(red: 1, green: 95 / 255, blue: 87 / 255),
    Color(red: 254 / 255, green: 188 / 255, blue: 46 / 255),
    Color(red: 40 / 255, green: 200 / 255, blue: 64 / 255),
  ]

  var body: some View {
    GeometryReader { proxy in
      let scale = proxy.size.width / Self.viewport.width
      ZStack(alignment: .topLeading) {
        Color.primary.opacity(0.06)
        drawing.offset(x: Self.margin, y: Self.margin)
      }
      .frame(width: Self.viewport.width, height: Self.viewport.height, alignment: .topLeading)
      .scaleEffect(scale, anchor: .topLeading)
    }
    .aspectRatio(Self.viewport.width / Self.viewport.height, contentMode: .fit)
    .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
    .accessibilityHidden(true)
  }

  private var drawing: some View {
    let sidebar = SidebarState.defaultWidth
    let inset = WindowLayout.shownInset
    let controls = WindowControlsMetrics.macOS27
    // The card runs off the drawing's right and bottom edges.
    let card = CGRect(x: sidebar, y: inset, width: Self.viewport.width, height: Self.viewport.height)
    let showsToolbar = choice == .toolbar
    return ZStack(alignment: .topLeading) {
      Color(nsColor: Self.windowTint)
      windowControls(centreY: controls.centreY, trailingX: controls.trailingX)
      if !showsToolbar {
        sidebarControls(width: sidebar, controls: controls)
      }
      // Arc's favorites start 44 pt down with the toolbar on, below the URL
      // field without it.
      tabRows(width: sidebar, top: showsToolbar ? 48 : 96)
      page(width: card.width, height: card.height, showsToolbar: showsToolbar)
        .offset(x: card.minX, y: card.minY)
    }
    .clipShape(
      UnevenRoundedRectangle(topLeadingRadius: Self.windowCornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
  }

  /// The window's own tint: the sidebar's material, light grey, or Arc's
  /// near-black in Dark Mode.
  static let windowTint = NSColor(name: nil) { appearance in
    appearance.isDark ? SidebarTint.dark : NSColor(white: 0.84, alpha: 1)
  }

  private func glyph(_ systemImage: String, at point: CGPoint) -> some View {
    Image(systemName: systemImage)
      .font(.system(size: Self.glyphSize, weight: .medium))
      .foregroundStyle(Color.primary.opacity(0.6))
      .position(point)
  }

  /// Close, minimise and zoom, in their colours, ending at the metrics'
  /// trailing edge.
  private func windowControls(centreY: CGFloat, trailingX: CGFloat) -> some View {
    let diameter: CGFloat = 14
    let pitch: CGFloat = 23
    return ForEach(0..<3, id: \.self) { index in
      Circle()
        .fill(Self.windowControlColours[index])
        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
        .frame(width: diameter, height: diameter)
        .position(x: trailingX - diameter / 2 - CGFloat(2 - index) * pitch, y: centreY)
    }
  }

  /// The top row's toggle, back, forward and reload, and the URL field, at
  /// the sidebar's own places.
  private func sidebarControls(width: CGFloat, controls: WindowControlsMetrics) -> some View {
    let pitch = 32 + TopRow.gap
    let reloadX = width - TopRow.trailing - 16
    let y = controls.centreY
    return ZStack(alignment: .topLeading) {
      glyph("sidebar.left", at: CGPoint(x: TopRow.hideSidebarX(width: width, controls: controls) + 16, y: y))
      glyph("arrow.left", at: CGPoint(x: reloadX - 2 * pitch, y: y))
      glyph("arrow.right", at: CGPoint(x: reloadX - pitch, y: y))
      glyph("arrow.clockwise", at: CGPoint(x: reloadX, y: y))
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.primary.opacity(0.15))
        .frame(width: width - 16, height: 38)
        .offset(x: 8, y: 46)
      Capsule().fill(Color.secondary.opacity(0.22))
        .frame(width: width * 0.42, height: 11)
        .offset(x: 22, y: 59.5)
    }
  }

  /// The page's card, with the toolbar across its top in that layout, its
  /// toggle, back, forward and reload at their slots.
  private func page(width: CGFloat, height: CGFloat, showsToolbar: Bool) -> some View {
    let toolbar = ToolbarArrangement.height
    let symbols = ["sidebar.left", "arrow.left", "arrow.right", "arrow.clockwise"]
    let contentTop = showsToolbar ? toolbar : 0
    return ZStack(alignment: .topLeading) {
      Color(nsColor: .textBackgroundColor)
      if showsToolbar {
        Rectangle().fill(Color(nsColor: ToolbarFill.background)).frame(height: toolbar)
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).offset(y: toolbar)
        ForEach(Array(zip(symbols, ToolbarArrangement.leadingCentres)), id: \.0) { symbol, x in
          glyph(symbol, at: CGPoint(x: x, y: toolbar / 2))
        }
      }
      // A heading and some text, so it reads as a page.
      VStack(alignment: .leading, spacing: 12) {
        Capsule().fill(Color.secondary.opacity(0.14)).frame(width: 110, height: 14)
        ForEach(0..<4, id: \.self) { index in
          Capsule().fill(Color.secondary.opacity(0.18)).frame(width: index == 3 ? 90 : 150, height: 8)
        }
      }
      .offset(x: 28, y: contentTop + 28)
    }
    .frame(width: width, height: height, alignment: .topLeading)
    .clipShape(
      UnevenRoundedRectangle(topLeadingRadius: PageCardView.cornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
  }

  /// Three tabs, the first one active.
  private func tabRows(width: CGFloat, top: CGFloat) -> some View {
    ForEach(0..<3, id: \.self) { index in
      let y = top + CGFloat(index) * 42
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(index == 0 ? Color(nsColor: .textBackgroundColor).opacity(0.9) : Color.clear)
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(index == 0 ? 0.9 : 0.5))
            .frame(width: 18, height: 18)
          Capsule().fill(Color.secondary.opacity(0.16)).frame(width: width * (0.5 - CGFloat(index) * 0.08), height: 10)
        }
        .padding(.leading, 12)
      }
      .frame(width: width - 16, height: 36)
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
                RoundedRectangle(cornerRadius: LayoutThumbnail.cornerRadius + 3, style: .continuous)
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

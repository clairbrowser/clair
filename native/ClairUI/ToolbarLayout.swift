// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// Where the toolbar's controls go across a card of a given width
/// (add-page-toolbar design D4), with Arc's metrics: the leading buttons at
/// fixed places, the trailing ones on a 36 pt pitch from the trailing edge,
/// and the host centred on the card. Each side leaves controls out before
/// they come too close to the host, as Arc does: the trailing side its
/// pinned extensions, farthest from the site controls first; the leading
/// side reload together with the link icon. Only then is the host truncated,
/// keeping its centre.
nonisolated struct ToolbarArrangement: Equatable {
  static let height: CGFloat = 32
  /// Arc's leading buttons with the sidebar hidden, from the card's leading
  /// edge: the sidebar toggle, back, forward and reload.
  static let leadingCentres: [CGFloat] = [21, 57.75, 94.75, 132]
  /// IconButtonSize.regular.
  static let buttonSize: CGFloat = 32
  /// The first trailing control, from the card's trailing edge, and the
  /// distance between them: Arc's site-controls and split-view buttons.
  static let trailingFirst: CGFloat = 21
  static let trailingPitch: CGFloat = 36
  /// Arc leaves a control out once it comes within this of the host: it kept
  /// one 14 pt from the link icon and left one out that touched the host.
  static let clearance: CGFloat = 8
  /// The host's text and the rounded background it shows under the pointer,
  /// which reaches 6.5 pt past the text on each side in Arc.
  static let hostFontSize: CGFloat = 13
  static let hostPadding: CGFloat = 6.5
  static let hostHeight: CGFloat = 24
  /// The link icon's button, which ends where the host's background starts:
  /// Arc's link glyph is centred 16 pt before the host's text.
  static let linkWidth: CGFloat = 19
  /// The not-secure icon, before the link icon.
  static let notSecureWidth: CGFloat = 16
  static let notSecureGap: CGFloat = 2

  /// What a toolbar holds.
  struct Content: Equatable {
    /// The leading controls that always show: the sidebar toggle, back and
    /// forward, or back and forward in a Peek.
    var leadingCount: Int
    var hasReload = true
    /// Whether the host has its link icon: not for the new tab page.
    var hasLink = true
    var hasNotSecure = false
    /// The host's width as it shows whole: its text and background.
    var hostWidth: CGFloat
    /// The trailing controls that always show: the site-controls button, or
    /// none in a Peek.
    var trailingFixedCount = 1
    var extensionCount = 0
    var indicatorCount = 0
  }

  /// The always-shown leading controls' centres, from the card's leading edge.
  private(set) var leading: [CGFloat] = []
  private(set) var reload: CGFloat?
  private(set) var notSecure: CGFloat?
  private(set) var link: CGFloat?
  /// The host's background frame, horizontally, centred on the card.
  private(set) var hostMinX: CGFloat = 0
  private(set) var hostWidth: CGFloat = 0
  /// The trailing controls that always show, nearest the trailing edge first.
  private(set) var trailingFixed: [CGFloat] = []
  /// Each pinned extension's centre in pinned order, or nil once left out.
  private(set) var extensions: [CGFloat?] = []
  private(set) var indicators: [CGFloat] = []

  init(width: CGFloat, content: Content) {
    let centre = width / 2
    let half = Self.buttonSize / 2
    let ideal = content.hostWidth
    let notSecureRoom = content.hasNotSecure ? Self.notSecureWidth + Self.notSecureGap : 0
    func hostLeft(link: Bool) -> CGFloat {
      centre - ideal / 2 - (link ? Self.linkWidth : 0) - notSecureRoom
    }
    func leadingCentre(_ slot: Int) -> CGFloat {
      slot < Self.leadingCentres.count
        ? Self.leadingCentres[slot]
        : Self.leadingCentres[Self.leadingCentres.count - 1] + CGFloat(slot - Self.leadingCentres.count + 1) * 37
    }
    func trailingCentre(_ slot: Int) -> CGFloat {
      width - Self.trailingFirst - CGFloat(slot) * Self.trailingPitch
    }

    // The leading side: reload and the link icon go together.
    leading = (0..<content.leadingCount).map(leadingCentre)
    let fixedEnd = leading.last.map { $0 + half } ?? 0
    var showsReload = content.hasReload
    var showsLink = content.hasLink
    if showsReload, leadingCentre(content.leadingCount) + half + Self.clearance > hostLeft(link: showsLink) {
      showsReload = false
      showsLink = false
    }
    let leadingEnd = showsReload ? leadingCentre(content.leadingCount) + half : fixedEnd
    reload = showsReload ? leadingCentre(content.leadingCount) : nil

    // The trailing side: the extensions farthest from the site controls go
    // first. The indicators stay, after the extensions kept.
    let fixedCount = content.trailingFixedCount
    trailingFixed = (0..<fixedCount).map(trailingCentre)
    var kept = content.extensionCount
    func trailingStart(extensions: Int) -> CGFloat {
      let slots = fixedCount + extensions + content.indicatorCount
      return slots == 0 ? width : trailingCentre(slots - 1) - half
    }
    while kept > 0, trailingStart(extensions: kept) - Self.clearance < centre + ideal / 2 {
      kept -= 1
    }
    let left = content.extensionCount - kept
    extensions = (0..<content.extensionCount).map { index in
      // The last pinned is nearest the site controls.
      index < left ? nil : trailingCentre(fixedCount + content.extensionCount - 1 - index)
    }
    indicators = (0..<content.indicatorCount).map { trailingCentre(fixedCount + kept + $0) }

    // The host keeps its centre, as wide as the nearer side allows.
    let trailingRoom = trailingStart(extensions: kept) - Self.clearance - centre
    let leadingRoom =
      centre - (content.leadingCount > 0 || showsReload ? leadingEnd + Self.clearance : 0)
      - (showsLink ? Self.linkWidth : 0) - notSecureRoom
    hostWidth = max(0, min(ideal, 2 * min(trailingRoom, leadingRoom)))
    hostMinX = centre - hostWidth / 2
    link = showsLink ? hostMinX - Self.linkWidth / 2 : nil
    let beforeHost = showsLink ? hostMinX - Self.linkWidth : hostMinX
    notSecure = content.hasNotSecure ? beforeHost - Self.notSecureGap - Self.notSecureWidth / 2 : nil
  }

  /// The host's width as it shows whole: its text and its background's
  /// padding.
  static func hostWidth(for text: String) -> CGFloat {
    let font = NSFont.systemFont(ofSize: hostFontSize, weight: .medium)
    let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
    return textWidth.rounded(.up) + 2 * hostPadding
  }
}

/// A toolbar control's place (add-page-toolbar D4), for `ToolbarLayout`.
nonisolated enum ToolbarRole: Equatable, Sendable {
  /// An always-shown leading control, by its slot.
  case leading(Int)
  case reload
  case notSecure
  case link
  case host
  /// An always-shown trailing control, by its slot from the trailing edge.
  case trailingFixed(Int)
  /// A pinned extension, by its pinned index.
  case pinnedExtension(Int)
  case indicator(Int)
}

private nonisolated struct ToolbarRoleKey: LayoutValueKey {
  static let defaultValue: ToolbarRole? = nil
}

extension View {
  func toolbarRole(_ role: ToolbarRole) -> some View {
    layoutValue(key: ToolbarRoleKey.self, value: role)
  }
}

/// Lays the toolbar's controls out by `ToolbarArrangement`, each centred on
/// the toolbar's centre line. The toolbar builds only the controls its
/// arrangement keeps; anything else goes out of sight.
struct ToolbarLayout: Layout {
  let content: ToolbarArrangement.Content

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: ToolbarArrangement.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let arrangement = ToolbarArrangement(width: bounds.width, content: content)
    let midY = bounds.midY
    for subview in subviews {
      guard let role = subview[ToolbarRoleKey.self] else { continue }
      var size: ProposedViewSize = .unspecified
      let x: CGFloat?
      switch role {
      case .leading(let slot): x = arrangement.leading.indices.contains(slot) ? arrangement.leading[slot] : nil
      case .reload: x = arrangement.reload
      case .notSecure: x = arrangement.notSecure
      case .link: x = arrangement.link
      case .host:
        x = arrangement.hostMinX + arrangement.hostWidth / 2
        size = ProposedViewSize(width: arrangement.hostWidth, height: ToolbarArrangement.hostHeight)
      case .trailingFixed(let slot):
        x = arrangement.trailingFixed.indices.contains(slot) ? arrangement.trailingFixed[slot] : nil
      case .pinnedExtension(let index):
        x = arrangement.extensions.indices.contains(index) ? arrangement.extensions[index] : nil
      case .indicator(let index):
        x = arrangement.indicators.indices.contains(index) ? arrangement.indicators[index] : nil
      }
      if let x {
        subview.place(at: CGPoint(x: bounds.minX + x, y: midY), anchor: .center, proposal: size)
      } else {
        subview.place(at: CGPoint(x: bounds.minX - 10_000, y: midY), anchor: .center, proposal: .zero)
      }
    }
  }
}

// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// The update banner at the bottom of the sidebar, above the footer
/// (add-update-banners D4): a pill while an update waits, which grows into a
/// card with Restart and Update on hover, or the "Update Complete!" card after
/// an update.
///
/// It takes only the pill's slot, 24 pt tall with 8 pt below it, inset 8 pt
/// from each side as in Arc. The cards are drawn in a bottom-aligned overlay,
/// so they grow upward over the tab list without moving it.
struct UpdateBannerView: View {
  let banner: UpdateBanner
  weak var actions: (any SidebarActions)?

  static let pillHeight: CGFloat = 24
  static let inset: CGFloat = 8

  /// The slot's own transition, as the pill shows or the complete card
  /// closes: Arc slides it down 15 pt as it fades (D5).
  static func slotTransition(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .offset(y: 15).combined(with: .opacity)
  }

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: Self.pillHeight)
      .padding(.bottom, Self.inset)
      .overlay(alignment: .bottom) {
        Group {
          switch banner {
          case .waiting:
            WaitingUpdateCard(actions: actions).transition(.opacity)
          case .complete(let version):
            UpdateCompleteCard(showsWhatsNew: UpdateBanner.releaseURL(forVersion: version) != nil, actions: actions)
              .transition(.opacity)
          case .none:
            EmptyView()
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset)
        .animation(.easeIn(duration: 0.12), value: banner)
      }
  }
}

/// The card's look (D4): a pill with a faint fill and border while closed, or
/// a raised card while open.
private struct UpdateCardBackground: View {
  let isOpen: Bool

  static let cardRadius: CGFloat = 10

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let shape = RoundedRectangle(
      cornerRadius: isOpen ? Self.cardRadius : UpdateBannerView.pillHeight / 2, style: .continuous)
    ZStack {
      // Arc's pill: about 4% darker than the sidebar, with a 9% border.
      shape.fill(Color.primary.opacity(0.04))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
        .opacity(isOpen ? 0 : 1)
      shape.fill(Color(nsColor: .controlBackgroundColor))
        // In Dark Mode the shadow barely shows, so a faint edge keeps the
        // card apart from the sidebar.
        .overlay(shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 6, y: 1)
        .opacity(isOpen ? 1 : 0)
    }
  }
}

/// The card's title row: 24 pt, the pill's text in the pill's style.
private struct UpdateCardTitle: View {
  let title: String
  /// Room kept clear at each side, for the close button.
  var sideInset: CGFloat = 10

  var body: some View {
    Text(title)
      .font(.system(size: 13))
      .foregroundStyle(.primary)
      .lineLimit(1)
      // At the 164 pt minimum the pill is 148 pt wide (D4).
      .minimumScaleFactor(0.85)
      .truncationMode(.tail)
      .padding(.horizontal, sideInset)
      .frame(maxWidth: .infinity)
      .frame(height: UpdateBannerView.pillHeight)
  }
}

/// The line under the title row.
private struct UpdateCardHairline: View {
  var body: some View {
    Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
  }
}

/// "New Clair Version Available": a pill that opens into a card with Restart
/// and Update while the pointer is over it (D4, D5). Whether it's open is the
/// window's own.
private struct WaitingUpdateCard: View {
  weak var actions: (any SidebarActions)?

  static let title = "New Clair Version Available"
  /// Arc's card is fully drawn within about 120 ms, overshoots slightly and
  /// settles by about 300 ms.
  static let openAnimation = Animation.spring(response: 0.25, dampingFraction: 0.8)
  static let collapseAnimation = Animation.easeOut(duration: 0.15)

  @State private var isOpen = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if reduceMotion {
        // The pill and the card cross-fade in place.
        ZStack(alignment: .bottom) {
          card(open: false)
            .opacity(isOpen ? 0 : 1)
            .allowsHitTesting(!isOpen)
            .onHover { if $0 { setOpen(true) } }
          card(open: true)
            .opacity(isOpen ? 1 : 0)
            .allowsHitTesting(isOpen)
            .onHover { if !$0 { setOpen(false) } }
        }
      } else {
        // The pill grows upward into the card, its bottom edge fixed.
        card(open: isOpen).onHover { setOpen($0) }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.updateBanner")
  }

  private func setOpen(_ open: Bool) {
    guard open != isOpen else { return }
    let animation =
      reduceMotion ? .easeInOut(duration: 0.15) : (open ? Self.openAnimation : Self.collapseAnimation)
    withAnimation(animation) { isOpen = open }
  }

  private func card(open: Bool) -> some View {
    VStack(spacing: 0) {
      UpdateCardTitle(title: Self.title)
      if open {
        VStack(spacing: 0) {
          UpdateCardHairline()
          RestartAndUpdateButton { actions?.restartToUpdate() }
            .padding(8)
        }
        .transition(.opacity)
      }
    }
    .background { UpdateCardBackground(isOpen: open) }
    .contentShape(.rect(cornerRadius: UpdateCardBackground.cardRadius))
  }
}

/// The card's button: a plain accent fill with white text, without Arc's
/// colour animation (proposal).
private struct RestartAndUpdateButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text("Restart and Update")
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(Color.accentColor, in: .rect(cornerRadius: 6, style: .continuous))
        .contentShape(.rect(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("clair.updateBanner.restart")
  }
}

/// "Update Complete!", open without hover, with a close button and See What's
/// New (D4). Nothing on it animates while it sits open.
private struct UpdateCompleteCard: View {
  /// False when the version has no release page to open (D6).
  let showsWhatsNew: Bool
  weak var actions: (any SidebarActions)?

  /// The close button's hit area.
  static let closeSize: CGFloat = 20

  var body: some View {
    VStack(spacing: 0) {
      UpdateCardTitle(title: "Update Complete!", sideInset: Self.closeSize + 6)
        .overlay(alignment: .trailing) {
          IconButton(
            systemImage: "xmark", help: "Close", size: Self.closeSize, cornerRadius: 5, glyphSize: 11,
            glyphWeight: .semibold, dimsWhenInactive: false
          ) { actions?.closeUpdateComplete() }
          .accessibilityIdentifier("clair.updateComplete.close")
          .padding(.trailing, 2)
        }
      if showsWhatsNew {
        UpdateCardHairline()
        WhatsNewRow { actions?.updateWhatsNewChosen() }
          .padding(.horizontal, 4)
          .padding(.vertical, 6)
      }
    }
    .background { UpdateCardBackground(isOpen: true) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.updateComplete")
  }
}

/// "See What's New" with a heart, in plain accent colour, and a hover
/// highlight (D4).
private struct WhatsNewRow: View {
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "heart.circle.fill").font(.system(size: 14))
        Text("See What's New").font(.system(size: 13)).lineLimit(1)
        Spacer(minLength: 0)
      }
      .foregroundStyle(Color.accentColor)
      // 8 pt from the card's leading edge, with the row's 4 pt inset.
      .padding(.horizontal, 4)
      .frame(height: 22)
      .background(
        Color.primary.opacity(isHovered ? 0.06 : 0), in: .rect(cornerRadius: 5, style: .continuous)
      )
      .animation(sidebarHoverFade, value: isHovered)
      .contentShape(.rect)
      .onHover { isHovered = $0 }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("clair.updateComplete.whatsNew")
  }
}

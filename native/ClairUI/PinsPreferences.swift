// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation

/// The user's choices about pinned tabs and favorites, kept across launches
/// (add-pinned-tabs-and-favorites design D11).
struct PinsPreferences {
  /// The Spaces whose pinned section is collapsed, in every window.
  static let collapsedKey = "ClairCollapsedPinnedSpaces"
  /// The profiles whose "Drag to add Favorites" box is done with: dismissed,
  /// or the profile got a favorite.
  static let favoritesHintKey = "ClairFavoritesHintDone"
  /// Posted when a Space's pinned section collapses or expands, so every
  /// window showing it follows.
  static let collapsedDidChange = Notification.Name("ClairCollapsedPinnedSpacesDidChange")

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func isCollapsed(_ spaceID: SpaceID) -> Bool {
    (defaults.stringArray(forKey: Self.collapsedKey) ?? []).contains(spaceID)
  }

  func setCollapsed(_ collapsed: Bool, for spaceID: SpaceID) {
    var spaces = defaults.stringArray(forKey: Self.collapsedKey) ?? []
    spaces.removeAll { $0 == spaceID }
    if collapsed {
      spaces.append(spaceID)
    }
    defaults.set(spaces, forKey: Self.collapsedKey)
    NotificationCenter.default.post(name: Self.collapsedDidChange, object: nil)
  }

  /// Whether the empty favorites box shows for a profile with no favorites:
  /// never again once it's done with.
  func showsFavoritesHint(for profileID: ProfileID, favoriteCount: Int) -> Bool {
    favoriteCount == 0 && !(defaults.stringArray(forKey: Self.favoritesHintKey) ?? []).contains(profileID)
  }

  /// The profile's box is done with: dismissed, or it has a favorite.
  func finishFavoritesHint(for profileID: ProfileID) {
    var profiles = defaults.stringArray(forKey: Self.favoritesHintKey) ?? []
    guard !profiles.contains(profileID) else { return }
    profiles.append(profileID)
    defaults.set(profiles, forKey: Self.favoritesHintKey)
  }
}

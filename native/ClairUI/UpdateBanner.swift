// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Observation

/// What the sidebar's update banner shows (add-update-banners D1).
enum UpdateBanner: Equatable {
  case none
  /// "New Clair Version Available": a downloaded update is waiting.
  case waiting(version: String)
  /// "Update Complete!": the first launch of `version`, newer than the last.
  case complete(version: String)

  /// The GitHub release page of `version`, or nil when it isn't a plain
  /// dotted number, as for a development package with an unusual version
  /// (add-update-banners D6).
  static func releaseURL(forVersion version: String) -> URL? {
    guard version.wholeMatch(of: #/[0-9]+(\.[0-9]+)*/#) != nil else {
      return nil
    }
    return URL(string: "https://github.com/clairbrowser/clair/releases/tag/v\(version)")
  }
}

/// The app-wide banner, which every window's sidebar reads. `UpdateController`
/// owns the only instance in the app and is its only writer, so every window
/// agrees and a close in one applies to all (add-update-banners D1).
@Observable
final class UpdateBannerState {
  var banner: UpdateBanner = .none

  /// An instance no updater writes to, for windows built outside Clair.app.
  static let detached = UpdateBannerState()
}

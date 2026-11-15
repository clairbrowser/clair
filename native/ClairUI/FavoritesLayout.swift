// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import CoreGraphics

/// Where the favorites grid puts its tiles (add-pinned-tabs-and-favorites
/// design D11, "Arc reference"): rows of at most four, as few rows as that
/// allows and as few columns as those rows allow, tiles 47 pt tall sharing the
/// width less 8 pt at the edges and between tiles.
struct FavoritesLayout: Equatable {
  static let maxColumns = 4
  static let tileHeight: CGFloat = 47
  static let inset: CGFloat = 8
  static let gap: CGFloat = 8

  let count: Int
  let rows: Int
  let columns: Int
  /// Each tile's width.
  let tileWidth: CGFloat
  /// The grid's height, insets included.
  let height: CGFloat

  /// The layout of `count` tiles in a sidebar `width` wide.
  init(count: Int, width: CGFloat) {
    self.count = max(count, 0)
    rows = count > 0 ? (count + Self.maxColumns - 1) / Self.maxColumns : 0
    columns = rows > 0 ? (count + rows - 1) / rows : 0
    let inner = width - 2 * Self.inset - CGFloat(max(columns - 1, 0)) * Self.gap
    tileWidth = columns > 0 ? max(inner / CGFloat(columns), 0) : 0
    height = rows > 0 ? 2 * Self.inset + CGFloat(rows) * Self.tileHeight + CGFloat(rows - 1) * Self.gap : 0
  }

  /// The frame of tile `index`, from the grid's top-leading corner: rows fill
  /// from the leading edge.
  func frame(of index: Int) -> CGRect {
    guard columns > 0, index >= 0 else { return .zero }
    let row = index / columns
    let column = index % columns
    return CGRect(
      x: Self.inset + CGFloat(column) * (tileWidth + Self.gap),
      y: Self.inset + CGFloat(row) * (Self.tileHeight + Self.gap),
      width: tileWidth, height: Self.tileHeight)
  }

  /// The index a tile dropped at `point` takes among the others: before the
  /// tile under it whose leading half holds the point, or after it.
  func dropIndex(at point: CGPoint) -> Int {
    guard count > 0, columns > 0 else { return 0 }
    let row = min(max(Int((point.y - Self.inset) / (Self.tileHeight + Self.gap)), 0), rows - 1)
    let pitch = tileWidth + Self.gap
    let column = min(max(Int(((point.x - Self.inset) + pitch / 2) / pitch), 0), columns)
    return min(row * columns + column, count)
  }
}

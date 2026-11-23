// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// drag <x1> <y1> <x2> <y2> [<x3> <y3>]... [<hold seconds>]
//
// Drags with the mouse's own events, in screen points (as `probe.sh send tree`
// prints frames), at a hand's speed: press, hold, move in steps through each
// point, hold, let go. For SwiftUI drag gestures in Clair, which the probe's
// XCUITest `drag` doesn't reach. It holds 0.3 s at the end before letting go,
// or as long as a last odd number gives, which leaves time to screenshot the
// drag. It moves the real pointer, and the shell it runs from needs
// permission to post events (Privacy & Security > Accessibility). Bring the
// app forward first (`probe.sh send activate`). Arc ignores these events.

import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let numbers = arguments.compactMap { Double($0) }
guard numbers.count == arguments.count, numbers.count >= 4 else {
  FileHandle.standardError.write("usage: drag <x1> <y1> <x2> <y2> [<x3> <y3>]... [<hold seconds>]\n".data(using: .utf8)!)
  exit(2)
}
guard CGPreflightPostEventAccess() else {
  FileHandle.standardError.write("drag: this shell may not post events (Privacy & Security > Accessibility)\n".data(using: .utf8)!)
  exit(1)
}
let hold = numbers.count % 2 == 1 ? max(numbers[numbers.count - 1], 0) : 0.3
let points = stride(from: 0, to: numbers.count - 1, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }

func post(_ type: CGEventType, _ point: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
}

post(.mouseMoved, points[0])
usleep(200_000)
post(.leftMouseDown, points[0])
usleep(300_000)
let steps = 30
for (from, to) in zip(points, points.dropFirst()) {
  for step in 1...steps {
    let t = Double(step) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
    usleep(16_000)
  }
}
usleep(useconds_t(hold * 1_000_000))
post(.leftMouseUp, points[points.count - 1])

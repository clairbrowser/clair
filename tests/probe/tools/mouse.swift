// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// mouse move <x> <y>
// mouse click <x> <y>
// mouse doubleclick <x> <y>
//
// Moves the real pointer to a point in screen points (as `probe.sh send tree`
// prints frames), and clicks there with `click`, or twice with `doubleclick`. For when the probe's own
// `hover` and `click` can't reach: they're relative to the app's first window,
// which is a dialog while one shows, and a SwiftUI hover in a window that isn't
// key (a sidebar row's close button behind a page's alert) didn't appear for
// the probe's hover. Like `drag`, the shell needs permission to post events
// (Privacy & Security > Accessibility). Bring the app forward first
// (`probe.sh send activate`): the click lands on whatever is under the point.

import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let numbers = arguments.dropFirst().compactMap { Double($0) }
guard arguments.count == 3, ["move", "click", "doubleclick"].contains(arguments[0]), numbers.count == 2 else {
  FileHandle.standardError.write("usage: mouse move|click|doubleclick <x> <y>\n".data(using: .utf8)!)
  exit(2)
}
guard CGPreflightPostEventAccess() else {
  FileHandle.standardError.write("mouse: this shell may not post events (Privacy & Security > Accessibility)\n".data(using: .utf8)!)
  exit(1)
}
let point = CGPoint(x: numbers[0], y: numbers[1])

func post(_ type: CGEventType, clickCount: Int64 = 1) {
  let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
  event?.setIntegerValueField(.mouseEventClickState, value: clickCount)
  event?.post(tap: .cghidEventTap)
}

// Two moves, so a view's hover sees the pointer arrive.
post(.mouseMoved)
usleep(150_000)
post(.mouseMoved)
if arguments[0] != "move" {
  usleep(300_000)
  // A double-click's second press and release carry a click count of 2.
  for count in Int64(1)...(arguments[0] == "doubleclick" ? 2 : 1) {
    post(.leftMouseDown, clickCount: count)
    usleep(60_000)
    post(.leftMouseUp, clickCount: count)
    usleep(60_000)
  }
}

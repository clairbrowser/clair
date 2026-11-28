// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// keys <step>...
//
// Posts real key events, with Ctrl and Shift held across steps, which
// XCUITest's typeKey can't do: it lets go of its modifiers after each key.
// For Ctrl+Tab's switcher (add-tab-switcher-and-tabs-menu design D8), in Arc
// and in Clair. The steps run in order:
//
//   ctrldown, ctrlup     press or release Control
//   shiftdown, shiftup   press or release Shift
//   tab, esc             press and release Tab or Esc, with what's held
//   escdown, escup       press or release Esc, to hold it across steps, such
//                        as escdown sleep:2 escup for a press and hold
//   sleep:<seconds>      wait, such as sleep:0.5
//   shot:<png>:<x,y,w,h> capture a screen rectangle in points to <png>
//
// For example: keys ctrldown tab sleep:0.5 shot:build/probe/s.png:0,0,963,1006 ctrlup
//
// A step that holds a key and no step that lets it go leaves it held: the
// tool releases Control, Shift and Esc at the end. Like `drag` and `mouse`, the
// shell needs permission to post events (Privacy & Security > Accessibility).
// Bring the app forward first (`probe.sh send activate`): the keys go to
// whatever app is active.

import CoreGraphics
import Foundation

let controlKey: CGKeyCode = 59
let shiftKey: CGKeyCode = 56
let tabKey: CGKeyCode = 48
let escapeKey: CGKeyCode = 53

func fail(_ message: String, status: Int32 = 2) -> Never {
  FileHandle.standardError.write("keys: \(message)\n".data(using: .utf8)!)
  exit(status)
}

let steps = Array(CommandLine.arguments.dropFirst())
guard !steps.isEmpty else {
  fail("usage: keys ctrldown|ctrlup|shiftdown|shiftup|tab|esc|escdown|escup|sleep:<s>|shot:<png>:<x,y,w,h>...")
}
guard CGPreflightPostEventAccess() else {
  fail("this shell may not post events (Privacy & Security > Accessibility)", status: 1)
}

// Every step is checked before any key goes, so a wrong one leaves nothing
// held.
func isValid(_ step: String) -> Bool {
  if ["ctrldown", "ctrlup", "shiftdown", "shiftup", "tab", "esc", "escdown", "escup"].contains(step) { return true }
  if step.hasPrefix("sleep:") { return Double(step.dropFirst("sleep:".count)).map { $0 >= 0 } ?? false }
  if step.hasPrefix("shot:") {
    let parts = step.dropFirst("shot:".count).split(separator: ":", maxSplits: 1)
    return parts.count == 2 && !parts[0].isEmpty && parts[1].split(separator: ",").compactMap { Double($0) }.count == 4
  }
  return false
}
if let wrong = steps.first(where: { !isValid($0) }) {
  fail("unknown step \(wrong)")
}

var held: CGEventFlags = []
var escapeHeld = false
let source = CGEventSource(stateID: .hidSystemState)

func post(_ key: CGKeyCode, down: Bool) {
  let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
  event?.flags = held
  event?.post(tap: .cghidEventTap)
  usleep(15_000)
}

func modifier(_ key: CGKeyCode, _ flag: CGEventFlags, down: Bool) {
  if down { held.insert(flag) } else { held.remove(flag) }
  post(key, down: down)
}

/// Lets go of what's held, so a failure leaves no key down.
func releaseHeld() {
  if escapeHeld { holdEscape(false) }
  if held.contains(.maskShift) { modifier(shiftKey, .maskShift, down: false) }
  if held.contains(.maskControl) { modifier(controlKey, .maskControl, down: false) }
}

func releaseAndFail(_ message: String) -> Never {
  releaseHeld()
  fail(message, status: 1)
}

func holdEscape(_ down: Bool) {
  escapeHeld = down
  post(escapeKey, down: down)
}

func press(_ key: CGKeyCode) {
  post(key, down: true)
  usleep(30_000)
  post(key, down: false)
}

/// screencapture's rectangle, from "x,y,w,h" in points.
func shoot(_ argument: Substring) {
  let parts = argument.split(separator: ":", maxSplits: 1)
  let numbers = parts.count == 2 ? parts[1].split(separator: ",").compactMap { Double($0) } : []
  guard parts.count == 2, !parts[0].isEmpty, numbers.count == 4 else {
    releaseAndFail("shot needs <png>:<x,y,w,h>, got \(argument)")
  }
  let rect = numbers.map { String(Int($0.rounded())) }.joined(separator: ",")
  let capture = Process()
  capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  capture.arguments = ["-x", "-R", rect, String(parts[0])]
  do {
    try capture.run()
    capture.waitUntilExit()
  } catch {
    releaseAndFail("screencapture didn't run: \(error)")
  }
  // screencapture exits 0 when it can't write the file.
  guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: String(parts[0])) else {
    releaseAndFail("screencapture didn't write \(parts[0])")
  }
}

for step in steps {
  switch step {
  case "ctrldown": modifier(controlKey, .maskControl, down: true)
  case "ctrlup": modifier(controlKey, .maskControl, down: false)
  case "shiftdown": modifier(shiftKey, .maskShift, down: true)
  case "shiftup": modifier(shiftKey, .maskShift, down: false)
  case "tab": press(tabKey)
  case "esc": press(escapeKey)
  case "escdown": holdEscape(true)
  case "escup": holdEscape(false)
  default:
    if step.hasPrefix("sleep:"), let seconds = Double(step.dropFirst("sleep:".count)), seconds >= 0 {
      usleep(useconds_t(seconds * 1_000_000))
    } else if step.hasPrefix("shot:") {
      shoot(step.dropFirst("shot:".count))
    } else {
      fail("unknown step \(step)")
    }
  }
}

// Nothing stays held once the tool is done.
releaseHeld()

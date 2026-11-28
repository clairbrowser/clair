# Proposal

## Why

Arc shows its short state notices in the popup at the card's top-trailing corner: how to leave full screen, however it was entered; that a page has hidden the cursor; and the zoom level. Clair shows only some of them there, in Chromium's wording: the window's own full screen shows no notice, a pointer lock reads "To show your cursor, press Esc", and the zoom level is a toast at the bottom of the card.

## What Changes

- **Pointer lock:** while a page holds the pointer lock outside page full screen, the popup reads "Your cursor is hidden. Press [esc] to show cursor." In page full screen, the full-screen notice still shows. Esc ends the lock and hides the popup.
- **Window full screen:** entering full screen by any route (View › Enter Full Screen, the green button, Ctrl+Cmd+F, an extension) shows "To exit full screen, press [esc]" in the popup. As in Arc, an Esc that reaches the page, or that nothing else in the window uses, shows "[esc] again to exit fullscreen", and a second one in quick succession leaves full screen, wherever the keyboard focus is in the window. An Esc that closes the command bar, find or a dialog sheet only does that. One Esc no longer leaves the window's full screen, as AppKit made it, and holding Esc, Chromium's way, doesn't either.
- **One time for every notice:** each notice in the popup shows for the popup's own time, Copy URL's 5 s, and hides sooner only when what it describes ends.
- **Key caps:** every notice labels its key "esc", as Arc does, so page full screen's becomes "To exit full screen, press [esc]".
- **Downloads:** a download that starts in full screen or during a pointer lock no longer shows "Download started. To see it, press [Esc]." The popup keeps whatever it shows.
- **Zoom:** changing a page's zoom shows the level alone, such as "110%", in the popup, in place of the "Zoom: 110%" toast.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `browser-window`: adds requirements for the popup's timing, the hidden-cursor notice, the window full-screen notice, the double tap of Esc that leaves it, and the zoom notice, and changes "Full screen" so its notice's key cap reads "esc".

## Impact

- `engine/overlay/chrome/browser/clair/window/`: `ClairExclusiveAccessContext` writes the pointer-lock text, shows the browser and extension full-screen notices, passes `esc` as the key, counts Esc taps in the window's full screen and leaves it however it was entered; `ClairNativeWindow`'s `cancelOperation:` counts an unused Esc rather than leaving full screen; `ZoomChanged` reports the level to the new contract method.
- `engine/patches/clair/esc-double-tap.patch`: turns Chromium's `kPressAndHoldEscToExitBrowserFullscreen` off by default.
- `native/ClairHost.h`: **BREAKING** for the contract only: a `showZoomLevel:` method on the window. The engine key changes, so it needs an engine build.
- `native/ClairUI/`: the zoom notice in the popup, and `NoticePopupView.markingKeys` drawing a bare "Esc" as an "esc" key cap, with unit tests and the fakes.
- `tests/runtime/`: a pointer-lock page and tests in `FullscreenTests`, and a zoom test.
- A Changie fragment (user-facing).

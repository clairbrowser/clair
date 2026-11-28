# Design

## Context

See proposal.md for why and `specs/browser-window/spec.md` for the behavior.

**The popup today:** `ClairExclusiveAccessContext::UpdateExclusiveAccessBubble` (`engine/overlay/chrome/browser/clair/window/clair_browser_window.mm`) turns each exclusive-access bubble into text with Chromium's `exclusive_access_bubble::GetInstructionTextForType` and sends it to `showExclusiveAccessNotice:`. `ClairUI` shows it in the top-trailing popup (`NoticeState`, identifier `clair.fullscreenNotice`; `replace-browser-window` design D18), drawing each `|key|` as a `KeyCap`. `ClairUI` keeps it until the engine hides it: a timer of `ExclusiveAccessBubble::kShowTime` (3.8 s) does, and runs Chromium's first-hide callback, and the end of the mode does at once. Copy URL's notice shows for `NoticeState.copiedDuration` (5 s). Types for which `IsExclusiveAccessModeBrowserFullscreen` is true, the browser's and an extension's full screen, are hidden on purpose.

**What Chromium sends:**
- A pointer lock: `POINTERLOCK_EXIT_INSTRUCTION` outside full screen ("To show your cursor, press |Esc|"), `FULLSCREEN_POINTERLOCK_EXIT_INSTRUCTION` in tab full screen, whose text is the full-screen one.
- Window full screen: whenever the window enters it by any route, Clair's `WindowFullscreenChanged` calls `FullscreenController::WindowFullscreenStateChanged`, which calls `ExclusiveAccessManager::UpdateBubble(force_update)`, which sends `BROWSER_FULLSCREEN_EXIT_INSTRUCTION` (or the extension type). With `kPressAndHoldEscToExitBrowserFullscreen`, enabled by default, its text is "To exit full screen, press and hold |Esc|".
- Esc: with that feature, `ExclusiveAccessManager::HandleUserKeyEvent` starts a 1.5 s hold timer on an unmodified Esc key-down, re-shows the notice after 0.5 s of holding, and exits full screen when the timer fires; a key-up before then cancels it. In window full screen, no controller handles a quick Esc, so it returns false and the key goes on. Chromium calls it from the page's keyboard pre-handling (`BrowserWebContentsDelegate::PreHandleKeyboardEvent`, before `BrowserWindow::PreHandleKeyboardEvent`); `ClairBrowserWindow::HandleExclusiveAccessKey`, called from the native window's `sendEvent:`, calls it only in page full screen. An Esc that nothing in the window uses reaches `-[NSWindow cancelOperation:]`, which leaves macOS full screen on one tap; Chromium gives a page's unhandled Esc back to the window, so it gets there too.
- Zoom: `ClairBrowserWindow::ZoomChanged(can_show_bubble)` shows `IDS_TOOLTIP_ZOOM` ("Zoom: 110%") through `ShowToast`.

**Arc's full screen, probed on 2026-11-27** with `tests/probe/` (real key events, the page's Esc events counted by `esc.html`):
- Entering the window's full screen, by any route, shows "To exit full screen, press ⎋." for 3 to 5 s, the same text as a page's full screen, drawn over the toolbar at the window's top edge.
- In the window's full screen, an Esc that reaches the page shows "[⎋] again to exit fullscreen" in the card's top-trailing corner, gone by 5 s, with an "Edit the shortcut ↗" link under it after about 2 s. The page still gets the Esc.
- A second Esc leaves full screen only when its key-down comes about 0.23 s or less after the first's: 0.22 s left it, 0.24 s didn't. Holding Esc does nothing more.
- An Esc that closes the command bar only closes it: no notice, and it doesn't count as the first tap.
- A page's own full screen leaves on one Esc, whether the page locks the pointer or not.

The rest of the wording and placement comes from the owner.

## Goals / Non-Goals

**Goals:** Arc's notices in the popup, Chromium's exclusive-access bookkeeping unchanged, and Arc's double tap of Esc to leave the window's full screen, from anywhere in the window.

**Non-Goals:**
- A cursor a page hides with CSS (`cursor: none`): Esc can't bring it back, and Chromium shows nothing for it.
- Changing the popup's look or place, or zoom controls in the popup: the entering notice shows in the popup, not over the toolbar as in Arc, and its key is an "esc" key cap, not Arc's ⎋ glyph (D2).
- Arc's "Edit the shortcut ↗" link under the "again" notice: Clair has no setting for the shortcut.
- Chromium's full-screen exit "X" button, which belongs to its own window.

## Decisions

### D1. The engine writes the pointer-lock text

In `UpdateExclusiveAccessBubble`, a `POINTERLOCK_EXIT_INSTRUCTION` sends "Your cursor is hidden. Press |esc| to show cursor." to `showExclusiveAccessNotice:` in place of Chromium's text. Every other type keeps Chromium's text. Its accessibility label reads "Your cursor is hidden. Press esc to show cursor."

**Alternatives:** matching Chromium's text in `ClairUI` (ties it to Chromium's string, which changes with the locale and versions); a contract method for the notice's kind (a contract change for one string); a patch to `IDS_PRESS_TO_EXIT_MOUSELOCK` (a Chromium file for text Clair's own overlay already chooses).

### D2. Every notice's key reads "esc"

Lowercase, as Arc's tooltips label the key ("Stop loading this page esc"). Arc's full-screen notices draw a ⎋ glyph; the owner chose the "esc" key cap for every notice. The engine passes `u"esc"`, not `u"Esc"`, as the accelerator, so every Chromium text it shows, full screen's and keyboard lock's, carries `|esc|`. `NoticePopupView.markingKeys`, which turns a bare "Esc" into a key for texts without markers, writes `|esc|` too.

**Alternative:** lowercase the label in `KeyCap`: it would also change the keys tooltips show, which follow the menus' glyphs.

### D3. The window's full screen: its notice and Arc's double tap

`UpdateExclusiveAccessBubble` stops hiding the browser and extension full-screen types and shows them like the others, so every route into window full screen shows its notice. `HideNotice` on leaving full screen already covers them.

A Clair patch, `clair/esc-double-tap.patch`, turns `kPressAndHoldEscToExitBrowserFullscreen` off by default in `chrome/browser/ui/ui_features.cc`. Chromium's text for those types is then "To exit full screen, press |esc|", Arc's, and its press-and-hold no longer runs, so holding Esc doesn't leave full screen.

In the window's own full screen, with no page in full screen, `ClairExclusiveAccessContext` counts Esc taps as Arc does. An unmodified Esc key-down that isn't a repeat counts when it reaches the page, in `ClairBrowserWindow::PreHandleKeyboardEvent` (which returns not handled, so the page still gets it), or when nothing else in the window used it and it reaches `ClairNativeWindow`'s `cancelOperation:`. There it no longer leaves full screen on one tap: the window's `cancelOperation:` calls `super` only outside the window's own full screen. A page's Esc that Chromium gives back to the window unhandled reaches both; one with the same event timestamp as the last counted one counts once. An Esc that the command bar, find or a field in the sidebar takes never reaches either, so it does only what it did, as in Arc. A dialog sheet (`ClairDialogWindow`) is a window of its own, so its Esc never counts.

The first tap shows "|esc| again to exit fullscreen", Arc's wording, through `showExclusiveAccessNotice:` (so the end of full screen hides it, D6) and keeps its time. A second tap whose key-down comes less than 0.23 s after the first's leaves full screen through `FullscreenController`, as `IDC_FULLSCREEN` does, which calls `ExclusiveAccessContext::ExitFullscreen`. That left only a full screen a page or Chromium itself had entered; with no page in full screen, it now leaves the window's own full screen however it was entered, the green button or AppKit's Ctrl+Cmd+F too. A later tap starts over. While a page is in full screen, one Esc leaves it, as before and as in Arc.

**Alternatives:** Chromium's press-and-hold, which this change first built (the owner prefers Arc's taps: no holding and waiting); counting every Esc from `sendEvent:` (it would count the Esc that closes the command bar, which Arc doesn't); AppKit's single tap (a stray Esc for the page or the sidebar leaves full screen); a longer time between taps (Arc's is short so that two Escs meant for the page rarely exit).

### D4. The zoom level goes to the popup through the contract

A new `ClairWindow` method, `- (void)showZoomLevel:(NSInteger)percent`, replaces the toast in `ZoomChanged`. `ClairUI` shows `Notice(text: "\(percent)%", identifier: "clair.zoomNotice")` in the popup. `NoticeState.show` already replaces a showing notice in place, so repeated zooms update one popup. A zoom replaces an exclusive-access notice that's up, as Copy URL does; a later exclusive-access notice replaces the zoom one.

The engine sends the number and `ClairUI` formats it, so the text has no Chromium string and no locale-dependent format in it.

**Alternatives:** formatting "110%" in the engine and reusing `showExclusiveAccessNotice:` (that call keeps its notice until nil, and its hide would take a zoom notice with it); a generic `showNotice:` (no other caller yet).

### D5. Esc ends a pointer lock through Chromium

Esc outside full screen reaches `ExclusiveAccessManager` through the page's keyboard pre-handling, which unlocks the pointer and sends `EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE`, hiding the popup. The runtime test checks it.

### D6. The popup times every notice itself

`NoticeState` gets one duration for every notice, today's `copiedDuration` (5 s, Arc's for Copy URL) renamed `duration`, and `show` always uses it; callers no longer pass one. `showExclusiveAccessNotice:` with text shows it like any other notice, and with nil hides it only if it is still the one showing, as now.

So the engine only hides a notice early: when the mode ends (`HideNotice` with `kInterrupted`) it sends nil, and when `kShowTime` runs out it no longer does. The timer stays for Chromium's bookkeeping, `IsExclusiveAccessBubbleDisplayed()` and the first-hide callback with `kTimeout`, so Chromium sees what it saw before.

**Alternative:** let the engine keep timing its notices: they'd show for 3.8 s and Clair's own for 5 s.

### D7. No download notices

`UpdateExclusiveAccessBubble` always asks `GetInstructionTextForType` for the text with `has_download` false, so a mode's notice never mentions a download. Params with `has_download` and `EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE`, Chromium's "keep the current notice and add the download to it", change nothing: the popup stays as it is, and the first-hide callback runs at once with `kNotShown`, as for any notice that isn't shown. The download still appears in the downloads list as usual.

**Alternative:** a Clair notice of its own for a download in full screen: the owner asked for none.

## Risks / Trade-offs

- [Esc doesn't end a pointer lock in Clair's native window] → The runtime test reads `document.pointerLockElement` after Esc.
- [XCUITest's keys are slow, and a hosted runner can't post key events] → The runtime test sends the two taps as one `typeText` of two Esc characters, which XCUITest types as fast as it can. If they come further apart than Arc's time, the test reports it.
- [Two quick Escs meant for a page, such as a game, leave full screen] → As in Arc.
- [The full-screen notice now shows on every entry, including a window restored in full screen at launch] → That is Arc's behavior as the owner describes it.
- [Pointer lock needs a user gesture and the window's focus on the runner] → The test asks for the lock through the harness's `Runtime.evaluate`, which passes `userGesture: true`, after bringing the window forward.
- [The popup's identifier for exclusive-access notices stays `clair.fullscreenNotice`] → Not shown to anyone; tests tell the notices apart by their text.
- [The engine key and the contract change] → One engine build before merging, with `ClairUI` updated in the same PR.

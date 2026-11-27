# Design

## Context

See proposal.md for why and `specs/browser-window/spec.md` for the behavior.

**The popup today:** `ClairExclusiveAccessContext::UpdateExclusiveAccessBubble` (`engine/overlay/chrome/browser/clair/window/clair_browser_window.mm`) turns each exclusive-access bubble into text with Chromium's `exclusive_access_bubble::GetInstructionTextForType` and sends it to `showExclusiveAccessNotice:`. `ClairUI` shows it in the top-trailing popup (`NoticeState`, identifier `clair.fullscreenNotice`; `replace-browser-window` design D18), drawing each `|key|` as a `KeyCap`. A timer of `ExclusiveAccessBubble::kShowTime` (3.8 s) hides it and runs Chromium's first-hide callback, and the end of the mode hides it at once. Types for which `IsExclusiveAccessModeBrowserFullscreen` is true, the browser's and an extension's full screen, are hidden on purpose.

**What Chromium sends:**
- A pointer lock: `POINTERLOCK_EXIT_INSTRUCTION` outside full screen ("Press |Esc| to show your cursor"), `FULLSCREEN_POINTERLOCK_EXIT_INSTRUCTION` in tab full screen, whose text is the full-screen one.
- Window full screen: whenever the window enters it by any route, Clair's `WindowFullscreenChanged` calls `FullscreenController::WindowFullscreenStateChanged`, which calls `ExclusiveAccessManager::UpdateBubble(force_update)`, which sends `BROWSER_FULLSCREEN_EXIT_INSTRUCTION` (or the extension type). With `kPressAndHoldEscToExitBrowserFullscreen`, enabled by default, its text is "Press and hold |Esc| to exit full screen".
- Esc: `ExclusiveAccessManager::HandleUserKeyEvent` starts a 1.5 s hold timer on an unmodified Esc key-down, re-shows the notice after 0.5 s of holding, and exits full screen when the timer fires; a key-up before then cancels it. In window full screen, no controller handles a quick Esc, so it returns false and the key goes on. Chromium calls it from the page's keyboard pre-handling; `ClairBrowserWindow::HandleExclusiveAccessKey`, called from the native window's `sendEvent:`, calls it only in page full screen.
- Zoom: `ClairBrowserWindow::ZoomChanged(can_show_bubble)` shows `IDS_TOOLTIP_ZOOM` ("Zoom: 110%") through `ShowToast`.

Arc wasn't probed for this change; the wording, placement and behavior come from the owner.

## Goals / Non-Goals

**Goals:** Arc's notices in the popup, Chromium's exclusive-access bookkeeping unchanged, and Chromium's press-and-hold Esc for window full screen working from anywhere in the window.

**Non-Goals:**
- A cursor a page hides with CSS (`cursor: none`): Esc can't bring it back, and Chromium shows nothing for it.
- Arc's two-step Esc for a page that is in full screen and locks the pointer (the first Esc unlocks, a second exits).
- Changing the popup's look or place, or zoom controls in the popup.
- Chromium's full-screen exit "X" button, which belongs to its own window.

## Decisions

### D1. The engine writes the pointer-lock text

In `UpdateExclusiveAccessBubble`, a `POINTERLOCK_EXIT_INSTRUCTION` without a download sends "Your cursor is hidden. Press |esc| to show cursor." to `showExclusiveAccessNotice:` in place of Chromium's text. Every other type keeps Chromium's text. Its accessibility label reads "Your cursor is hidden. Press esc to show cursor."

**Alternatives:** matching Chromium's text in `ClairUI` (ties it to Chromium's string, which changes with the locale and versions); a contract method for the notice's kind (a contract change for one string); a patch to `IDS_PRESS_TO_EXIT_MOUSELOCK` (a Chromium file for text Clair's own overlay already chooses).

### D2. Every notice's key reads "esc"

Lowercase, as in Arc's wording and its tooltips ("Stop loading this page esc"). The engine passes `u"esc"`, not `u"Esc"`, as the accelerator, so every Chromium text, full screen, keyboard lock's press and hold and the download variants, carries `|esc|`. `NoticePopupView.markingKeys`, which turns a bare "Esc" into a key for texts without markers, writes `|esc|` too.

**Alternative:** lowercase the label in `KeyCap`: it would also change the keys tooltips show, which follow the menus' glyphs.

### D3. The window's full screen shows its notice

`UpdateExclusiveAccessBubble` stops hiding the browser and extension full-screen types and shows them like the others, so every route into window full screen shows "Press and hold |esc| to exit full screen" for 3.8 s, the text following Chromium's feature. `HideNotice` on leaving full screen already covers them.

Holding Esc must work wherever the focus is, but the page's path already feeds Chromium. So in window full screen, `HandleExclusiveAccessKey` passes unmodified Esc key-downs and key-ups to `ExclusiveAccessManager::HandleUserKeyEvent` only when the window's first responder isn't the page's view, and always returns false there, so the key goes on to the command bar, find, a sheet or the sidebar as before. While a page is in full screen, it keeps today's behavior.

**Alternatives:** feed every Esc from `sendEvent:` (the page's would reach Chromium twice, and a second key-up after the timer was cancelled reaches the controllers as a press); a tap-to-exit Esc (the owner chose Chromium's hold, so a quick Esc still closes things).

### D4. The zoom level goes to the popup through the contract

A new `ClairWindow` method, `- (void)showZoomLevel:(NSInteger)percent`, replaces the toast in `ZoomChanged`. `ClairUI` shows `Notice(text: "\(percent)%", identifier: "clair.zoomNotice")` in the popup for `NoticeState.copiedDuration` (5 s). `NoticeState.show` already replaces a showing notice's text in place and restarts its time, so repeated zooms update one popup. A zoom replaces an exclusive-access notice that's up, as Copy URL does; a later exclusive-access notice replaces the zoom one.

The engine sends the number and `ClairUI` formats it, so the text has no Chromium string and no locale-dependent format in it.

**Alternatives:** formatting "110%" in the engine and reusing `showExclusiveAccessNotice:` (that call keeps its notice until nil, and its hide would take a zoom notice with it); a generic `showNotice:` (no other caller yet).

### D5. Esc ends a pointer lock through Chromium

Esc outside full screen reaches `ExclusiveAccessManager` through the page's keyboard pre-handling, which unlocks the pointer and sends `EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE`, hiding the popup. The runtime test checks it.

## Risks / Trade-offs

- [Esc doesn't end a pointer lock in Clair's native window] → The runtime test reads `document.pointerLockElement` after Esc. If it fails, D3's routing also covers a pointer lock.
- [The full-screen notice now shows on every entry, including a window restored in full screen at launch] → That is Arc's behavior as the owner describes it.
- [Pointer lock needs a user gesture and the window's focus on the runner] → The test asks for the lock through the harness's `Runtime.evaluate`, which passes `userGesture: true`, after bringing the window forward.
- [The zoom notice's 5 s is a guess, since Arc wasn't measured] → It's one constant; adjust it once measured.
- [The popup's identifier for exclusive-access notices stays `clair.fullscreenNotice`] → Not shown to anyone; tests tell the notices apart by label.
- [The engine key and the contract change] → One engine build before merging, with `ClairUI` updated in the same PR.

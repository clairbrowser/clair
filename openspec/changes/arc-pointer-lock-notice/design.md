# Design

## Context

See proposal.md for why and `specs/browser-window/spec.md` for the behavior.

**What Clair does today:** `ClairExclusiveAccessContext::UpdateExclusiveAccessBubble` (`engine/overlay/chrome/browser/clair/window/clair_browser_window.mm`) turns every exclusive-access bubble into text with Chromium's `exclusive_access_bubble::GetInstructionTextForType` and sends it to `showExclusiveAccessNotice:`. `ClairUI` shows that in the top-trailing popup (`NoticeState`, identifier `clair.fullscreenNotice`; `replace-browser-window` design D18), drawing each `|key|` as a `KeyCap`. A timer of `ExclusiveAccessBubble::kShowTime` (3.8 s) hides it and runs Chromium's first-hide callback, and the end of the lock hides it at once.

**What Chromium sends for a pointer lock:** `EXCLUSIVE_ACCESS_BUBBLE_TYPE_POINTERLOCK_EXIT_INSTRUCTION` outside full screen ("Press |Esc| to show your cursor") and `EXCLUSIVE_ACCESS_BUBBLE_TYPE_FULLSCREEN_POINTERLOCK_EXIT_INSTRUCTION` in tab full screen, whose text is the full-screen one. When the lock ends, it sends `EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE`.

Arc wasn't probed for this change, at the owner's request; the wording and the popup come from the owner.

## Goals / Non-Goals

**Goals:** Arc's wording for a pointer lock outside full screen, in the popup that already shows it, with Chromium's exclusive-access bookkeeping unchanged.

**Non-Goals:**
- A cursor a page hides with CSS (`cursor: none`): Esc can't bring it back, Chromium shows nothing for it, and the page keeps the cursor only while it's over the page.
- Changing the popup's look, place or timing, or the full-screen notice's wording beyond its key's label.
- Keyboard lock, which only happens in full screen and keeps its notice.

## Decisions

### D1. The engine writes Arc's text

In `UpdateExclusiveAccessBubble`, a `POINTERLOCK_EXIT_INSTRUCTION` without a download sends "Your cursor is hidden. Press |esc| to show cursor." to `showExclusiveAccessNotice:` in place of Chromium's text. Every other type, including the full-screen pointer lock and any bubble with a download, keeps Chromium's text. The popup draws `|esc|` as a key cap labelled "esc", and its accessibility label reads "Your cursor is hidden. Press esc to show cursor."

**Alternatives:**
- *Match Chromium's text in `ClairUI`* and swap it there: fragile, since it ties `ClairUI` to Chromium's string, which changes with the locale and with versions.
- *A new `ClairHost.h` method for the notice's kind*, with the text in `ClairUI`: a contract change for one string.
- *A patch to Chromium's `IDS_PRESS_TO_EXIT_MOUSELOCK`:* it changes a Chromium file for text Clair's own overlay already chooses.

### D2. Every notice's key reads "esc"

Lowercase, as in Arc's wording and its tooltips ("Stop loading this page esc"). The engine passes `u"esc"`, not `u"Esc"`, as the accelerator to `GetInstructionTextForType`, so Chromium's texts, the full-screen notice, keyboard lock's "press and hold" and the download variants, all carry `|esc|`. `NoticePopupView.markingKeys`, which turns a bare "Esc" into a key for texts without markers, writes `|esc|` as well, so no path draws "Esc". The full-screen notice's accessibility label becomes "To exit full screen, press esc".

**Alternative:** lowercase the label in `KeyCap` or the popup: it would also lowercase the keys a tooltip shows, which follow the menu's glyphs.

### D3. Esc is Chromium's

Esc outside full screen reaches Chromium's `ExclusiveAccessManager` through the page's keyboard pre-handling, which ends the lock and sends `EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE`, hiding the popup. `ClairBrowserWindow::HandleExclusiveAccessKey` only steps in during page full screen. The runtime test checks that Esc ends the lock.

## Risks / Trade-offs

- [Esc doesn't end the lock in Clair's native window] → The runtime test presses Esc and reads `document.pointerLockElement`. If that fails, route Esc to `ExclusiveAccessManager::HandleUserKeyEvent` while the pointer is locked, as `HandleExclusiveAccessKey` does in page full screen.
- [Pointer lock needs a user gesture and the window's focus on the runner] → The test asks for the lock through the harness's `Runtime.evaluate`, which passes `userGesture: true`, after bringing the window forward.
- [The popup's identifier is `clair.fullscreenNotice`, though it now also shows the pointer-lock notice] → It's an identifier, not shown to anyone; tests tell the two notices apart by their label.
- [The engine key changes] → One engine build before merging.

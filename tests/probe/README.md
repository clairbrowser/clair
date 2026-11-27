# The probe: driving Arc and Clair side by side

These tools compare Clair with Arc, and check UI changes by hand, from scripts:
an XCUITest **probe** that clicks, hovers and types in either app, a test copy
of Clair, a page server, screen recordings at 60 fps, and pixel measurements
of screenshots and frames. Synthetic mouse events don't work, since Arc
ignores them; XCUITest's do.

Everything they make goes to `build/probe/` (ignored by git). Never commit
screenshots or recordings.

**Run them as they are, from bash.** The scripts are bash 3.2. Don't inline
their loops in zsh (the agent's shell): zsh doesn't word-split `$var`, so a
loop over `"name 10 20"` passes one argument, and the probe gets a command
without its coordinates.

## One-time setup

- **Automation mode.** XCUITest needs it. If `probe.sh start` says macOS
  refused UI testing ("Timed out while enabling automation mode"), the owner
  runs, once:

  ```
  sudo automationmodetool enable-automationmode-without-authentication
  ```

  `automationmodetool` with no arguments shows the setting.
- **Permission prompts.** The first probe run, and the first debugger attach,
  each show a macOS prompt on the owner's screen. A run that hangs is waiting
  for one: ask the owner to approve it. Never kill an attached `lldb`: that
  kills the app.
- **The engine.** `launch-clair.sh` packages with `scripts/run-local.sh`, so
  the engine for the checkout's key must be published.

## Quick start

```
tests/probe/serve.sh start                         # pages on http://localhost:8765/
tests/probe/launch-clair.sh http://localhost:8765/colour.html
tests/probe/probe.sh start com.clairbrowser.clair    # or no argument for Arc
tests/probe/probe.sh send "click 496 332 shift" "sleep 1.5" "key escape"
tests/probe/probe.sh stop
tests/probe/serve.sh stop
```

- `launch-clair.sh [--port <n>] [--flag <switch>]... [--env <NAME=value>]... [url]`
  packages the checkout's ClairUI into `build/probe/clair/` and launches it
  with a fresh throwaway profile and the mock keychain, then prints its
  windows. `--flag` passes a Chromium switch, such as
  `--extension-mime-request-handling=always-prompt-for-install` to let a CRX
  from a local server ask to install. `--env` sets an environment variable in
  Clair, such as `CLAIR_TEST_FEED_URL` for a local appcast
  (`docs/updates.md`). Launching again quits the previous test copy, and the
  probe stops with it: start the probe again.
- `probe.sh start [bundle id]` builds the probe once, starts it, and attaches
  it to the app (Arc, `company.thebrowser.Browser`, by default). For Clair it
  insists that the test copy runs. It also unregisters every other copy of
  Clair from Launch Services (except installed ones in `/Applications`):
  otherwise XCUITest may launch one, such as the runner's
  `build/src/out/Default/Clair.app`, with the owner's real profile, which
  raises a "Clair Safe Storage" keychain prompt.
- `probe.sh send <line>...` runs lines in order and prints their output. It
  fails when a line failed (`error: …`) or the probe stopped.
- `probe.sh status` and `probe.sh stop`.
- `click-element.sh <identifier|title|label> [left|right] [n]` clicks (or
  right-clicks) the first element of that name in the tree that has a size,
  or the nth, such as a list's second row's button, at its centre, so a
  script needn't know where a window opened. An open
  menu's items have a size; the menu bar's closed ones don't.

**When the owner's own Clair is running** (for example a `run-local.sh` build
they're trying), never attach the probe to Clair: with two copies running,
XCUITest may drive theirs, so `probe.sh start com.clairbrowser.clair` refuses.
Drive the test copy over the DevTools protocol instead, which reaches only
that copy: launch it with `launch-clair.sh --port 9333`, then
`build/probe/bin/cdp 9333 <url part> click <x> <y> 8` Shift+clicks at CSS
pixels (x, y), and `cdp` sends any other protocol command. Capture its window
by ID (`screencapture -l`, IDs from `build/probe/bin/windows <pid>`), since
the windows may overlap. The scripts never unregister a running copy from
Launch Services.

## Commands

Coordinates are in points from the top-left corner of the app's main window
(`app.windows.firstMatch`). `tree` prints frames in screen points.

| Command | Does |
|---|---|
| `app <bundle id>` | attach to another app (start it first) |
| `activate` | bring the app forward; this may switch Spaces |
| `click x y [mods]` | click, holding `shift`, `cmd`, `opt`, `ctrl` (comma-separated) |
| `rclick x y`, `hover x y` | right-click, move the pointer |
| `scroll x y dy` | scroll by `dy` |
| `drag x1 y1 x2 y2 [hold]` | press, then drag at a hand's speed and hold before letting go, 0.3 s or `hold` seconds |
| `key <name> [mods]` | a single character, or `return`, `escape`, `tab`, `space`, `delete`, `forwarddelete`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown` |
| `type <text>` | type text |
| `paste <text>` | put text on the pasteboard and press Cmd+V, for emoji, which `type` doesn't type reliably |
| `tree` | the accessibility tree, with identifiers, labels and frames |
| `frame` | the main window's frame |
| `sleep <s>` | wait |
| `menu <title>` | click a menu item; with several of that title, the one in the open menu |
| `quit` | stop the probe |

## Recording and measuring

```
tests/probe/record.sh peek 22,52,1200,1006 4 -- "click 496 332 shift" "sleep 1.2" "key escape"
build/probe/bin/sheet build/probe/rec/peek/sheet.png 6 build/probe/rec/peek/frames/f013*.png
build/probe/bin/measure track build/probe/rec/peek/frames white 0 0 2400 2012 80
```

- `record.sh <name> <x,y,w,h> <seconds> [-- <probe line>...]` records a
  screen rectangle with `screencapture -v -R`, runs the lines 0.8 s in, and
  saves frames every 1/60 s as `build/probe/rec/<name>/frames/f<ms>.png`, at
  2 px per point. Take the rectangle from `build/probe/bin/windows <owner>`
  (Arc, Clair). `measure` works in the image's pixels: halve them for points.
- `tools/` holds small Swift tools, compiled into `build/probe/bin/` on first
  use (or by `tools/build.sh`); each describes its arguments at the top:
  `windows` (window IDs and frames, by app name or process ID), `drag` (a drag
  with real mouse events, in screen points), `mouse` (a real pointer move, double-click or
  click, in screen points), `keys` (real key events with Ctrl and Shift held
  across steps, and screenshots between them), `cdp` (DevTools
  protocol commands for the test copy), `frames` (a movie's frames), `sheet` (a
  labelled contact sheet), `crop` (a pixel rectangle; `sips --cropOffset`
  centres instead), and `measure`:
  - `pixel`, `line` (every pixel along a row or column, for profiles such as a
    shadow's falloff), `bbox`, `runs` on one image;
  - `track` (a bounding box per frame), `lum` (the darkest pixel in a
    rectangle per frame) and `match` (where each frame sits between two
    templates, such as reload and stop) over a recording, printing only
    changes.
- Screenshots: `screencapture -x -R <x,y,w,h>` (2 px per point) or
  `-l <window id>`. An XCUITest window screenshot captures only the web
  content.

### Worked examples

These come from the add-peek change (its design.md has the numbers):

- **Geometry against a coloured page.** `pages/colour.html` is blue with
  yellow links, so a Peek's white page, the washed parent and the window
  background separate cleanly: `measure bbox shot.png blue` gives the parent
  card's edges, `measure track … white … 80` the Peek's (rows with a white
  run of 80 px, 40 pt, or more, which skips the buttons), and `measure bbox … accent`
  a button's glyph.
- **Shadows.** `measure line` along a row through a card, outward from its
  edge, against the washed page further out gives the shadow's darkening per
  pixel; compare both apps' profiles side by side.
- **Animation curves.** Record the open and close, `track` the Peek's height
  per frame, and fit a curve to it.
- **Load timing.** `/slow-links` links to pages the server sends after 200 ms
  to 3 s. Record the toolbar while Shift+clicking one, and `measure match`
  each frame between a reload frame and a stop frame to time the button.
- **Esc cases.** `esc-links.html` opens `esc.html?<case>` (a field, a
  dialog, a cross-origin frame…) from `127.0.0.1`, so its `localhost` frames
  are cross-origin.

## Traps

- **zsh**: see the top. A crashed probe used to leave a stale command file;
  `probe.sh start` clears it.
- **A stray Clair and a keychain prompt**: if one appears, quit that copy and
  Deny the leftover prompt:
  `osascript -e 'tell application "System Events" to tell process "SecurityAgent" to click button "Deny" of window 1'`.
- **The probe stops** when the app it's attached to quits or relaunches, or
  when macOS withdraws UI-testing authorization ("Not authorized for
  performing UI testing actions"). `probe.sh start` again.
- **Spaces**: `activate` can switch to the app's Space; record only after it
  settles, or the recording shows the owner's other windows. Record with
  `-R`: `screencapture -v -l` adds the window's shadow and scales the frame.
- **Arc's windows**: the owner's blank test window is a
  `standaloneBrowserWindow`. Shift+click inside a Peek there opens the link as
  a tab in the owner's main window (their Personal space): close it there
  afterwards. Cmd+W on a blank window's last tab closes the window. A drag
  that misses Arc's sidebar edge moves the window.
- **Arc's Developer Mode**: with Arc's toolbar on (⇧⌘D), `localhost`
  pages, so `serve.sh`'s, show Arc's striped Developer Mode toolbar, with
  the full URL and developer tools, in place of the normal one. To compare
  with Arc's normal toolbar, use a public site.
- **Cmd+T in Dia**: the new tab doesn't take Cmd+L, so a following
  `key l cmd` and `type` load the URL in the tab that was showing, which
  may be the owner's. Then a closing Cmd+W closes that tab, not yours.
  Check which tab is selected in a screenshot before navigating or closing.
- **Drags in Clair and Arc**: Arc takes real mouse drags from `build/probe/bin/drag`
  (a tab dragged onto the page, into a folder), but the probe's `drag`
  doesn't start one there. On the owner's Mac the probe's `drag` reaches Clair
  with no events at all, though `click` and `hover` do, so it moves nothing
  there. Drag with the mouse's own events instead:
  `build/probe/bin/drag x1 y1 x2 y2`, in screen points, after `activate`.
  More points after the first two make it pass through each, so a drag can go
  somewhere and back, and an odd last number is how long it holds before
  letting go (0.3 s by default): with `drag … 2` in the background, a
  `screencapture -C` 1.5 s later shows the drag in progress, pointer
  included. It moves the real pointer and needs the shell to have permission
  to post events. The XCUITest runner has no such permission, so the probe
  can't do this itself.
- **Never toggle the sidebar** from the probe: a new Clair window opens with
  the last chosen state, and the owner often sets the window up. Look at a
  screenshot first.
- **A full-screen sidebar** stays in its darker material while the probe
  drives Clair, so hover flicker doesn't show; reproduce pointer bugs with
  real `CGEvent` mouse moves instead.
- **Clair's green button** is `XCUIIdentifierFullScreenWindow` in the tree,
  not `ZoomWindow`.
- **A dialog becomes the main window.** While a page's alert or another
  Views dialog shows, `app.windows.firstMatch` is that dialog, so the probe's
  coordinates (and `click-element.sh`'s) start at its corner, and its `hover`
  doesn't bring up a sidebar row's close button. Use `build/probe/bin/mouse
  move|click x y` in screen points instead.
- **Held modifiers**: the probe's `key` releases its modifiers after each key,
  so it can't hold Ctrl across Tabs for the tab switcher. Use
  `build/probe/bin/keys` after `activate`, for example
  `keys ctrldown tab sleep:0.5 shot:build/probe/s.png:0,30,963,976 tab ctrlup`:
  `shot:` captures a screen rectangle in points while Ctrl is still held, and
  the tool lets go of Ctrl and Shift at the end. Arc takes these events.
- **Read a frame before clicking**: a button can disappear after the click,
  failing a later query.
- **The emoji picker takes typing.** A field that opens macOS's emoji picker,
  such as a Space's icon field, loses keys to it while it's open, as its
  search field: `type`, `paste` and Return go to the picker. Send
  `key escape` once to close it; the field keeps editing.
- **The probe shares Clair's defaults**: the test copy uses the bundle ID's
  user defaults domain (sidebar width and state), as an installed Clair does.

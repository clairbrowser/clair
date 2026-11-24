# Section 01: contract and window core

## What this section is

The seam between Chromium and `ClairUI`. `native/ClairHost.h` is the contract: Chromium loads the `ClairUI` framework at start-up and the two sides talk only through it. The overlay files under `engine/overlay/chrome/browser/clair/window/` replace Chromium's browser window with a native one and bridge browser state to Swift; `BrowserWindowController` and `BrowserWindowModel` are the Swift side. `native-window-hook.patch` is the largest patch Clair carries, and it decides where Chromium hands control over.

Everything else in the app sits on this seam, so a weakness here is inherited by every feature. This is also the section where C++, Objective-C++ and Swift object lifetimes meet, which is where memory-safety bugs in a browser shell tend to live.

## Specs to judge against

`openspec/specs/browser-window`, `native-layer`, `chromium-engine`, and `docs/native-window.md`.

## Where to look in the engine tree

Start from the files `native-window-hook.patch` and `native-layer-hook.patch` touch, and from the includes of `clair_browser_window.mm`. Expect to need `chrome/browser/ui/` (the `Browser`, `BrowserWindow` and tab strip model interfaces), `chrome/browser/ui/views/frame/`, `chrome/browser/ui/cocoa/`, `components/constrained_window/` and `ui/views/cocoa/`.

## What to establish

**Lifetimes and threading**
- For each object that crosses the contract, who owns it and what guarantees it outlives its users? Look for raw pointers and unretained references to `Browser`, `WebContents`, tab and profile objects held by Objective-C or Swift objects, and for observers that are not removed.
- What happens to each bridge and observer when a window closes, a tab is discarded or moved to another window, a profile is destroyed, or the app quits with work in flight?
- Is every entry from Swift into Chromium on the UI thread, and does anything re-enter Chromium from inside a Chromium callback in a way the callee does not allow?

**What a compromised renderer can reach**
- The native window implements `WebContentsDelegate`, `WebContentsObserver` and `BrowserWindow` methods that Chromium calls on a renderer's request: opening and adding contents, resizing and moving, full screen, focus, pointer lock, drag and drop, context menus, title and favicon updates. List the ones Clair implements itself. For each, which arguments does the renderer choose, and what does Clair do with them before Chromium's own checks have run, or in place of them?
- Follow each such call into Swift. Does a value a renderer chose (a rectangle, a string, a URL, a count) reach AppKit or an array index unchecked? Can a renderer call often enough, or in an order, that the bridge does not expect?
- The contract's objects (`ClairTab`, `ClairBrowser`, `ClairWindow` and the rest) wrap Chromium objects whose lifetime a renderer can end at a moment of its choosing, by closing a tab, crashing or navigating. What does each wrapper do when Swift calls it afterwards, what does an identifier resolve to once its tab or Space is gone, and can a completion block or a weakly held delegate be called into after the window behind it has closed?

**The contract**
- Is `ClairHost.h` a coherent interface, or a list of calls that grew one feature at a time? Where does it expose Chromium's shape instead of Clair's concepts?
- What does each side assume about the other that the header does not state: call order, nullability, which calls are valid before the window exists or after it closes?
- How is a contract mismatch between an engine and a `ClairUI` build detected? The two are built separately and the engine is cached by key.

**Replacing the window**
- `BrowserWindow` is a wide interface. Which methods does Clair's window implement as no-ops or stubs, and which of those does Chromium rely on for security UI: permission prompts, full-screen and pointer-lock notices, download warnings, certificate interstitials, HTTP auth, external-protocol prompts?
- Does anything web content can trigger assume a Chromium view that no longer exists?

**Structure**
- `clair_browser_window.mm` is about 2,800 lines. What are its responsibilities, and which would be safer or clearer as separate objects?
- Is state held once, or duplicated between the C++ window, the bridge and the Swift model with a risk of the copies disagreeing?

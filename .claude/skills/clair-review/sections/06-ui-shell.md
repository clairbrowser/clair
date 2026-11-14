# Section 06: the rest of ClairUI and its unit tests

## What this section is

The parts of the Swift framework that no feature section owns: the root view and page card that compose the window (`BrowserRootView`, `PageCardView`, `OverlayViews`), the Settings window, and the shared pieces every feature uses (`Tooltip`, `IconButton`, `LoadingIndicator`, `SpringValue`, `AnchorResolver`, layout and title-bar helpers). It also owns the whole unit test target, `native/ClairUITests`, including the `FakeBrowser` and `FakeHost` doubles that every feature's tests are written against.

This section is about how the framework is put together and whether it will stay workable as it doubles in size. Security matters less here than structure, though anything you notice belongs in the report.

## Specs to judge against

`openspec/specs/settings-window`, `browser-window` (layout and chrome) and `sidebar` where the shared views implement it. You may read any other file in `native/ClairUI` to understand how the shared pieces are used; your findings should concern the files in your list.

## Where to look in the engine tree

Rarely needed. `native/ClairHost.h` in the repository is the boundary that matters.

## What to establish

**Architecture**
- Draw the framework's shape: which types hold state, which views observe which models, and how a change in Chromium reaches the screen. Is there one pattern, or several that grew side by side?
- Where does state live in views that should live in a model, and where is the same fact held in two places?
- Is AppKit and SwiftUI mixed along a clear line, or case by case? Which crossings are fragile (first responder, window ordering, layout feedback loops, hosting views inside layer-backed views)?
- What runs on the main actor by declaration and what only by habit? Look for callbacks from Chromium that touch UI state without a stated isolation.
- Which shared pieces have grown feature-specific branches?

**Quality**
- Large views first: what are the responsibilities of `BrowserRootView` and `PageCardView`, and where would you split them?
- Animation and timing code (`SpringValue`, `LoadingIndicator`, overlay transitions): what is driven by timers or delays that could instead follow state, and what leaks or keeps running when its window closes?
- Dead code, duplicated helpers, and names that no longer describe what the thing does.
- Accessibility: the runtime suite drives the app through the accessibility tree, and a hidden view has broken it before. Are identifiers and labels applied consistently?

**The unit tests**
- `FakeBrowser.swift` is over 1,100 lines. Does it model the host faithfully, or has it become a second implementation whose behaviour can drift from the real one? What real behaviour can the fakes not express?
- Which tests check behaviour and which only restate the implementation? Which would still pass if the feature were broken?
- What is covered here that the runtime suite in `tests/runtime` covers again, and which runtime tests could move down to this level because the fakes could express them? Section 07 owns the runtime suite; report what you see from this side.
- Which files in `native/ClairUI` have little or no test coverage, judged by what the tests reference?

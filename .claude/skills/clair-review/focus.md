# Focus for this run

Edit this file before each review run. It holds what is specific to the moment; the section briefs hold what is always worth checking.

## Where Clair stands

- Clair has not been released. Nobody has data to migrate, so stored formats and the `ClairHost.h` contract may change freely. Do not recommend migrations or compatibility shims.
- Profiles, pinned tabs and favourites, and link rules have been reviewed once (the run of 2026-11-20). Each Space uses one Chromium profile and several Spaces can share one; a window switches between Spaces of different profiles in place, by holding one hidden Chromium browser window for each extra profile. Pins live in Local State (`clair.pins`). Link rules route only links handed over by macOS to a Space, possibly in another profile.
- Three features landed after that run, and no review has seen them:
  - **Update banners** (archived changes `add-update-banners` and `follow-chromium-restart-check`). `UpdateController` owns one `UpdateBannerState` that every window's sidebar shows: a "New Clair Version Available" pill that grows into a Restart and Update card, and "Update Complete!" after an update. An idle install now follows Chromium's restart check. Check what Restart and Update does to unsaved page state and other profiles' hidden windows, and whether anything a page controls can trigger or suppress a banner.
  - **The page toolbar** (archived change `add-page-toolbar`). `ClairShowsToolbar`, on by default, puts back, forward, reload, the host, pinned extensions and site controls in a toolbar inside the top of the page card instead of the sidebar. `BrowserWindowModel` decides where the controls show (`showsPageHeader`, `sidebarShowsControls`), and popups anchor to whichever controls are on screen. Check that the host it shows can't be spoofed (long subdomains, IDN, `data:` and `blob:` URLs, a Peek's page) and that anchored popups and permission prompts still point at the right page when the toolbar or the page moves.
  - **The Bookmarks menu** (archived change `add-bookmarks-menu`, `clair/bookmarks-menu-root.patch`). Chromium's Bookmarks menu lists Other Bookmarks directly; a Clair dialog adds, edits and removes a page's bookmark through new `ClairHost.h` calls (`clair_bookmarks.mm`); `ClairBookmarkBarDrain`, one per profile, moves anything that lands in the Bookmarks Bar to Other Bookmarks; and the command bar offers bookmarks again, through Chromium's unmasked `DefaultOmniboxProviders()`. Incognito and guest windows use their original profile's bookmarks. Check what the drain can be made to do by an extension or a policy-managed folder, whether a bookmark ID from Swift can reach a node it shouldn't (managed, mobile, another profile's), and what the re-enabled omnibox providers expose to pages or extensions.
- Arc stops working on 2026-12-22, which is why the remaining features are being built quickly.

## Two features come next

Neither has a change yet. Both are on the MVP list in the archived `ship-plain-ungoogled-build` proposal. Answer these in the "Forward look" part of your report where they touch your section. The aim is to learn, before the features are designed, what the current code makes easy and what it makes hard.

**Split view.** Two pages side by side in one window's card, each with its own page header, as Arc's split view. `add-page-toolbar` built the toolbar as a page header that split view can reuse per pane, and made `BrowserWindowModel` the one place that decides which header shows.

- How much of the window assumes one page view: the card, the still, find, infobars, DevTools, the drag strip, Peeks, full screen, focus and the command bar's target? Which of these would need a pane rather than a window?
- How would two panes map onto Chromium's tab strip and `TabStripModel` (one tab each, or Chromium's own split tabs), and what does that mean for session restore, shared tabs across windows, pins and Spaces in other profiles?
- Can both panes come from different profiles, and if not, what stops it?

**Sidebar folders.** Folders of tabs in the sidebar, as Arc's, nestable and collapsible, holding pinned tabs as well as Today tabs.

- Where does the sidebar's row model live, and how would a tree of rows fit it, its drag and drop, its keyboard commands and its restore?
- How do folders relate to pins (`clair.pins`), which are saved whether or not a page is open, and to Spaces shared between profiles? Where would folders be stored, and what is worth deciding before the first release fixes that format?

## The freeze list

For anything in your section that becomes expensive to change after the first release (stored data formats, key material, identifiers, entitlements, on-disk layout), say whether it is in a state worth keeping.

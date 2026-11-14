# Section 02: Spaces, profiles, sessions and the sidebar

## What this section is

Clair's own data model. A Space is a named set of tabs; each Space uses one Chromium profile and several Spaces can share one. `clair_space_store` persists Spaces, `clair_space_tabs` keeps each Space's tab list (shared across windows), `clair_profiles` manages profiles, `clair_window_group` lets one visible window stand in front of a hidden Chromium browser window per extra profile, and `clair_space_session` ties tabs to Spaces across a relaunch. The Swift files show and edit all of it, with the sidebar as the main view.

This is the newest and fastest-changing code in the app, it holds the only data format Clair defines itself, and both upcoming features land here. Profile isolation is also the security boundary users will rely on most directly.

## Specs to judge against

`openspec/specs/spaces`, `profiles`, `sidebar`, `browser-window` (the parts on restoring windows) and `app-identity` (data paths and the keychain item).

## Where to look in the engine tree

Start from the files the session, data-path and keychain patches touch. Expect to need `chrome/browser/profiles/`, `chrome/browser/sessions/` and `components/sessions/`, `chrome/browser/ui/tabs/` and the tab strip model, `chrome/common/chrome_paths*` and `components/os_crypt/`.

## What to establish

**Profile isolation**
- State the guarantee precisely: what is kept apart between two profiles, and what is shared by design?
- Find every place a tab, a URL, a `WebContents` or a navigation moves between Spaces. When the Spaces use different profiles, is a new `WebContents` created in the target profile, or can one built for profile A end up shown in, or attached to, profile B? What carries over: opener, referrer, session storage, history entries?
- The hidden browser windows of a window group are real Chromium windows. What can reach them: extensions through `chrome.windows` and `chrome.tabs`, session restore, window-management shortcuts, AppleScript or accessibility, the Dock? Can one be surfaced, focused or closed in a way that breaks the group?
- How do incognito windows fit? Can a Space or a window group ever hold an off-the-record profile, and does anything written to the Space store reveal incognito activity?
- When a profile is removed, what still refers to it?

**The data model and its storage**
- Where is each piece of state stored (a preferences file, profile prefs, session tags), and what is the source of truth when they disagree after a crash or a partial write?
- How does the code treat a store it cannot parse, a Space that names a missing profile, duplicate identifiers, or a tab tagged for a Space that no longer exists? Unreleased does not mean the file is always well formed.
- Is the format versioned, and is it shaped around what Clair needs or around what was easy to serialize?

**Sessions and restore**
- Follow a relaunch end to end with restoring on and off. Can tabs come back in the wrong Space, the wrong profile or twice?
- `space-session.patch` changes Chromium's session code. Is the change minimal, and what happens to a session file written without it?

**Structure**
- `clair_space_tabs.mm` is about 1,500 lines and tab lists are shared across windows. Who owns a Space's tab list, and how many other objects keep their own view of it?
- `SidebarView.swift` is about 1,300 lines. Separate what is layout from what is model logic that ended up in a view.

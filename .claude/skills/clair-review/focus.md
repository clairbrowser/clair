# Focus for this run

Edit this file before each review run. It holds what is specific to the moment; the section briefs hold what is always worth checking.

## Where Clair stands

- Clair has not been released. Nobody has data to migrate, so stored formats and the `ClairHost.h` contract may change freely. Do not recommend migrations or compatibility shims.
- Profiles have just landed. Each Space uses one Chromium profile and several Spaces can share one. A window switches between Spaces of different profiles in place, by holding one hidden Chromium browser window for each extra profile.
- Arc stops working on 2026-12-22, which is why the remaining features are being built quickly.

## Two features come next

Answer these in the "Forward look" part of your report where they touch your section. The aim is to learn, before either feature is designed, what the current code makes easy and what it makes hard.

**Link rules.** Rules that send a link to a particular Space or profile by matching its URL, in the manner of Arc's Air Traffic Control and Dia's link rules. A rule deliberately moves a navigation from one profile into another.

- Where can a navigation be intercepted and re-routed today, and which of those points see links opened from other apps, from page content and from the command bar?
- What does profile isolation actually guarantee now? Write the guarantees down, because link rules will be designed against them.
- What would a rule be able to leak across a profile boundary: the URL itself, a referrer, an opener relationship, a session?

**Pinned favourites and pinned tabs.** Favourites shown in every Space of a profile, and tabs pinned within a Space, both of which survive restarts.

- What should the Space store and the tab model look like to hold them? Propose the shape you would want, breaking changes included.
- Is there one owner for "the tabs of a Space", or would pinned items add another?
- Which parts of the sidebar and session-restore code assume every tab is an ordinary open tab?

## The freeze list

For anything in your section that becomes expensive to change after the first release (stored data formats, key material, identifiers, entitlements, on-disk layout), say whether it is in a state worth keeping.

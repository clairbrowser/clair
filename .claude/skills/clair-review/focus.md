# Focus for this run

Edit this file before each review run. It holds what is specific to the moment; the section briefs hold what is always worth checking.

## Where Clair stands

- Clair has not been released. Nobody has data to migrate, so stored formats and the `ClairHost.h` contract may change freely. Do not recommend migrations or compatibility shims.
- Profiles landed recently. Each Space uses one Chromium profile and several Spaces can share one. A window switches between Spaces of different profiles in place, by holding one hidden Chromium browser window for each extra profile.
- Pinned tabs and favourites have just landed, and no review has seen them. A pin is a saved item in Local State (`clair.pins`) that stays whether or not a page is open: a pinned tab belongs to a Space, a favourite to a profile and shows in every Space of it. A link to another site clicked in a pinned tab opens in a peek, through a navigation throttle. Session restore now always runs. The decisions are in the archived change `add-pinned-tabs-and-favorites`.
- Arc stops working on 2026-12-22, which is why the remaining features are being built quickly.

## One feature comes next

Answer these in the "Forward look" part of your report where they touch your section. The aim is to learn, before the feature is designed, what the current code makes easy and what it makes hard.

**Link rules.** Rules that send a link to a particular Space or profile by matching its URL, in the manner of Arc's Air Traffic Control and Dia's link rules. A rule deliberately moves a navigation from one profile into another.

- Where can a navigation be intercepted and re-routed today, and which of those points see links opened from other apps, from page content and from the command bar?
- What does profile isolation actually guarantee now? Write the guarantees down, because link rules will be designed against them.
- What would a rule be able to leak across a profile boundary: the URL itself, a referrer, an opener relationship, a session?
- A pinned tab already re-routes links to other sites into a peek. When a link rule and a pin both claim a navigation, which code would decide, and is there one place where that decision could live?

## The freeze list

For anything in your section that becomes expensive to change after the first release (stored data formats, key material, identifiers, entitlements, on-disk layout), say whether it is in a state worth keeping.

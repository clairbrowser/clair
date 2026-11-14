# Spec Delta

## MODIFIED Requirements

### Requirement: No bookmarks in the interface
Clair SHALL NOT show bookmarks in its interface: there SHALL be no Bookmarks menu, bookmarks bar, bookmark star or bookmark bubble, and their shortcuts Shift+Cmd+B and Opt+Cmd+B SHALL do nothing. Cmd+D SHALL pin or unpin the tab (`pinned-tabs`), as in Arc. Bookmarks already in the profile SHALL be kept, and `chrome://bookmarks` SHALL still open when typed in the command bar.

#### Scenario: Menu bar
- **WHEN** the user looks through the menu bar
- **THEN** there is no Bookmarks menu, and the View menu has no "Always Show Bookmarks Bar" item

#### Scenario: Bookmark shortcut
- **WHEN** the user presses Cmd+D on a Today tab
- **THEN** the tab is pinned, and no bookmark is created

### Requirement: Tabs restored at launch
When Clair launches, it SHALL reopen the tabs that were open when it quit, as Arc does, unless the user chose otherwise in Chromium's "On startup" setting. This SHALL hold for a new profile without any setting being changed. Incognito tabs SHALL NOT come back. Pinned tabs and favorites SHALL come back whatever the setting (`pinned-tabs`); the setting decides only whether their pages reopen.

#### Scenario: Quit and relaunch
- **WHEN** a user who never changed a setting quits Clair with several tabs open and launches it again
- **THEN** those tabs are open again

#### Scenario: The user chose a new tab page
- **WHEN** the user set "On startup" to "Open the New Tab page" in `chrome://settings`, quits and relaunches
- **THEN** Clair opens one window on a new tab page

#### Scenario: After a crash
- **WHEN** Clair crashes with tabs open and is launched again
- **THEN** the tabs reopen

#### Scenario: Pins with a new tab page at startup
- **WHEN** the user set "On startup" to "Open the New Tab page", quits with two pinned tabs and a favorite open, and relaunches
- **THEN** the pinned tabs and the favorite are listed, none of them open, and the Today tabs are gone

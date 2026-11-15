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
When Clair launches, it SHALL reopen the tabs that were open when it quit, as Arc does: Today tabs, and pinned tabs and favorites whose pages were open (`pinned-tabs`). They SHALL come back until the user closes them, with no setting to start without them: `chrome://settings` SHALL NOT show Chromium's "On startup" section, and a startup choice an extension or a stored preference makes SHALL be ignored. Incognito tabs SHALL NOT come back.

#### Scenario: Quit and relaunch
- **WHEN** a user who never changed a setting quits Clair with several tabs open and launches it again
- **THEN** those tabs are open again

#### Scenario: No "On startup" section
- **WHEN** the user opens `chrome://settings`
- **THEN** it has no "On startup" section

#### Scenario: The user chose a new tab page
- **WHEN** Chromium's startup preference is stored as "Open the New Tab page", or an extension sets startup pages, and the user quits with tabs open and relaunches
- **THEN** those tabs are open again, and no startup page opens

#### Scenario: After a crash
- **WHEN** Clair crashes with tabs open and is launched again
- **THEN** the tabs reopen

#### Scenario: Open pins
- **WHEN** the user quits with a pinned tab and a favorite open, and relaunches
- **THEN** both are open again, and the pinned tabs and favorites that weren't open are listed, still not open

## MODIFIED Requirements

### Requirement: Tab commands treat a split as one row
The tab commands of `spaces` (Next Tab, Previous Tab, Cmd+1 to Cmd+9, Close Tabs Below, and Ctrl+Shift+PageDown and PageUp) SHALL count a split as one row, and the switcher (`tab-switcher`) SHALL count it as one tab. Selecting it SHALL show the split as clicking its row does.

#### Scenario: Next Tab
- **WHEN** Today lists "Mail", a split, and "Docs", "Mail" is shown, and the user presses Opt+Cmd+Down twice
- **THEN** the window shows the split and then "Docs"

#### Scenario: Ctrl+Tab
- **WHEN** the window showed a split and then "Docs", and the user presses Ctrl+Tab
- **THEN** the window shows the split, with the pane focused last focused

### Requirement: The split row's menu
Right-clicking a split row SHALL open the menu of its kind for the tab whose chip is under the pointer (Today tab menu, `pinned-tabs`, `favorites`), without Back to Pinned URL or Edit Pinned Page ›, and with Separate Tabs in place of Split with Tab ›. Pin Tab, Pin to Favorites, Unpin Tab, Remove Favorite and Move to Space SHALL act on the whole split.

#### Scenario: A Today split's menu
- **WHEN** the user right-clicks the "Docs" chip of a Today split
- **THEN** the menu offers the Today tab menu's items for "Docs", with Separate Tabs where Split with Tab would be

#### Scenario: Copy Link
- **WHEN** the user chooses Copy Link from that menu
- **THEN** the URL of "Docs" is copied

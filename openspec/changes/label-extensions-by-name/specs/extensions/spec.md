## MODIFIED Requirements

### Requirement: Extensions menu
The menu bar SHALL have an Extensions menu just left of Window. It SHALL list every extension with an action in the frontmost browser window's profile, with its icon, by its name as `chrome://extensions` shows it, in alphabetical order of those names, followed by a separator, "Add Extension…" and "Manage Extensions…". The title an extension gives its action SHALL NOT change the menu.

#### Scenario: Listing extensions
- **WHEN** three extensions are installed and the user opens the Extensions menu
- **THEN** it lists the three with their icons from A to Z, then a separator, "Add Extension…" and "Manage Extensions…"

#### Scenario: An extension titles its action
- **WHEN** an extension sets its action's title to text other than its name, such as "Manage Extensions…", and the user opens the Extensions menu
- **THEN** the menu lists that extension by its name, in its name's place in the order

#### Scenario: Managing extensions
- **WHEN** the user chooses "Manage Extensions…"
- **THEN** `chrome://extensions` opens in a new tab

#### Scenario: Adding an extension
- **WHEN** the user chooses "Add Extension…"
- **THEN** the Chrome Web Store opens in a new tab

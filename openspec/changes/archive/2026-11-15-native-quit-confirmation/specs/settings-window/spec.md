# Spec Delta

## MODIFIED Requirements

### Requirement: Warn before quitting toggle
The Advanced page SHALL have a toggle labelled "Warn before quitting" that shows and changes Chromium's warn-before-quitting setting. It SHALL be on when the user never changed it, as in Chromium, and a change SHALL apply at once. While it is on, Cmd+Q and Clair › Quit Clair SHALL ask in a quit dialog laid out as Dia's, and Chromium's "Hold ⌘Q to Quit" panel SHALL NOT show. No other quit SHALL ask. The menu bar SHALL NOT have Chromium's own "Warn Before Quitting" item, which the toggle replaces.

#### Scenario: On
- **WHEN** the toggle is on and the user presses Cmd+Q
- **THEN** Clair shows the quit dialog on the window and keeps running until the user answers

#### Scenario: The quit dialog
- **WHEN** the quit dialog shows
- **THEN** it is on the key browser window, or the most recently active one, with the title "Are you sure you want to quit Clair?", the message "You may lose unsaved work in your tabs.", "Always quit" at the bottom leading corner, and Cancel and a destructive Quit at the trailing corner, as in `native-quit-confirmation`'s `dia-reference/`

#### Scenario: Cancel
- **WHEN** the quit dialog shows and the user presses Esc or clicks Cancel
- **THEN** the dialog closes and Clair keeps running

#### Scenario: Quit
- **WHEN** the quit dialog shows and the user presses Return or clicks Quit
- **THEN** Clair quits

#### Scenario: Always quit
- **WHEN** the quit dialog shows and the user clicks "Always quit"
- **THEN** Clair quits, and after the next launch the toggle is off and Cmd+Q quits at once

#### Scenario: The Quit menu item
- **WHEN** the toggle is on and the user chooses Clair › Quit Clair
- **THEN** Clair shows the quit dialog

#### Scenario: Other quits
- **WHEN** the toggle is on and the user quits from the Dock, logs out, or Clair relaunches for an update, or no browser window is open
- **THEN** Clair quits without the dialog

#### Scenario: A download in progress
- **WHEN** the toggle is on, a download is in progress and the user presses Cmd+Q
- **THEN** only Chromium's warning about the download shows

#### Scenario: Off
- **WHEN** the user turns the toggle off and presses Cmd+Q
- **THEN** Clair quits at once

#### Scenario: Menu bar
- **WHEN** the user opens the Clair menu
- **THEN** it has no "Warn Before Quitting" item

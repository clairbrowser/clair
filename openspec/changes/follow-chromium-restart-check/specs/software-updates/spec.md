## MODIFIED Requirements

### Requirement: Downloaded update installs while the user is idle
While a downloaded update is waiting, Clair SHALL install it and relaunch on its own once the Mac has had no keyboard, mouse or trackpad input for 30 minutes, unless a download is in progress, an incognito, guest or web app window is open, audio is playing, or a page the user has interacted with would ask "Leave site?"; it SHALL then try again at the next idle period. If Clair was not the active app, the relaunched Clair SHALL stay in the background.

#### Scenario: User away with an update ready
- **WHEN** an update is waiting and the Mac has had no input for 30 minutes
- **THEN** Clair installs the update, relaunches with its windows and tabs restored, and runs the new version

#### Scenario: Something would be interrupted
- **WHEN** an update is waiting and the Mac has had no input for 30 minutes, but a download is in progress, an incognito or guest window is open, audio is playing, or a web app window is open
- **THEN** Clair does not install the update, and installs it at a later idle period once none of these holds

#### Scenario: A page would ask before leaving
- **WHEN** an update is waiting, the Mac has had no input for 30 minutes, and a tab shows a page with a "Leave site?" handler that the user has clicked in
- **THEN** Clair does not install the update and shows no "Leave site?" dialog, and installs the update at a later idle period once that tab is closed or has left the page

#### Scenario: Clair in the background
- **WHEN** Clair installs an update while idle and another app was active
- **THEN** the relaunched Clair does not become the active app

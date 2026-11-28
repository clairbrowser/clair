# Spec Delta

## Purpose

Brings a user's Spaces, favorites, pinned and Today tabs, bookmarks, history and extensions from another browser on the same Mac into Clair, through Clair's own import dialog.

## ADDED Requirements

### Requirement: Import menu item
The Clair menu SHALL offer "Import from Another Browser…" after Set as Default Browser. Choosing it SHALL open the import dialog (`dialogs`) on the frontmost browser window, or on a new window when none is open. While the dialog shows on one window, choosing the item again SHALL bring that window forward rather than open a second dialog.

#### Scenario: Opening the dialog
- **WHEN** the user chooses Clair › Import from Another Browser…
- **THEN** the frontmost window dims and shows the import dialog's first step

#### Scenario: No window open
- **WHEN** no browser window is open and the user chooses the item
- **THEN** a window opens and shows the import dialog

#### Scenario: Already showing
- **WHEN** the dialog shows on one window, another window is frontmost, and the user chooses the item
- **THEN** the window with the dialog comes forward, and no second dialog opens

### Requirement: Choosing a browser
The first step SHALL be titled "Import from your old browser", with the message "Import everything you need from your old browser to hit the ground running with Clair.", and SHALL show a card for each source on this Mac, two per row, in the order Safari, Arc, Dia, Chrome, each with the app's icon, its name and a radio button. The first card SHALL be selected. Clicking a card SHALL select it. Its buttons SHALL be Cancel and Continue (`dialogs`, stepped dialogs).

#### Scenario: All present
- **WHEN** Arc, Dia and Chrome have data on this Mac and the user opens the dialog
- **THEN** it shows Safari and Arc in the first row and Dia and Chrome in the second, with Safari selected

#### Scenario: Continue
- **WHEN** the user selects Arc and presses Return
- **THEN** the dialog shows Arc's second step

### Requirement: Which sources show
Arc SHALL show while its sidebar data is on this Mac, and Dia and Chrome while their profiles are, whether or not the app is installed or running. Safari SHALL always show, since its data comes from a file the user exports. A source with nothing Clair can read SHALL NOT show.

#### Scenario: Arc never used
- **WHEN** Arc is installed but has never been opened, and Dia and Chrome aren't on this Mac
- **THEN** the first step shows Safari alone

#### Scenario: Source running
- **WHEN** Arc is running
- **THEN** Arc's card still shows, and its second step asks to quit Arc ("Quitting the source browser")

### Requirement: What will come over
The second step SHALL be titled "Import from <browser>" and list what that source brings, each with an icon: for Arc and Dia, Spaces, Favorites, Pinned Tabs, Today Tabs, Bookmarks, History and Extensions; for Chrome, Pinned Tabs, Today Tabs, Bookmarks, History and Extensions; for Safari, Bookmarks and History. It SHALL show no counts, and SHALL have no option to leave an item out. Its buttons SHALL be Cancel, Back and Import (`dialogs`, stepped dialogs).

#### Scenario: Safari's list
- **WHEN** the user has chosen Safari's export file
- **THEN** the step lists Bookmarks and History only

#### Scenario: Chrome's list
- **WHEN** the user picks Chrome and continues
- **THEN** the step lists Pinned Tabs, Today Tabs, Bookmarks, History and Extensions, and a row for each Chrome profile

#### Scenario: Back
- **WHEN** the user clicks Back on Arc's second step
- **THEN** the first step shows, with Arc selected

### Requirement: Quitting the source browser
While Arc, Dia or Chrome is running, its second step SHALL say "Quit <browser> to import from it." and its default button SHALL read "Quit <browser>" in place of Import. Clicking it SHALL ask the browser to quit, as its own Quit command would, and once it has quit the button SHALL read Import. If the browser is opened again before Import, the step SHALL ask again.

#### Scenario: Quitting Arc
- **WHEN** Arc is running and the user reaches Arc's second step
- **THEN** it says "Quit Arc to import from it." with a "Quit Arc" button, and clicking it quits Arc and turns the button into Import

#### Scenario: Quit cancelled
- **WHEN** Arc asks to confirm quitting and the user cancels there
- **THEN** Arc keeps running, and the button still reads "Quit Arc"

#### Scenario: Not running
- **WHEN** Chrome isn't running and the user reaches Chrome's second step
- **THEN** the default button reads Import

### Requirement: Choosing destination profiles
The second step SHALL list each profile of the source, by the name the source gives it (for Dia, the names of the Dia profiles that share its data), with an "Import into" popup listing every Clair profile and then "New Profile". The first row SHALL start on the profile of the Space the window shows, and the others on "New Profile". Several rows MAY choose the same profile. Everything from a source profile SHALL go to the profile its row chose.

#### Scenario: Arc with two profiles
- **WHEN** Arc has the profiles "Your Arc" and "Work", the window shows a Space of Clair's "Personal", and the user reaches Arc's second step
- **THEN** "Your Arc" is set to import into "Personal" and "Work" into "New Profile"

#### Scenario: Dia profiles sharing data
- **WHEN** Dia's "Profile 2" and "Profile 3" share one data folder
- **THEN** one row reads "Profile 2, Profile 3"

#### Scenario: Safari
- **WHEN** the user reaches Safari's list
- **THEN** it shows one row, "Safari", set to the profile of the Space the window shows

### Requirement: New profiles from an import
A row set to "New Profile" SHALL create a Clair profile when the import runs, named after the source profile (for Dia, its first Dia profile), with " 2", " 3" and so on added when a profile of that name exists. Its Spaces SHALL be the source profile's. A new profile left with no Space, because its source profile had none, SHALL get one Space named after it.

#### Scenario: Name taken
- **WHEN** Clair has a profile "Work" and the user imports Arc's "Work" into "New Profile"
- **THEN** a profile "Work 2" is created and holds the imported Spaces

#### Scenario: No Spaces
- **WHEN** a source profile with bookmarks and history but no Spaces is imported into "New Profile"
- **THEN** the new profile has one Space named after it, and the bookmarks and history

### Requirement: Dia's privacy note
Dia's second step SHALL say, above the profile list: "Clair reads your Dia data only on this Mac, to import it into Clair. Nothing is sent anywhere. Your Mac will ask to let Clair use “Dia Safe Storage” from your keychain: Clair needs it only to read Dia's tabs." The keychain SHALL be asked only after the user clicks Import.

#### Scenario: Reading Dia's tabs
- **WHEN** the user clicks Import on Dia's second step
- **THEN** macOS asks to let Clair use "Dia Safe Storage", and once allowed, the import runs

#### Scenario: Access denied
- **WHEN** the user denies the keychain request
- **THEN** Dia's bookmarks, history and extensions are still imported, and the summary says that Dia's Spaces, favorites, pinned and Today tabs couldn't be read without that access

### Requirement: Safari's export file
Safari's second step SHALL first explain, as numbered steps, how to export from Safari (open Safari, choose File › Export Browsing Data to File…, export and save the file, then choose it here), with an area to drop the .zip or the folder it unpacks to, and a default button "Choose File…" that opens a file panel. Once a valid file is chosen, the step SHALL show what will come over and the profile row, and its default button SHALL read Import.

#### Scenario: Dropping the file
- **WHEN** the user drops Safari's export .zip on the area
- **THEN** the step lists Bookmarks and History, the "Safari" row, and Import

#### Scenario: Wrong file
- **WHEN** the user chooses a file that isn't a Safari export
- **THEN** the area says the file isn't a Safari export, and the step still asks for one

#### Scenario: Partial export
- **WHEN** the user exported only bookmarks from Safari
- **THEN** the step accepts the file, and the import brings the bookmarks

### Requirement: Importing and its summary
Import SHALL show the import's progress in the dialog, with no buttons, until everything is done, extension installs included, and then a summary titled "Import Complete" with a count of each item imported and a list of what was skipped and why, extensions that failed to install included, with one Done button that Return and Esc choose.

#### Scenario: Summary
- **WHEN** an import from Arc finishes
- **THEN** the dialog shows how many Spaces, favorites, pinned tabs, Today tabs, bookmarks, history entries and extensions came over, and what was skipped

#### Scenario: Unreadable data
- **WHEN** a source's sidebar data can't be read, for example after the source changed its format
- **THEN** everything else is imported, and the summary says which items couldn't be read

### Requirement: Spaces from an import
Each Space of an Arc or Dia profile SHALL come over as a Space of the row's Clair profile, after the existing Spaces, with its name and, from Arc, its emoji icon. Each of Dia's "profiles" SHALL be a Space, and each Chrome profile SHALL be one Space named after it. A Space whose name matches one in that Clair profile SHALL merge into it. Colours and themes SHALL NOT come over.

#### Scenario: Arc Spaces
- **WHEN** Arc's "Your Arc" has the Spaces "Space 1" and "Space 2" with 😀, imported into "Personal"
- **THEN** "Personal" gains "Space 1" and "Space 2" with 😀, after its own Spaces

#### Scenario: Dia profiles sharing data
- **WHEN** Dia's "Profile 2" and "Profile 3" share one data folder, imported into "New Profile"
- **THEN** one new profile holds two Spaces, "Profile 2" and "Profile 3"

#### Scenario: Same name
- **WHEN** "Personal" already has a Space "Space 1" and Arc's "Space 1" is imported into it
- **THEN** no second "Space 1" is made, and Arc's pins and tabs join the existing one

### Requirement: Pinned tabs and folders from an import
A Space's pinned tabs, folders and pinned splits SHALL come over at the end of its pinned section, in the source's order, each pinned tab with its pinned URL, title and custom name, and folders closed. Arc's pinned URL SHALL be the URL Arc keeps for the pin. Since folders hold no folders (`tab-folders`), a nested folder SHALL become a folder named with its path, such as "Parent Folder / Child Folder", right after its parent's. A folder holding only folders SHALL NOT come over itself.

#### Scenario: Nested folder
- **WHEN** Arc's "Space 1" has the folder "Parent Folder" holding a split and the folder "Child Folder" with "RENAMED TAB"
- **THEN** Clair's "Space 1" shows "Parent Folder" holding the split, then "Parent Folder / Child Folder" holding the pinned tab named "RENAMED TAB"

#### Scenario: Deeper nesting
- **WHEN** Dia's group "A" holds only the group "B", which holds "C" with one tab
- **THEN** Clair shows one folder, "A / B / C", holding the tab

### Requirement: Today tabs from an import
A Space's Today tabs from Arc, Dia or Chrome SHALL come over below the Space's existing Today tabs, in the source's order, without loading their pages until selected. Dia's and Chrome's open tabs of every window SHALL come over, window by window.

#### Scenario: Unloaded
- **WHEN** an import brings 20 Today tabs
- **THEN** they show in the sidebar with their titles, and only a selected one loads its page

### Requirement: Chrome's tabs
Chrome's tabs SHALL come from the session Chrome saved last, in each profile's Space: its pinned tabs, of every window, at the end of the pinned section, each pinned at the URL it shows, and its other tabs as Today tabs. Chrome's split tabs SHALL come over as splits (`browser-import`, "Splits from an import"). Chrome's tab groups SHALL NOT come over as groups: their tabs come over in place.

#### Scenario: Chrome's windows
- **WHEN** Chrome's "Person 1" has a window with the pinned tab Gmail and the tabs A and B, and another window with C, imported into "New Profile"
- **THEN** the new profile's Space "Person 1" has Gmail pinned, and A, B and C as Today tabs, in that order

#### Scenario: A Chrome split
- **WHEN** Chrome's window has the tabs Docs and Mail in a split, Docs taking 60% of the width
- **THEN** Clair's Today tabs hold a split of Docs and Mail, Docs leading at 60%

#### Scenario: A tab group
- **WHEN** Chrome's tabs D and E are in the group "Trip"
- **THEN** D and E come over as Today tabs in their place, with no group

### Requirement: Favorites from an import
Arc's and Dia's favorites SHALL be added after the destination profile's own favorites, in the source's order. Dia's favorites of every Space using a profile SHALL go to that profile's favorites, in Space order. A bookmarks bar, Chrome's or Safari's Favorites, SHALL NOT become favorites: it comes over as bookmarks ("Bookmarks from an import").

#### Scenario: Arc favorites
- **WHEN** Arc's "Your Arc" has the favorites example.com and wiktionary.org, imported into "Personal"
- **THEN** "Personal" shows them after its own favorites

#### Scenario: Safari's Favorites bar
- **WHEN** Safari's Favorites hold Apple, then the folder "News"
- **THEN** Clair's favorites don't change, and the Bookmarks menu lists Apple and the "News" folder

### Requirement: Splits from an import
A split of two panes SHALL come over as a Clair split (`split-view`) of the same pages, in pane order and with the source's ratio, as a Today tab, pinned tab or favorite, wherever it was. A split stacked top to bottom SHALL come over side by side. A split of three or more panes SHALL come over as separate tabs, one after another in pane order, in its place.

#### Scenario: Two panes
- **WHEN** Arc's Today section has a split of Hacker News and Engadget at 0.5
- **THEN** Clair's Today tabs hold a split of the same pages, equal width

#### Scenario: Stacked
- **WHEN** Arc has a split of Dog over Cat
- **THEN** Clair shows a split with Dog leading and Cat trailing

#### Scenario: Three panes
- **WHEN** Arc's Today section has a split of Africa, Europe and Asia
- **THEN** Clair's Today tabs hold Africa, Europe and Asia as three tabs, in that order, in the split's place

### Requirement: Bookmarks from an import
A source profile's bookmarks SHALL come over as they are, with no folder added around them, keeping their folders and order: the contents of its bookmarks bar, then its other bookmarks, after what the destination profile's Other Bookmarks already holds, as Clair empties its own Bookmarks Bar (`bookmarks`). None SHALL land in the Bookmarks Bar. Safari's Reading List SHALL NOT come over.

#### Scenario: Arc bookmarks
- **WHEN** Arc's "Work" has "Google" in its bookmarks bar and "Docs" in Other Bookmarks, imported into "Work 2"
- **THEN** "Work 2"'s Bookmarks menu lists "Google" then "Docs", and no Heads Up dialog shows

### Requirement: History from an import
A source profile's history SHALL come over into the destination profile's history, with each page's URL, title, visit count and last visit, so History and the command bar's suggestions offer it. Safari's history SHALL come from its export. Importing the same source profile into the same Clair profile again SHALL add only pages visited since the last such import; a first import of it into another Clair profile, or of another source profile into this one, SHALL bring all its history.

#### Scenario: Importing history again
- **WHEN** the user imports Arc's history, browses in Arc, and imports again
- **THEN** only the pages visited in Arc since the first import gain a visit in Clair

#### Scenario: Another destination
- **WHEN** Arc's "Work" was imported into "Work 2", and the user later imports it into "Personal"
- **THEN** "Personal" gets all of "Work"'s history

#### Scenario: History after import
- **WHEN** the user imports Arc's history and types part of a page's title in the command bar
- **THEN** the command bar suggests that page from history

### Requirement: Extensions from an import
Each extension a source profile installed from the Chrome Web Store SHALL be installed in the destination profile from the Chrome Web Store, without a prompt per extension, keeping whether it was turned on and whether it was pinned. An extension already installed there, one not from the store, a theme or an app SHALL be skipped, and one the store can't provide SHALL be listed in the summary.

#### Scenario: Store extension
- **WHEN** Arc's "Work" has Dark Reader from the store, turned on and pinned, imported into "Work 2"
- **THEN** Dark Reader installs in "Work 2" without asking, turned on and pinned

#### Scenario: Unpacked extension
- **WHEN** a source profile has an extension loaded unpacked
- **THEN** it isn't installed, and the summary lists it as not from the Chrome Web Store

### Requirement: Importing again
Importing from the same source again SHALL NOT duplicate what came over before. A favorite, pinned tab or Today tab whose URL already shows in the same place, the same favorites, Space section or folder, and a bookmark whose URL is already in the same folder SHALL be skipped and counted in the summary as already in Clair. A bookmarks folder whose name matches one in the same place SHALL merge into it.

#### Scenario: Second import
- **WHEN** the user imports from Arc twice into the same profiles
- **THEN** the second import adds nothing that the first brought, and its summary says those items were already in Clair

### Requirement: Import privacy
Apart from finding which sources are on this Mac and their profiles' names, and checking a chosen Safari file, an import SHALL read a source's data only after the user clicks Import, only from this Mac, and SHALL never change the source's files or keychain items. Apart from downloading extensions from the Chrome Web Store, it SHALL send nothing over the network. Temporary copies Clair makes to read a source SHALL be readable by the user alone and deleted when the import ends.

#### Scenario: Before Import
- **WHEN** the user opens the dialog, picks Dia and clicks Back
- **THEN** no keychain request shows, and Clair has read none of Dia's data

#### Scenario: After the import
- **WHEN** an import from Dia ends
- **THEN** Dia's files and its keychain item are unchanged, and no decrypted copy of its data remains

### Requirement: Chromium's import menu item hidden
The Clair menu SHALL NOT show Chromium's "Import Bookmarks and Settings…", so "Import from Another Browser…" is its only import item.

#### Scenario: Clair menu
- **WHEN** the user opens the Clair menu
- **THEN** it shows "Import from Another Browser…" and not "Import Bookmarks and Settings…"

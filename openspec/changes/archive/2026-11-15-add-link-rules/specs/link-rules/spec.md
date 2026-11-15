# Spec Delta

## Purpose
Link rules, as Arc's Air Traffic Control and Dia's Link Rules: which Space opens a link from another app, how a rule matches a link, and the dialog that edits the rules.

## ADDED Requirements

### Requirement: Link rules
Clair SHALL keep an ordered list of link rules, app-wide and across launches. Each rule SHALL have a match option, a text and a destination Space. The match options SHALL be "URLs containing", "this exact URL" and "URLs starting with". No two rules SHALL have the same match option and text.

#### Scenario: Rules kept across launches
- **WHEN** the user saves a rule opening URLs containing `example.com` in a Space named Work, and quits and relaunches Clair
- **THEN** the Link Rules dialog lists that rule

#### Scenario: No rules
- **WHEN** Clair has never stored any rules
- **THEN** the rule list is empty, and every link opens as it would without link rules

### Requirement: Match options
A rule SHALL match a link's URL, ignoring its fragment: "URLs containing" when the URL contains the rule's text, ignoring case; "this exact URL" when the URL equals the text read as a URL; "URLs starting with" when the URL starts with the text read as a URL. Host names SHALL compare without regard to case.

#### Scenario: Containing
- **WHEN** a rule opens URLs containing `meet.google` in Work, and a link to `https://Meet.Google.com/abc-defg-hij` arrives from another app
- **THEN** it opens in Work

#### Scenario: Exact URL
- **WHEN** a rule opens this exact URL `https://example.com/inbox` in Work, and links to `https://example.com/inbox#top` and `https://example.com/inbox/old` arrive from another app
- **THEN** the first opens in Work, and the second matches no rule

#### Scenario: Starting with
- **WHEN** a rule opens URLs starting with `github.com/acme` in Work, and links to `https://github.com/acme/app/pull/1` and `https://gist.github.com/acme` arrive from another app
- **THEN** the first opens in Work, and the second matches no rule

### Requirement: Texts without a scheme
A rule's text without a scheme SHALL be read as an `https` URL, and SHALL match `http` and `https` links alike.

#### Scenario: Either scheme
- **WHEN** a rule opens this exact URL `example.com/inbox` in Work, and links to `http://example.com/inbox` and `https://example.com/inbox` arrive from another app
- **THEN** both open in Work

### Requirement: First matching rule wins
When several rules match a link, the first in the list's order SHALL decide where it opens.

#### Scenario: Two rules match
- **WHEN** the list has, in order, a rule opening URLs containing `docs.google.com` in Work and one opening URLs containing `google.com` in Personal, and a link to `https://docs.google.com/document/d/1` arrives from another app
- **THEN** it opens in Work

### Requirement: Links from other apps are checked
Every `http` or `https` link that macOS hands to Clair from outside it SHALL be checked against the rules: a link clicked in another app while Clair is the default browser, opened with `open`, or handed off from another device, including a link that launches Clair. A link that matches no rule SHALL open as it would without link rules.

#### Scenario: Clair not running
- **WHEN** Clair isn't running and the user clicks a link in another app that a rule matches
- **THEN** Clair launches, and the link opens in the rule's Space

#### Scenario: No rule matches
- **WHEN** a link that matches no rule arrives from another app
- **THEN** it opens where it would without link rules

### Requirement: Where a matched link opens
A matched link SHALL open in a new foreground tab of the rule's Space, in its Space's profile, in the most recently active window that isn't incognito or guest, which switches to that Space. With no such window open, a new window showing that Space SHALL open with the link.

#### Scenario: A matching link from another app
- **WHEN** a window shows the Space Personal, a rule opens URLs containing `example.com` in Work, and the user clicks a link to `https://example.com/` in another app
- **THEN** Clair comes to the front, the window switches to Work, and a new tab showing `https://example.com/` is active in Work

#### Scenario: Work uses another profile
- **WHEN** Work uses the profile Work, a rule opens URLs containing `example.com` in Work, and a matching link arrives from another app
- **THEN** the page opens in the Work profile, signed in as that profile is

#### Scenario: No window open
- **WHEN** no browser window is open and a matching link arrives from another app
- **THEN** a new window opens showing the rule's Space, with the link in a new tab

### Requirement: Links opened inside Clair are not routed
Link rules SHALL NOT apply to links opened from inside Clair: link clicks, the command bar, extensions, Peek, session restore and Reopen Closed Tab.

#### Scenario: Link clicked inside Clair
- **WHEN** a rule opens URLs containing `example.com` in Work, and the user clicks a link to `https://example.com/` in a page shown in Personal
- **THEN** the link opens as it would without link rules, in Personal

### Requirement: Rules follow their Space
Deleting a Space SHALL remove the rules that open links in it, including when the Space goes with its profile. Renaming a Space or changing its profile SHALL keep its rules.

#### Scenario: Deleting a Space
- **WHEN** a rule opens URLs containing `example.com` in Work and the user deletes Work
- **THEN** the rule is gone from the Link Rules dialog, and a link to `https://example.com/` from another app matches no rule

#### Scenario: Renaming a Space
- **WHEN** a rule opens links in Work and the user renames Work to Office
- **THEN** the rule shows Office, and matching links open there

### Requirement: Link Rules dialog
"Link Rules…" (`settings-window`) SHALL open a dialog titled "Link Rules" on the Settings window, laid out as Dia's: a rounded list area with one row per rule in the list's order, separated by hairlines; "Add Rule" at the bottom leading corner; "Cancel" and "Done" at the bottom trailing corner. Edits SHALL take effect only when the user chooses Done.

#### Scenario: Opening with rules
- **WHEN** Clair has two rules and the user chooses "Link Rules…"
- **THEN** the dialog shows both rules in order, with Add Rule, Cancel and Done

### Requirement: Link rule rows
Each row SHALL show the word "Open", a popup of the three match options, a text field with the placeholder `example.com`, the word "in", a popup of Spaces, and an × button labelled "Remove Link Rule" that removes the row. The Spaces popup SHALL show each Space's icon and name, grouped under its profile's name when there's more than one profile. "Add Rule" SHALL append a row matching "URLs containing" with an empty, focused field and the first Space.

#### Scenario: Adding a rule
- **WHEN** the user chooses Add Rule
- **THEN** a row appears at the bottom of the list with "URLs containing", an empty focused field and the first Space

#### Scenario: Removing a rule
- **WHEN** the user clicks a row's × button
- **THEN** the row disappears, and the others keep their order

#### Scenario: Spaces of several profiles
- **WHEN** Clair has Spaces in the profiles Personal and Work, and the user opens a row's Space popup
- **THEN** it lists each profile's name followed by that profile's Spaces, each with its icon and name

### Requirement: Link Rules empty states
With no rows, the list area SHALL show "No link rules yet". With only one Space, "Add Rule" SHALL be disabled, and an empty list area SHALL show "Link rules work with more than one Space. Add another Space to get started." instead.

#### Scenario: No rules
- **WHEN** Clair has two Spaces and no rules, and the user opens the dialog
- **THEN** the list area shows "No link rules yet"

#### Scenario: One Space
- **WHEN** Clair has one Space and no rules, and the user opens the dialog
- **THEN** the list area says that link rules work with more than one Space, and Add Rule is disabled

### Requirement: Saving link rules
Done SHALL drop rows with an empty field and check the rest. When they pass, Done SHALL save them as the new list, in their order, and close the dialog. When they don't, the dialog SHALL stay open, save nothing and show an error line under the list.

#### Scenario: Saving
- **WHEN** the user adds a rule opening URLs containing `example.com` in Work and chooses Done
- **THEN** the dialog closes, and a link to `https://example.com/` from another app opens in Work

#### Scenario: Empty row
- **WHEN** the user chooses Add Rule, leaves the field empty and chooses Done
- **THEN** the dialog closes, and no rule was added

### Requirement: Link rule errors
The error line SHALL say "Enter a valid domain or URL." when a row's text isn't a valid domain or URL, "Each domain or URL and matching option can only appear once." when two rows have the same match option and text, and "Choose a Space for each rule." when a row's Space was deleted while the dialog was open. The error line SHALL go when the user edits a row.

#### Scenario: Invalid text
- **WHEN** a row's field holds `not a url` and the user chooses Done
- **THEN** the dialog stays open with "Enter a valid domain or URL." under the list, and no rule is saved

#### Scenario: Duplicate rule
- **WHEN** two rows both match "URLs containing" `example.com` and the user chooses Done
- **THEN** the dialog stays open with "Each domain or URL and matching option can only appear once."

#### Scenario: Space deleted while open
- **WHEN** a row opens links in Work, Work is deleted while the dialog is open, and the user chooses Done
- **THEN** the dialog stays open with "Choose a Space for each rule."

### Requirement: Discarding edits
Cancel, or Esc, SHALL close the dialog without saving when the rows are as they were when it opened. When they differ, Cancel SHALL instead turn, in place, into a red "Discard Changes" button, still answering Esc; choosing it SHALL close the dialog without saving.

#### Scenario: Cancel without edits
- **WHEN** the user opens the dialog and presses Esc
- **THEN** the dialog closes

#### Scenario: Cancel with edits
- **WHEN** the user adds a rule and presses Esc
- **THEN** the dialog stays open, and Cancel has become a red "Discard Changes" button

#### Scenario: Discarding
- **WHEN** "Discard Changes" shows and the user presses Esc again
- **THEN** the dialog closes, and the rules are as they were before it opened

# Spec Delta

## MODIFIED Requirements

### Requirement: Dialog buttons and keys
A dialog's buttons SHALL sit at its bottom trailing corner, the default button last and filled with the accent colour. A dialog MAY also have one button at its bottom leading corner, such as "Add Rule", which neither Esc nor Return chooses. Esc SHALL choose the cancelling button and Return the default button, and each of those buttons SHALL show its key beside its title, as in Arc. A disabled default button SHALL ignore Return. A click outside the card SHALL do nothing.

#### Scenario: Esc
- **WHEN** a dialog with Cancel shows and the user presses Esc
- **THEN** the dialog closes as if Cancel was clicked

#### Scenario: Return on a disabled default
- **WHEN** the default button is disabled and the user presses Return
- **THEN** nothing happens

#### Scenario: Clicking outside
- **WHEN** the user clicks the dimmed window around the card
- **THEN** the dialog stays open

#### Scenario: A leading button
- **WHEN** a dialog has a button at its bottom leading corner
- **THEN** it shows no key, and Esc and Return leave it alone

### Requirement: Destructive dialog buttons
A dialog MAY mark its default button as destructive, for an action that destroys something. A destructive default button SHALL be filled with the system's red in place of the accent colour, and SHALL otherwise behave as any default button. A dialog MAY also turn its cancelling button destructive while it shows, such as Cancel becoming "Discard Changes" once there are unsaved edits. That button SHALL be filled with the system's red, keep its place and Esc, and widen to fit its title.

#### Scenario: A destructive default
- **WHEN** a dialog's default button is marked destructive
- **THEN** it shows in red, last in the row, and Return chooses it

#### Scenario: A cancelling button turned destructive
- **WHEN** a dialog turns its Cancel button into "Discard Changes"
- **THEN** that button shows in red with ESC beside its title, before the default button, and Esc chooses it

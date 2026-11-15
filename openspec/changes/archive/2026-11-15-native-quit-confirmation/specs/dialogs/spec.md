# Spec Delta

## MODIFIED Requirements

### Requirement: Dialog buttons and keys
A dialog's buttons SHALL sit at its bottom trailing corner, the default button last and filled with the accent colour. A dialog MAY also have one button at its bottom leading corner, such as "Always quit", which neither Esc nor Return chooses. Esc SHALL choose the cancelling button and Return the default button, and each of those buttons SHALL show its key beside its title, as in Arc. A disabled default button SHALL ignore Return. A click outside the card SHALL do nothing.

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

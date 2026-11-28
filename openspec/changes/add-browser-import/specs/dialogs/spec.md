# Spec Delta

## ADDED Requirements

### Requirement: Stepped dialogs
A dialog that leads through steps, such as the import dialog, SHALL place its buttons in place of "Dialog buttons and keys"'s placement, its keys unchanged: its cancelling button at the bottom leading corner on every step, with Esc and its key, and at the bottom trailing corner Back, when the step has one, just before the default button with Return. Back SHALL show no key, and Esc and Return SHALL leave it alone. The card SHALL keep its width from step to step.

#### Scenario: A middle step
- **WHEN** a stepped dialog shows its second step
- **THEN** Cancel with ESC sits at the bottom leading corner, and Back then the default button with RETURN at the bottom trailing corner

#### Scenario: The first step
- **WHEN** a stepped dialog shows its first step
- **THEN** Cancel sits at the bottom leading corner and the default button at the bottom trailing corner, with no Back

#### Scenario: Esc on a later step
- **WHEN** a stepped dialog shows its second step and the user presses Esc
- **THEN** the dialog closes as if Cancel was clicked, rather than going back

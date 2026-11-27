# Spec Delta

## MODIFIED Requirements

### Requirement: Toolbar controls
The toolbar SHALL hold, from its leading edge, the sidebar toggle, back, forward and reload, centred 21, 57.75, 94.75 and 132 points from the card's leading edge, and the host in the middle. At its trailing end it SHALL hold the split button (`split-view`), centred 21 points from the card's trailing edge, as in Arc, then to its left the site-controls button, the pinned extensions and the permission indicators, 36 points apart. All of them SHALL be vertically centred in the toolbar.

#### Scenario: Leading controls
- **WHEN** a window shows the toolbar, with the sidebar shown or hidden
- **THEN** the sidebar toggle, back, forward and reload sit at the toolbar's leading end, 37 points apart, in the same place relative to the card's leading edge

#### Scenario: Trailing controls
- **WHEN** the active tab uses the camera and two extensions are pinned
- **THEN** from the trailing end, the toolbar shows the split button centred 21 points from the card's edge, the site-controls button centred 57 points from it, the second and first pinned extensions centred 93 and 129 points from it, and the camera indicator centred 165 points from it

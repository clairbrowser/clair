# Link Rules: reference screenshots

Probed on 2026-11-15 in Dia 1.57.1 (`company.thebrowser.dia`) and Arc with
`tests/probe/`, at 2 px per point. Clair's dialog copies Dia's **controls
and layout**, and its Settings row follows Arc's Links page. The dialog's
look follows Clair's own dialogs, and its behaviour follows Arc's Air
Traffic Control (`design.md`).

Keep these screenshots: they stay with the change when it's archived.

| File | Shows |
|---|---|
| 01-dia-entry-point.jpg | Dia's "Link Rules…" button, below a card on its Profiles page. Clair follows Arc's Links page instead (12, D7). |
| 02-dia-empty.jpg | The empty dialog: title, a grey rounded list area with "No link rules yet" centred, Add Rule at the bottom leading corner, Cancel (ESC) and Done (↩) at the trailing corner. |
| 03-dia-new-rule.jpg | Add Rule appends a row and focuses its field: `Open [URLs containing ⌃] [example.com] in ● [Personal ⌃] ×`. |
| 04-dia-match-menu.jpg | The match popup: URLs containing, this exact URL, URLs starting with. |
| 05-dia-destination-menu.jpg | The destination popup: each profile with its colour dot. Clair lists Spaces with their icons. |
| 06-dia-saved-rule.jpg | A saved rule after reopening, with the field unfocused. |
| 07-dia-several-rules.jpg | Three rows with hairline separators, the newest at the bottom. |
| 08-dia-invalid-error.jpg | Done with an invalid value: the dialog stays open, grows and shows "Enter a valid domain or URL." in amber under the list. No row is marked. |
| 09-dia-duplicate-error.jpg | The same value and match option twice: "Each domain or URL and matching option can only appear once." |
| 10-dia-discard-changes.jpg | Cancel with unsaved edits turns, in place, into a red "Discard Changes ESC" button; pressing it again discards. |
| 11-arc-air-traffic-control.jpg | Arc's Air Traffic Control, for behaviour only: rules open links in a Space. Clair has no "Default" row and no Little Arc. |
| 12-arc-settings-links.jpg | Arc's Links page: Air Traffic Control is a one-row card at the bottom, "Choose where links open inside Arc. ⓘ" with an "Air Traffic Control…" button. Clair's row follows it as "Choose where links open inside Clair." with "Link Rules…" and no ⓘ (D7). |

## Measurements (points, from the accessibility tree)

- Dialog 640 × 286 with an empty list or one row; 24 inset.
- Title 26 tall; list area 592 wide, at least 146 tall, 8 below the title.
- Row about 48.5 tall: "Open" at +11, match popup 142 wide, field 186 × 26,
  "in", destination popup right-aligned, × button 22 × 11 at the trailing
  edge.
- Buttons 36 tall: Add Rule 89, Cancel 106, Done 84 and Discard Changes 168
  wide; 6 between Cancel and Done; 23 between the list and the buttons.
- The error line, 25 tall, sits between the list and the buttons and grows
  the dialog by 23.
- The list grows with its rows; Dia's scrolls once the dialog would leave
  the window.

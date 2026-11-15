# Proposal

## Why

Arc users route links from other apps with Air Traffic Control: a Meet link from Calendar opens in their Work Space, a Spotify link in Personal. Clair opens every link from another app in the most recently active window, so people with several Spaces or profiles have to move tabs by hand. Dia kept the feature as "Link Rules", with a simpler editor than Arc's. Arc stops working on 2026-12-22.

This builds on `add-spaces` and `add-profiles`, both merged, as built.

## What Changes

- **Link rules route links from other apps to a Space.** A rule matches a link's URL in one of three ways, as Dia's do: URLs containing a text, this exact URL, or URLs starting with a text. It opens a matching link in a new foreground tab of its Space, switching the most recently active window to that Space, or opening a window if none is open. The first matching rule in the list wins. Links that match no rule open as they do today.
- **Only links from other apps.** These are links macOS hands to Clair: clicked in another app while Clair is the default browser, opened with `open`, or handed off from another device. Links clicked inside Clair, the command bar, extensions and session restore are never routed.
- **A Link Rules dialog, laid out as Dia's.**
  - Settings › Links gains a "Link Rules…" button that opens the dialog on the Settings window.
  - Each rule is a row: `Open [match ⌃] [text field] in [Space ⌃] ×`.
  - Add Rule appends a row at the bottom leading corner, and Cancel and Done sit at the trailing corner.
  - Done checks every rule, saves them all and closes; an invalid or duplicate rule keeps the dialog open with an error line under the list.
  - Cancel with unsaved edits turns into a red "Discard Changes" button, which discards on a second press.
  - The dialog keeps the look of Clair's other dialogs; only Dia's controls and layout are copied.
- **Rules follow their Space.** Deleting a Space removes its rules, as does removing a profile with its Spaces.
- **Dialogs gain two options** that the Link Rules dialog needs: a button at the bottom leading corner, and a cancelling button that turns destructive.
- **BREAKING (`ClairHost.h`):** the host gains the link rules, read and replaced as a whole.

**Out of scope:**
- Arc's "Default" destination for unmatched links, and Little Arc.
- Rules by source app, and Dia's routing toasts.
- Routing links clicked inside Clair.
- Importing Arc's or Dia's rules.
- Reordering rules, and syncing them.

## Capabilities

### New Capabilities

- `link-rules`: the rules, how a link from another app is matched and where it opens, which links are routed, and the Link Rules dialog that edits them.

### Modified Capabilities

- `settings-window`: "Link Rules button" is added to the Links page.
- `dialogs`: "Dialog buttons and keys" allows a button at the bottom leading corner, and "Destructive dialog buttons" allows a cancelling button to turn destructive.
- `chromium-engine`: "Browser behavior as in ungoogled-chromium outside Clair's interface" names `link-rules` among Clair's own behaviour, and "What Clair's Chromium hooks may do" adds sending links from other apps to Clair's link rules.

## Impact

- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt.
- **Overlay:** a new rule store in Local State (`clair.link_rules`) with the matching. It is pruned when a Space is deleted, and the host bridge reads and replaces the rules and opens a matched link in its Space.
- **Patch:** a hook in `chrome/browser/app_controller_mac.mm`'s `-openStartupTabsReplacingNTP:`, through which links from other apps arrive.
- **`ClairUI`:** the Links page's button, the Link Rules dialog and its validation, and the two `ClairDialog` options.
- **Runtime suite:** new coverage for routing and the dialog. The Links page is a view the suite drives, so the quality checks run on the branch before merging.
- **References:** Dia's dialog was probed on 2026-11-15. The screenshots are in `dia-reference/` with their measurements, for checking the dialog by hand, and the implementation deletes them when it finishes.

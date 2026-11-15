# Design

"`add-spaces` D*n*", "`add-profiles` D*n*" and "`add-clair-dialogs` D*n*" below are decisions in those changes' archived `design.md`.

## Context

See proposal.md, "Why". What shapes the approach:

- **Links from other apps funnel into one method.**
  - Launch Services delivers links to `-[AppController application:openURLs:]` and Handoff to `-application:continueUserActivity:restorationHandler:`, both in `chrome/browser/app_controller_mac.mm`.
  - Both build `StartupTabs` and call `-openStartupTabsReplacingNTP:`. Before start-up completes, that method queues the tabs in `_startupTabs`. `-openStartupUrls` sends them through the same method once it has.
  - It then calls `OpenStartupTabsInBrowser`, which opens them in the last used profile's browser.
  - Links clicked inside Clair, the command bar, extensions and session restore never reach it.
- **Opening in a Space already exists.**
  - `ClairWindowGroup::OpenInSpace(space, url, then)` opens a URL in a new foreground tab of a Space: in the most recently active regular group, switching it to that Space, or in a new window (`add-spaces` D7, `add-profiles` D8).
  - `-[ClairChromiumHost openURL:inProfile:]` uses it.
- **Spaces live in Local State** (`ClairSpaceStore`, `clair.spaces`), and its `Observer::OnSpacesChanged` fires on any change, deletion included. Deleting a profile deletes its Spaces through the same store.
- **Settings already presents Clair dialogs.** `SettingsWindowController` owns a `ClairDialogPresenter` on its window, which the Profiles page uses.
  - `ClairDialogView` is 450 pt wide, with an optional icon and its buttons at the trailing corner.
  - A page can swap its content and update its buttons in place (`add-clair-dialogs` D1).
- **Dia's dialog was probed on 2026-11-15** with `tests/probe/`. `dia-reference/` holds the screenshots and measurements, and its README indexes them. Arc's Air Traffic Control sheet is there too, for behaviour only, and Arc's Links page, which the Settings row follows (D7).

## Goals / Non-Goals

**Goals:**
- One rule store and one matcher, in the engine, used for every link from another app, including at a cold launch.
- A dialog with Dia's controls and layout, built from `ClairDialog` rather than a separate sheet.
- Hooks only in Chromium files: one call in `app_controller_mac.mm`.

**Non-Goals:**
- Routing inside Clair, such as navigation throttles or `chrome.tabs`.
- Changing where unmatched links open.
- A Swift copy of the matcher. `ClairUI` validates the text only, for its error messages.

## Decisions

### D1. Rules live in Local State, owned by the engine

`overlay/chrome/browser/clair/clair_link_rule_store.{h,mm}` keeps the rules in Local State, next to the Space store:

```
clair.link_rules  { "version": 1,
                    "rules": [ { "id": "<uuid>",
                                 "match": "contains" | "exact" | "prefix",
                                 "text": "example.com",
                                 "space": "<space uuid>" } ] }
```

- Reading keeps only entries that are valid: a known `match`, a text that D3 accepts, and a Space the store knows. A rule whose Space has gone is dropped on read too, so a crash between a Space's deletion and the pruning can't leave a dangling rule.
- `id` lets a later change reorder or sync rules. `ClairUI` ignores it.
- The store observes `ClairSpaceStore`. On `OnSpacesChanged` it drops rules whose Space no longer exists, which covers deleting a Space and removing a profile.

*Alternatives:*
- `ClairUI`'s user defaults, as the Peek toggles are kept. Matching would then need a round trip to `ClairUI` for every link, including during start-up before `ClairUI` has a window, and the Space pruning would have to be in Swift too.
- One store per profile. Rules are app-wide, and a rule's Space already names its profile.

### D2. The hook in `-openStartupTabsReplacingNTP:`

A new `patches/clair/link-rules.patch` adds one call at the point in `-openStartupTabsReplacingNTP:` where start-up is complete, just before `OpenStartupTabsInBrowser`:

```
clair::RouteLinksFromOtherApps(tabs);   // removes the tabs it opened
if (tabs.empty()) return;
OpenStartupTabsInBrowser(std::move(tabs));
```

- `clair::RouteLinksFromOtherApps` lives in `overlay/chrome/browser/clair/clair_link_rules.{h,mm}`. For each `http` or `https` tab, it asks the store for the first matching rule and, if there is one, calls `ClairWindowGroup::OpenInSpace` and removes the tab from the list.
- Tabs it leaves open as before, in their original order.
- Every route runs through this point after start-up, so queued cold-launch links are routed too, once Spaces and profiles exist.
- At a cold launch with session restore, routed links open after the restored windows. `OpenInSpace` picks the most recently active restored group, as for any link.
- `is_untrusted_launch` tabs (`google-chrome://` and Handoff) are routed like the others, since `OpenInSpace` opens a plain web URL in a tab.

*Alternatives:*
- `-application:openURLs:` only. That misses Handoff, and queued URLs would need a second hook in `-openStartupUrls`.
- A navigation throttle. It can't tell a link from another app from one opened inside Clair.

### D3. Matching

`clair::LinkRuleMatcher` in `clair_link_rule_store.mm`, on Chromium's `GURL`. The engine has no unit-test target, so the runtime suite covers the matcher through real links from another app:

- **Reading a text** (rule texts and validation): trim whitespace, and reject a text that is empty or still contains whitespace. If it has no `scheme://`, prefix `https://`. Parse it with `GURL` and require a valid `http` or `https` URL with a host. A text that was written without a scheme is *scheme-free*.
- **Comparison form of a link:** its `GURL` spec without the fragment. For a scheme-free rule, the scheme and `://` are removed from both sides, so `http` and `https` match alike.
- **contains:** the link's comparison form contains the raw trimmed text, compared in lower case. It uses the raw text, so that `meet.google` (not a full host) works.
- **exact:** the comparison forms are equal. Canonicalisation lowercases the host and adds the root path, so `example.com` equals `https://EXAMPLE.com/`.
- **prefix:** the link's comparison form starts with the text's. `example.com` becomes `example.com/`, so it doesn't match `example.com.evil.net`.
- The first rule in order wins.

`ClairUI`'s validation (D5) mirrors only the "reading a text" rule, with `URLComponents`. Any text it lets through that `GURL` rejects is dropped by the store, and the dialog shows the list again when it reopens. The runtime suite covers the texts in the specs' scenarios on both sides.

*Alternative:* matching by domain (Dia's binary has options for a domain with its subdomains and an exact domain, which its menu doesn't show). Left out, as in Dia's shipping menu.

### D4. The contract

`native/ClairHost.h` gains:

```objc
typedef NS_ENUM(NSInteger, ClairLinkRuleMatch) {
  ClairLinkRuleMatchContains, ClairLinkRuleMatchExact, ClairLinkRuleMatchPrefix,
} NS_SWIFT_NAME(LinkRuleMatch);

@protocol ClairLinkRule <NSObject>
@property(nonatomic, readonly) ClairLinkRuleMatch match;
@property(nonatomic, readonly, copy) NSString *text;
@property(nonatomic, readonly, copy) ClairSpaceID spaceID;
@end

// in ClairHost
@property(nonatomic, readonly, copy) NSArray<id<ClairLinkRule>> *linkRules;
- (void)setLinkRules:(NSArray<id<ClairLinkRule>> *)rules;   // replaces all
- (BOOL)isValidLinkRuleText:(NSString *)text;               // D3's reading
```

- `setLinkRules:` copies each rule's properties, keeps the order and drops invalid ones (D1). `ClairUI` passes its own value type conforming to the protocol.
- `isValidLinkRuleText:` lets the dialog ask the engine itself, so D3's "mirror" is only a fallback for `FakeHost`. With it, D5's error matches what the store keeps.
- No observer: only the dialog reads the rules, when it opens. A Space deleted while it's open is seen through the existing `spacesDidChange:` (D5).

### D5. The dialog

`native/ClairUI/LinkRulesDialog.swift` (view) and `LinkRulesLogic.swift` (state and validation, unit-tested against `FakeHost`):

- **A `ClairDialog` on the Settings window's presenter.** The page has no icon, the title "Link Rules", the rows as its content, and:
  - `leadingButton: ClairDialogButton?` "Add Rule";
  - Cancel (`.cancel`) and Done (`.default`).
- **Width.** `ClairDialogPage` gains an optional `width`, 640 for this dialog, as Dia's. The content slot widens with it, which is 592 pt with Dia's insets and less with Clair's 38/28; the row's controls fit either way.
- **Rows** follow `dia-reference/`'s measurements:
  - "Open" in secondary text;
  - a borderless `Picker` (`.menu`) for the match;
  - a 186 pt `TextField` with the placeholder `example.com`;
  - "in";
  - a trailing borderless `Picker` of Spaces, sectioned by profile when there's more than one, each item the Space's icon (if any) and name;
  - an `xmark` button labelled "Remove Link Rule".
  - Rows are about 48 pt tall on a grey rounded area (Dia's list background, which `ClairDialogView` gets as a tint of the card's background), with inset hairlines. The area is at least 146 pt tall and scrolls beyond what the Settings window can show.
- **Look.** Fonts, colours and the buttons' fills are Clair's dialogs', not Dia's. Done is the accent-filled default, not Dia's black.
- **Errors.** Done runs the checks in order: drop empty rows, then validity, Space, duplicates. It shows the first failing message in a line between the list and the buttons, in the system's orange as Dia's amber, and the card grows to fit. Any edit clears it.
- **Discarding.** `LinkRulesLogic` compares the rows with the list read at opening (match, trimmed text, Space, order). While they differ, the page's cancel button is `ClairDialogButton(title: "Discard Changes", role: .cancel, isDestructive: true)`. The first Esc or click only flips the button, which `ClairDialogButton.action` does without answering; the second answers `.cancelled`.
- **Spaces deleted while open.** On `spacesDidChange:`, a row whose Space has gone shows an empty popup ("Choose a Space"), and Done reports "Choose a Space for each rule."
- **One Space.** With no rules, the list area shows the "more than one Space" message in place of "No link rules yet", and Add Rule is disabled either way. Rules for the one remaining Space can still exist after the user deletes the others; those rows still show, so they can be removed.

*Alternative:* a separate SwiftUI sheet as Dia's. Rejected: `ClairDialog` already gives the dimming, keys, focus, VoiceOver and the ESC/↩ capsules that `dialogs` specifies.

### D6. `ClairDialog` options

- **`ClairDialogPage.leadingButton`.** It sits at the bottom leading corner, shows no key, and gets `KeyboardShortcut` nil. Its action never answers the dialog.
- **`ClairDialogButton.isDestructive` for the cancel role.** Today `isDestructive` is derived from `.destructive`, a default role. It becomes a stored flag valid for both `.cancel` and `.default`. A destructive cancel button is red with the ESC capsule and keeps `.cancelAction`. The button row animates its width change with the dialog's existing swap animation.
- The runtime suite's identifiers stay: `clair.dialogCancel`, `clair.dialogDefault`, and a new `clair.dialogLeading`.

### D7. Settings › Links

The entry point follows Arc's Links page (`dia-reference/12-arc-settings-links.jpg`): Air Traffic Control is a card of its own at the bottom of the page, below the Peek card, with one row and no section text.

- `LinksSettingsView` gains a second `Section` below the Peek toggles, holding one `LabeledContent` row.
- Its label is "Choose where links open inside Clair.", with Arc's trailing full stop. Arc's ⓘ button after it is left out.
- Its trailing button is "Link Rules…" in place of "Air Traffic Control…", a standard bordered button as Arc's.
- The button calls `SettingsWindowController.showLinkRules()`, which reads `host.linkRules` and `host.spaces` and shows the dialog. Its accessibility identifier is `clair.linkRulesButton`.

*Alternative:* Dia's button alone under a card (`01-dia-entry-point.jpg`). Clair's Settings pages follow Arc's.

## Risks / Trade-offs

- **[`GURL` and `URLComponents` disagree on an odd text]** → D4's `isValidLinkRuleText:` makes the engine the judge in the real app. Only `FakeHost` uses the Swift fallback.
- **[A cold launch routes before the user's windows restore]** → D2 routes only after start-up completes, through the same queue Chromium uses. The runtime suite launches Clair with a matching link.
- **[A rule pointing at the Space the user is in feels like nothing happened]** → It opens a new tab there, as Arc does.
- **[`openStartupTabsReplacingNTP:` changes upstream]** → The hook is one call before `OpenStartupTabsInBrowser`, and the patch check fails loudly if it no longer applies.
- **[Incognito or guest as the most recent window]** → `OpenInSpace` already skips them (`add-profiles` D8).
- **[Rules lost on a downgrade]** → An older Clair ignores `clair.link_rules`, and a newer one reads it again.

## Migration Plan

Nothing to migrate: `clair.link_rules` is new, and its absence means no rules. A rollback leaves the pref unused in Local State.

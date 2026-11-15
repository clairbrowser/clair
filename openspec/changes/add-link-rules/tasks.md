# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means launching a test build of the branch with `tests/probe/launch-clair.sh` and comparing it with `dia-reference/`, whose README indexes the screenshots and Dia's measurements; don't re-probe Dia for what they already show. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), since the change alters a view the runtime suite drives. D-numbers are `design.md`'s decisions.

Suggested order: 1, then 2 and 3 in parallel. Group 3 can start in `ClairUI` against `FakeHost` as soon as 1 is done, while the engine builds. Group 4 is last.

Read `design.md` in full before starting. Verify every Chromium call it names against the engine workspace's source before using it, and update the design if one differs.

## 1. Contract and fakes

- [ ] 1.1 Add `ClairLinkRuleMatch`, `ClairLinkRule`, `linkRules`, `setLinkRules:` and `isValidLinkRuleText:` to `native/ClairHost.h` (D4), documented as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Give `FakeHost` a rule list that `setLinkRules:` replaces, dropping rules for unknown Spaces, a Swift `isValidLinkRuleText:` that follows D3's "reading a text", and the pruning of a deleted Space's rules. Verify with new cases in `SettingsTests` in CI.

## 2. Engine

- [ ] 2.1 Add `overlay/chrome/browser/clair/clair_link_rule_store.{h,mm}` (D1, D3): the `clair.link_rules` Local State pref and its registration in `clair::RegisterLocalStatePrefs`; reading that keeps only valid rules; replacing the list; pruning on `ClairSpaceStore::Observer::OnSpacesChanged`; the matcher. Add the sources to the `BUILD.gn` hunk. Verify with the runtime tests in 3.5: rules survive a relaunch, and a deleted Space's rule is gone.
- [ ] 2.2 Add `overlay/chrome/browser/clair/clair_link_rules.{h,mm}` with `clair::RouteLinksFromOtherApps` (D2), and its call in `-openStartupTabsReplacingNTP:` in a new `patches/clair/link-rules.patch` listed in `patches/series`. Verify that the patch check applies it, and with the runtime tests in 3.5: every scenario of `link-rules`' requirements from "Match options" to "Links opened inside Clair are not routed", including a cold launch with a matching link and a link clicked inside Clair.
- [ ] 2.3 Implement the D4 calls in `ClairChromiumHost`. Verify with the runtime tests in 3.5: rules saved in the dialog are the ones the engine routes by, in order.
- [ ] 2.4 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.5 Add a "Link rules" section to `docs/native-window.md` (the store, the matcher, the hook, the dialog) and its rows in "Where each piece lives". Verify that every file and decision it names exists.

## 3. ClairUI

- [ ] 3.1 Add an optional `width` to `ClairDialogPage`, and a stored `isDestructive` for cancel buttons, to `ClairDialog.swift` (D6). `leadingButton`, with the identifier `clair.dialogLeading`, comes from `native-quit-confirmation`. Verify with new cases in `ClairDialogTests` in CI: the leading button takes neither key, a destructive cancel button keeps Esc, and the existing cases pass.
- [ ] 3.2 Add `LinkRulesLogic.swift` (D5): the rows read from the host, adding and removing, the checks in order with their messages, the comparison for unsaved edits, the Discard Changes flip, Spaces deleted while open, and the one-Space state. Verify with new cases in `SettingsTests` in CI, one for each scenario of `link-rules`' requirements from "Link Rules dialog" to "Discarding edits".
- [ ] 3.3 Add `LinkRulesDialog.swift` (D5): the rows, popups grouped by profile, the list area and its empty states, and the error line. Check it by hand against `dia-reference/` 02 to 10, in Light and Dark Mode. Verify that the layout matches the README's measurements within a few points, and that the look is Clair's dialogs'.
- [ ] 3.4 Add the "Choose where links open inside Clair." card and `clair.linkRulesButton` to `LinksSettingsView`, and `SettingsWindowController.showLinkRules()` (D7). Verify with a case in `SettingsTests` in CI, and by hand against `dia-reference/12-arc-settings-links.jpg` and `settings-window`'s "Link Rules button" scenarios.
- [ ] 3.5 Add `tests/runtime/ClairRuntimeTests/LinkRulesTests.swift`. It drives the dialog through its identifiers, sends links "from another app" with `NSWorkspace.open(_:withApplicationAt:configuration:)` from the test runner, and checks where they open through the accessibility tree and DevTools. Cover the specs' scenarios for routing, matching, saving, discarding, deleting a Space and a relaunch. Verify with a `quality.yml` run on the branch.

## 4. Release notes and integration

- [ ] 4.1 Add a Changie fragment (`changie new`): Added for link rules in Settings › Links, which open links from other apps in a chosen Space. Verify that it's in the PR.
- [ ] 4.2 Run the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
- After archiving, delete the temporary probe output in `build/probe/link-rules/`. Keep `dia-reference/`, which moves into the archive with the change.

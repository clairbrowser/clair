# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. D-numbers are `design.md`'s decisions.

## 1. Contract and ClairUI

- [ ] 1.1 In `native/ClairHost.h`, document `ClairExtensionAction.name` as the extension's name and add `title` (D1); add `title` to `FakeExtensionAction`. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Use `title` for the tooltip and VoiceOver label of the pinned tile (`PinnedExtensions.swift`) and the Site Control Center tile (`SiteControlCenter.swift`) (D2). Verify that the `ClairUI` build passes in CI.

## 2. Engine

- [ ] 2.1 In `ClairExtensions::Snapshot` (`clair_extensions.mm`), fill `name` with `GetFixupExtensionNameForUIDisplay(extension->name())` and `title` with the action's title for the active tab, or that name when it's empty (D1, D3). Verify with the runtime test in 3.1.
- [ ] 2.2 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.

## 3. Tests and release notes

- [ ] 3.1 Make `tests/runtime/extensions/popup-badge` set its action's title to "3 badges for this page", and add a runtime test that the Extensions menu lists the extension as "Clair Test Action" and its pinned tile's VoiceOver label is "3 badges for this page". Verify with a `quality.yml` run on the branch.
- [ ] 3.2 Add a Changie fragment. Verify that `openspec validate --all --strict` passes in CI.

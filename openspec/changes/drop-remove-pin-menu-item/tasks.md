# Tasks

## 1. The pinned tab menu

- [ ] 1.1 Remove Remove Pin from `PinsLogic.pinnedMenu`, its `MenuCommand.removePin` and its dispatch in `PinsViews.swift`, and update `PinsTests`' menu test. Verify that CI's ClairUI build and tests pass, and by hand with the probe that a pinned tab's menu ends with Pin to Favorites and Unpin Tab, and that the × on an unselected pinned tab still removes it.

## 2. Release notes and checks

- [ ] 2.1 Add a Changie fragment: a pinned tab's menu no longer has Remove Pin. Verify that it's in the PR.
- [ ] 2.2 Run the merge gate and the quality checks on the branch (`gh workflow run quality.yml --ref <branch>`). Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.

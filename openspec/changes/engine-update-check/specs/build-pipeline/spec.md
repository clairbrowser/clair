# Spec Delta

## ADDED Requirements

### Requirement: Upstream engine releases checked daily
A workflow on a GitHub-hosted runner SHALL check at least once a day whether ungoogled-chromium has published a release tag newer than the pinned one, comparing versions numerically. It MAY also be started by hand with a tag to update to. When a newer tag exists, it SHALL run the patch check against the pin moved to that tag, and SHALL never use the self-hosted runner.

#### Scenario: No newer tag
- **WHEN** the scheduled check runs and the pinned tag is the newest ungoogled-chromium tag
- **THEN** it finishes without running the patch check, pushing a branch or opening a pull request

#### Scenario: Newer tag published
- **WHEN** the scheduled check runs and ungoogled-chromium has published a tag newer than the pinned one, and no engine update pull request is open
- **THEN** it runs the patch check, on a hosted runner, against the newest such tag

#### Scenario: Tag that is not newer
- **WHEN** the check is started by hand with a tag that is not newer than the pinned one, or that ungoogled-chromium hasn't published
- **THEN** it stops with an error naming the tag and opens nothing

#### Scenario: Upstream can't be read
- **WHEN** the list of ungoogled-chromium tags can't be fetched or holds no valid tag
- **THEN** the run fails with an error and opens nothing

### Requirement: Engine update pull request
After the patch check, the workflow SHALL open a pull request against `main` whose only change is the moved pin and a Changie fragment that names the new Chromium version. The pull request SHALL be ready for review when the check passed, and a draft when it failed. Its description SHALL name the tag and link the run, and SHALL give the command that builds its engine.

#### Scenario: Patches apply
- **WHEN** the patch check passes for the new tag
- **THEN** a pull request ready for review moves the pin to that tag, and its description gives the engine build command for its branch

#### Scenario: Patches need updating
- **WHEN** the patch check fails for the new tag
- **THEN** a draft pull request moves the pin to that tag, and its description says that Clair's patches need updating, names the patch that stopped the check and links the failing run

#### Scenario: Checks run on the pull request
- **WHEN** the engine update pull request is opened, ready or draft
- **THEN** the merge gate runs on it like on any pull request, and it can't merge until its engine is published, as for any change to the engine key

### Requirement: One engine update in review at a time
While an engine update pull request is open, the scheduled check SHALL NOT open another one. If a newer tag than the open pull request's appears, it SHALL comment on that pull request once for that tag. A tag whose update pull request was closed without merging SHALL NOT be proposed again by the scheduled check.

#### Scenario: Newer tag while an update is open
- **WHEN** an engine update pull request for one tag is open and the scheduled check finds a newer tag
- **THEN** it comments on the open pull request naming the newer tag, once, and opens no other pull request

#### Scenario: Update closed without merging
- **WHEN** the owner closed an engine update pull request for a tag without merging it, and that tag is still the newest
- **THEN** the scheduled check opens nothing for that tag, and only a check started by hand with that tag proposes it again

### Requirement: Engine update credentials
Only the job that pushes the update branch and opens or comments on the pull request SHALL hold write access, through a short-lived token of a GitHub App installed on this repository alone. The App's credentials SHALL be secrets of an `engine-update` environment limited to `main`. The job that fetches and patches the upstream source SHALL hold no secrets and read-only repository access.

#### Scenario: Upstream code runs without credentials
- **WHEN** the patch check runs upstream's scripts for the new tag
- **THEN** its job has no repository secrets, no environment and a read-only token

#### Scenario: Branch other than main
- **WHEN** the update workflow is started from a branch other than `main`
- **THEN** the job that opens the pull request can't read the App's credentials and fails before pushing anything

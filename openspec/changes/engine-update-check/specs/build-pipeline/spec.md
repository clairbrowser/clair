# Spec Delta

## ADDED Requirements

### Requirement: Upstream engine releases checked daily
A workflow on a GitHub-hosted runner SHALL check at least once a day whether ungoogled-chromium has published a release tag newer than the pinned one, comparing versions numerically. It MAY also be started by hand with a tag to update to. When a newer tag exists, it SHALL open an engine update pull request for it, and SHALL never use the self-hosted runner.

#### Scenario: No newer tag
- **WHEN** the scheduled check runs and the pinned tag is the newest ungoogled-chromium tag
- **THEN** it finishes without pushing a branch or opening a pull request

#### Scenario: Newer tag published
- **WHEN** the scheduled check runs and ungoogled-chromium has published a tag newer than the pinned one, and no engine update pull request is open
- **THEN** it opens an engine update pull request for the newest such tag

#### Scenario: Tag that is not newer
- **WHEN** the check is started by hand with a tag that is not newer than the pinned one, or that ungoogled-chromium hasn't published
- **THEN** it stops with an error naming the tag and opens nothing

#### Scenario: Upstream can't be read
- **WHEN** the list of ungoogled-chromium tags can't be fetched or holds no valid tag
- **THEN** the run fails with an error and opens nothing

### Requirement: Engine update pull request
An engine update pull request SHALL be opened as a draft against `main`, labelled `engine-update`. Its only change SHALL be the moved pin and a Changie fragment naming the new Chromium version. Its description SHALL name the tag, link the run that opened it, and list the update steps that stay manual. The merge gate SHALL run on it as on any pull request.

#### Scenario: Update opened
- **WHEN** the check opens an engine update pull request
- **THEN** it is a draft, moves the pin to the new tag, adds the Changie fragment, and the merge gate, including the patch check, runs on it

#### Scenario: Merge rules unchanged
- **WHEN** an engine update pull request's patch check has passed but its engine isn't published
- **THEN** it can't merge, as for any change to the engine key

### Requirement: Engine update state follows the patch check
When the merge gate finishes on an engine update pull request's head commit, its draft state SHALL follow that run's patch check. A passed or skipped check SHALL mark it ready for review and give the engine build command for its branch. A failed check SHALL keep or return it to draft, with a comment saying that Clair's patches need updating, naming the patch that stopped the check and linking the run.

#### Scenario: Patches apply
- **WHEN** the patch check passes on the draft engine update pull request
- **THEN** the pull request is marked ready for review and a comment gives `gh workflow run engine.yml -f ref=<its branch>`

#### Scenario: Patches need updating
- **WHEN** the patch check fails on the engine update pull request
- **THEN** the pull request stays a draft, or returns to draft, and one comment for that commit says the patches need updating, names the patch that stopped the check and links the run

#### Scenario: Patch fixes pushed
- **WHEN** the owner pushes patch fixes to a draft engine update pull request and the patch check then passes
- **THEN** the pull request is marked ready for review

#### Scenario: Run cancelled
- **WHEN** the merge gate's run on the engine update pull request is cancelled, or its patch check didn't finish
- **THEN** the pull request's state and comments don't change

### Requirement: CI results acted on only for update branches
The workflow that reacts to the merge gate SHALL act only on a run triggered by a pull request whose head branch is an engine update branch of this repository, not a fork, and whose pull request carries the `engine-update` label. It SHALL NOT check out or run the pull request's code, and SHALL take the failing patch's name only when it has the form of a patch path.

#### Scenario: Other pull request
- **WHEN** the merge gate finishes on any pull request that isn't an engine update pull request, including one from a fork whose branch has an update branch's name
- **THEN** the workflow stops before obtaining any credentials and changes nothing

#### Scenario: Unexpected patch name
- **WHEN** the failing patch's reported name isn't a plain relative `.patch` path
- **THEN** the comment says the patch check failed and links the run, without naming a patch

### Requirement: Engine update credentials
Only the jobs that push the update branch, change a pull request's state or comment on it SHALL hold write access, through a short-lived token of a GitHub App installed on this repository alone. The App's credentials SHALL be secrets of an `engine-update` environment limited to `main`, separate from the `release` environment.

#### Scenario: Branch other than main
- **WHEN** the update workflow is started from a branch other than `main`
- **THEN** its jobs can't read the App's credentials, and it fails before pushing anything

#### Scenario: Pull requests opened with the App's token
- **WHEN** the update workflow opens an engine update pull request
- **THEN** the merge gate runs on it, which a pull request opened with the workflow's own token wouldn't trigger

### Requirement: Patch check names the failing patch
When the patch check fails because a patch doesn't apply, it SHALL report that patch's path, relative to the series it belongs to, as an error annotation on its job, in addition to its log.

#### Scenario: Clair patch no longer applies
- **WHEN** a patch in `patches/series` doesn't apply during the patch check
- **THEN** the job fails with an error annotation naming that patch's path

#### Scenario: Failure not caused by a patch
- **WHEN** the patch check fails before any patch is applied, for example while fetching the source
- **THEN** it reports no patch name, and its log shows the error

# Spec Delta

## ADDED Requirements

### Requirement: Engine update pull request
The repository SHALL check ungoogled-chromium's release tags on a schedule, at least once a day. When a tag newer than `main`'s pin exists and no engine update pull request is open, it SHALL open a draft pull request that only moves the pin to the newest tag and adds its release note. The check MUST NOT start an engine build or merge a pull request. It SHALL NOT open a pull request for a tag whose pull request was closed without merging.

#### Scenario: Patch-level tag
- **WHEN** ungoogled-chromium publishes a new tag for the Chromium major Clair already uses, and no engine update pull request is open
- **THEN** within a day a draft pull request exists that changes only the pinned tag and the release note

#### Scenario: New major
- **WHEN** ungoogled-chromium publishes a tag for a newer Chromium major
- **THEN** the draft pull request says it is a new major, says whether ungoogled-chromium-macos has tagged that version, and lists the manual steps of an engine update

#### Scenario: Declined tag
- **WHEN** the owner closes an engine update pull request without merging it, and no newer tag exists
- **THEN** no new pull request is opened for that tag

#### Scenario: No build is started
- **WHEN** an engine update pull request is opened or updated
- **THEN** no job runs on the owner's self-hosted Mac until the owner starts the engine build

### Requirement: Engine update pull request takes newer tags
At most one engine update pull request SHALL be open at a time. When a newer tag appears while it is open, the pin SHALL move to that tag in the same pull request, keeping every commit already on its branch. Once the owner has started an engine build for the pull request's current pin, the pin SHALL NOT move unless the owner asks for the newer tag. The check MUST NOT rewrite or remove commits it did not make.

#### Scenario: Newer tag while fixes are in progress
- **WHEN** an engine update pull request holds commits the owner pushed, no engine build has been started for its current pin, and a newer tag appears
- **THEN** a commit that moves the pin to the newer tag is added on top of the owner's commits, and the pull request's title names the newer tag

#### Scenario: Engine build started
- **WHEN** a newer tag appears after the owner started an engine build for the open pull request's current pin, whether that build is running, failed or published an engine
- **THEN** the pull request's branch is left unchanged, and its description names the newer tag and says why it was not taken

#### Scenario: Owner asks for the newer tag
- **WHEN** the owner starts the check by hand and asks it to take the newest tag, on a pull request whose pin is held
- **THEN** a commit that moves the pin to the newest tag is added to the pull request

### Requirement: Engine update pull request follows the patch check
After each merge gate run on the engine update pull request's head commit, the pull request SHALL be ready for review when its patch check passed or was skipped, and a draft when it failed or timed out. One comment SHALL be kept up to date: after a failure it lists every Clair patch that does not apply, and after a pass it gives the command that builds the engine. A result for a commit that is no longer the head SHALL change nothing.

#### Scenario: Every patch applies
- **WHEN** the patch check passes on a draft engine update pull request
- **THEN** the pull request is marked ready for review, and its comment gives the command to build the engine

#### Scenario: Patches fail
- **WHEN** the patch check fails on an engine update pull request because two Clair patches don't apply
- **THEN** the pull request is a draft, and its comment names both patches

#### Scenario: Owner pushes a fix
- **WHEN** the owner pushes a commit that makes the last failing patch apply
- **THEN** once that commit's patch check passes, the pull request is marked ready for review with no further action from the owner

#### Scenario: A fix breaks a patch
- **WHEN** a push to a ready engine update pull request makes a patch fail
- **THEN** the pull request returns to draft, and its comment names that patch

#### Scenario: Failure outside the patches
- **WHEN** the patch check fails before or after the patch series, for example while fetching the source
- **THEN** the pull request is a draft, and its comment says the check failed at another step and links to its log

#### Scenario: Result for an old commit
- **WHEN** a merge gate run finishes for a commit that a later push replaced
- **THEN** the pull request's state and comment do not change

## MODIFIED Requirements

### Requirement: Patch check for engine changes
A pull request that changes the engine key SHALL also run a patch check on a GitHub-hosted runner, unless `chromium-engine-<key>` for its head commit's key is published when the run starts. It applies both patch series, the overlay and domain substitution to the pinned source, without compiling. It SHALL try every patch in Clair's series and fail naming each one that does not apply. Such a pull request SHALL NOT merge until its engine is published and its patch check, if it ran, has passed.

#### Scenario: Patch no longer applies
- **WHEN** a pull request bumps the ungoogled-chromium tag and one Clair patch no longer applies
- **THEN** the patch check fails and names that patch

#### Scenario: Several patches no longer apply
- **WHEN** a pull request bumps the ungoogled-chromium tag and three patches in `patches/series` no longer apply
- **THEN** one run of the patch check fails and names all three

#### Scenario: Context around a patch changed
- **WHEN** one context line of a patch in `patches/series` no longer matches the source, including a hunk's outermost line
- **THEN** the patch check fails and names that patch, because Clair's series is applied with no fuzz

#### Scenario: Engine not yet built
- **WHEN** an engine pull request's patch check passes but its engine has not been published
- **THEN** the engine check fails with a message naming the key and the command to build it, and the pull request can't merge

#### Scenario: Engine already published
- **WHEN** a pull request changes the engine key and `chromium-engine-<key>` is already published for its head commit's key
- **THEN** the patch check is skipped and the engine check passes

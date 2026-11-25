# Building Clair

Clair is ungoogled-chromium plus Clair's patches, built for Apple Silicon Macs. The same `build.sh` stages run on your Mac and in GitHub Actions.

## Building in GitHub Actions (the usual way)

The build is split in two (design D9–D12 of the active OpenSpec change):

- **The engine**, the patched Chromium, is built only on the owner's Mac by `.github/workflows/engine.yml`, when the owner starts it: `gh workflow run engine.yml -f ref=<branch>`. That uses `main`'s copy of `engine.yml`; add `--ref <branch>` when the branch changes the workflow itself. It publishes the prerelease `chromium-engine-<key>`, where the key is a hash of the engine's inputs (`scripts/engine-key.sh --manifest` lists them). Read its log with `gh run view --log`. After each run, `scripts/prune-engines.sh` keeps the 5 newest engines and any that `main` or an open pull request needs, and deletes the rest with their tags; to get a deleted one back, run `engine.yml` on its branch again.
- **The engine check**, the `Engine check` job in `.github/workflows/ci.yml`, compares each pull request's engine key with its base's. When they're the same (a Swift, script or docs change), it passes at once. When they differ and `chromium-engine-<key>` isn't published yet, the `Patch check` job runs `./build.sh fetch prepare` on a GitHub-hosted `xcode-27` runner (about 20 minutes); once it's published, the job is skipped, because `engine.yml` applied the same inputs to build it. Every patch in Clair's series is tried: when any doesn't apply, the job fails after the series, before the overlay is copied, and the log names each of them on a `clair-patch-failed: <path>` line. A skipped patch can make a later one that builds on it fail too, so fix them from the top. Clair's series is applied with no fuzz (`engine/steps/patch-no-fuzz.sh`), so a change to any context line counts as not applying; ungoogled-chromium's own series keeps `patch`'s defaults and stops at its first patch that doesn't apply. The same stage copies the overlay, compiles Clair's icon and replaces Chromium's logos (see `resources/icon/README.md`); a logo path that no longer exists in Chromium also fails the job and is named in the log. The engine check then fails until `chromium-engine-<key>` is published, and its error gives the `gh workflow run engine.yml` command to build it. Once `engine.yml` publishes an engine, it re-runs the engine check of every open pull request waiting for that key, so the pull request turns green by itself. The `Engine key` job's log lists the engine inputs the pull request changed. A new push to the same pull request cancels the checks that are running.

To try an engine, download it with `gh release download chromium-engine-<key>`, unzip it and remove the quarantine flag first: `xattr -dr com.apple.quarantine Clair.app`.

## Development tools

Working on Clair, as opposed to building it, needs a few more tools:

| Tool | Used for | Install |
|---|---|---|
| [OpenSpec](https://openspec.dev) 2.1 or later | Planning changes in `openspec/`, and the `openspec-*` agent skills | See [OpenSpec's installation guide](https://openspec.dev/docs/installation) |
| GitHub CLI (`gh`) | Engine builds, job logs, pull requests | `brew install gh` |
| [Changie](https://changie.dev) | Release-note fragments (see `.changes/README.md`) | `brew install changie` |
| `shellcheck`, `actionlint`, `cmark-gfm` | Running the merge gate's script tests and lints locally. Optional, because CI runs them | `brew install shellcheck actionlint cmark-gfm` |

Since OpenSpec 2.1, its agent skills (`openspec-propose`, `openspec-apply-change` and the others) live on each machine, not in the repository: in `~/.agents/skills/`, linked from `~/.claude/skills/`. After installing the CLI, run `openspec update` once and answer Yes to set them up. Run it again after upgrading OpenSpec to refresh them. CI runs `openspec validate --all --strict` with the version pinned in `.github/workflows/ci.yml`.

## Building locally

### System requirements

Building and running have different requirements: Clair runs on macOS 15.6 or later, but building it needs a much newer Mac.

| | Engine (Chromium) | Native layer (`ClairUI`) |
|---|---|---|
| Mac | Apple Silicon, 32 GB of RAM or more, about 80 GB of free disk (a 40 GB workspace plus the 30 GB reserve) | Apple Silicon |
| macOS | 26.6 or later, for Xcode 27.2 | 26.6 or later, for Xcode 27.2 |
| Xcode | 27.2 or later, with its Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`): ANGLE compiles its shaders with it | 27.2 or later: the project is in Xcode's JSON format (`project.xcproj`), which Xcode 26 can't open |
| macOS SDK | The newest released SDK that Chromium's linker can read, passed with `-s`: for now the newest 26.x, since the linker can't read the macOS 27 SDK that Xcode 27 ships. The Command Line Tools include a 26.x SDK (`/Library/Developer/CommandLineTools/SDKs/`) | Xcode's own |
| Other tools | Python 3.13 with `pip3 install PySocks httplib2`, and `brew install go ninja coreutils esbuild typescript zstd quilt` | none |

`engine.yml` picks the newest installed SDK of the major version in `engine/macos-sdk-major` itself, and `configure` refuses any other, since the engine key covers that file; to move the engine to a new SDK major version, change it. On the owner's Mac, `.github/workflows/runner-check.yml` checks the Xcode version, the Metal toolchain, the SDK, Python and the Homebrew tools, and warns when free disk is low. Software Update can replace the Command Line Tools' SDKs; when the SDK changes, the engine build deletes `out/Default` and compiles from scratch. A clean engine build takes about 4 hours on an M1 Pro (see [Engine build times](#engine-build-times)).

GitHub's `macos-26` runner image has Xcode 26.6 at most, so CI jobs that build `ClairUI` use the `xcode-27` image (a public preview).

Then:

```sh
git clone --recurse-submodules https://github.com/clairbrowser/clair.git
cd Clair
./build.sh -s /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk   # fetch, prepare, configure and compile
```

The stages can also be run one at a time: `./build.sh fetch prepare`, then `./build.sh configure`, then `./build.sh compile`. Run `./build.sh -h` for the options. The app is built at `build/src/out/Default/`.

`prepare` refuses to run twice on the same source. Run `fetch` again to start from clean source. It re-clones only when the existing source has been modified.

### Updating a prepared tree in place

`engine.yml` builds in a workspace it keeps between runs, and passes `-k` so `prepare` keeps `build/base`: an APFS clone of the source as it is after ungoogled-chromium's patches and before Clair's. Cloning takes no extra disk space until files change. `./build.sh -k update` then brings a prepared tree up to date when only Clair's patches changed:

1. It clones `build/base` to `build/next` and applies Clair's layer there: `engine/patches/series`, the overlay, the UI string rebranding, the icon and logos, and domain substitution. A patch that doesn't apply stops the update before `build/src` changes.
2. It copies into `build/src` only the files whose contents differ, using the list of files the previous layer touched (`build/layer_files`) and the files the new one touched. Files that come out the same keep their modification times, so ninja rebuilds only the targets the change affects.

`update` starts from fresh source (`fetch prepare`) instead when the tree has no base, when the ungoogled-chromium pin, `engine/downloads*.ini` or `engine/retrieve_and_unpack_resource.py` changed, when an earlier update stopped partway, or when `build/base_key` is unreadable. The log names the reason, with the recorded and current base keys when they differ. `configure` deletes `out/Default` when the macOS SDK changes, so no objects compiled with the old SDK are linked into the new engine.

## Building the native layer

`ClairUI.framework`, Clair's Swift layer, builds with Xcode 27.2 or later and needs no Chromium checkout or engine:

```sh
xcodebuild -project native/ClairUI.xcodeproj -scheme ClairUI \
  -destination "platform=macOS,arch=arm64" build test
```

The scheme fetches Sparkle first, with `scripts/fetch-sparkle.sh`, into `build/sparkle`, which is where the project looks for `Sparkle.framework`.

Or open `native/ClairUI.xcodeproj` in Xcode. The project is in Xcode's JSON format (`project.xcproj`); don't add a `project.pbxproj`. Sources in `native/ClairUI/` and tests in `native/ClairUITests/` join their targets by being in those folders.

How updates work, and how to test them against a local appcast, is in [updates.md](updates.md).

`native/ClairHost.h` is the whole contract with Chromium. Swift imports it as the `ClairHost` module (`native/module.modulemap`). Chromium loads the framework, takes its principal class (`ClairUIMain`) and calls `+startWithHost:` with its host. The header is an engine input, so changing it needs a new engine; Swift sources aren't.

On the Chromium side, `engine/patches/clair/native-layer-hook.patch` calls `clair::StartNativeLayer()` once the main menu is built. The loader and Chromium's host live in `engine/overlay/chrome/browser/clair/`, and `prepare` copies `ClairHost.h` beside them (`engine/steps/install-native-contract.sh`). The engine looks for `Contents/Frameworks/ClairUI.framework`; a bare engine has none, logs `ClairUI: no framework at …` and runs without it.

## Packaging Clair.app

`package.sh` turns an engine into `Clair.app` and its DMG in about a minute, with no Chromium checkout:

```sh
gh release download chromium-engine-<key> -p '*.zip'
./package.sh Clair-Chromium-Engine-<key>-arm64.zip build/package
```

It builds `ClairUI` (or takes `--clairui <framework>`), fetches Sparkle with `scripts/fetch-sparkle.sh`, writes the version from `version.txt`, the build number from `git rev-list --count HEAD` and Sparkle's keys into `Info.plist`, signs every nested bundle inside out, and writes `Clair-<version>-arm64.dmg`. Without `--identity`, it signs ad hoc and without the hardened runtime: an ad hoc signature has no Team ID, so library validation would refuse every framework. Ad hoc packages are for testing on your own Mac. Remove the quarantine flag before opening one you downloaded. With `--identity` and an App Store Connect API key (`--notary-key`, `--notary-key-id`, `--notary-issuer`), it also notarizes and staples the app, then the DMG built from it. `./package.test.sh` checks it against a stand-in engine and stand-ins for Apple's tools.

The DMG is built with [`dmgbuild`](https://github.com/dmgbuild/dmgbuild), which writes the Finder window's layout into the volume's `.DS_Store` itself, so packaging runs headless, with no Finder scripting. Its settings, the layout, the background and their sources are in `resources/dmg/` (see its `README.md`): a fixed window with Clair on the left, Applications on the right and an arrow between them, and the app's own `app.icns` as the volume icon. `package.sh` installs `dmgbuild` with `scripts/fetch-dmgbuild.sh`, from hash-pinned wheels in `resources/dmg/requirements.txt` into a virtual environment in `build/dmgbuild/`, which needs `python3` 3.10 or later on `PATH` (or `DMGBUILD_PYTHON`). `--dmgbuild <path>` names one already installed. `./package.test.sh` mounts the DMG it builds and checks the layout against `resources/dmg/layout.json`.

## Running Clair locally

`scripts/run-local.sh` is the edit-to-run loop for `ClairUI` (design D15 of `replace-browser-window`). It never fetches or builds Chromium:

```sh
./scripts/run-local.sh                                  # package and launch
./scripts/run-local.sh -- --enable-logging=stderr https://example.com/
./scripts/run-local.sh --profile build/run-local/keep   # keep a profile between runs
```

1. It downloads `chromium-engine-<key>` for the checkout's engine key with `gh`, checks it against its SHA-256, and caches it in `build/run-local/engines/` (the three most recently used keys stay). If the key has no published engine, which happens when the branch changes an engine input, it stops and prints the `engine.yml` command that builds it.
2. It builds `ClairUI` in Debug, in a derived-data folder it keeps, so a one-line Swift change rebuilds in seconds, and packages ad hoc with `package.sh --no-dmg`.
3. It launches `Clair.app` in the foreground with a throwaway `--user-data-dir` under `build/run-local/profiles/`, `--use-mock-keychain`, and Crashpad's dumps in that profile. Your own `~/Library/Application Support/Clair` and the "Clair Safe Storage" keychain item are never touched, and `--profile` refuses a folder inside Clair's own data folder. Arguments after `--` go to Clair. When Clair quits, the throwaway profile is deleted and the package is unregistered from Launch Services, so `open` keeps finding your installed Clair. It also deletes the code-sign clones Chromium leaves in `$(getconf DARWIN_USER_TEMP_DIR)../X/com.clairbrowser.clair.code_sign_clone/` when it's stopped with Ctrl-C or crashes, several hundred MB each, apart from any a running Clair still uses (`scripts/clean-code-sign-clones.sh`). Clair's user defaults (the sidebar's width and state, Sparkle's state) are shared with an installed Clair, so the script saves them before the launch and puts them back afterwards; changes an installed Clair makes to them in the meantime are lost.

`--no-launch` packages only and prints the app's path. Sparkle still keeps its preferences in the `com.clairbrowser.clair` defaults domain, which the installed Clair shares; a local package's build number is higher than any release's, so it's never offered an update.

## Quality checks

`.github/workflows/quality.yml` runs after every merge to `main`. It runs the runtime suite in `tests/runtime/` as three parallel jobs on hosted runners, split by test class so each runs about the same time: app, updates, restore and shared tabs (`AppTests`, `UpdateMenuTests`, `IdleInstallTests`, `CertificateDataTests`, `RestoreTests`, `SharedTabsTests`, `CommandBarTests`); profiles, link rules and extensions (`ProfilesTests`, `LinkRulesTests`, `ExtensionActionTests`, `DialogTests`, `FullscreenTests`); and window, Spaces and pins, everything else, which skips the classes the other two name so a new class always runs. When a class grows or a new one lands, rebalance from a full run's per-class times (`Executed N tests … in S seconds` in each job's log). Each job downloads `chromium-engine-<key>` and packages the app ad hoc; the last also runs `scripts/verify-app.sh --skip-signing`. A push to `main` skips every job when a passed quality run already covers it (`scripts/find-quality-pass.sh`): one on a commit with the same file tree, or, when the push changes only documentation (`openspec/`, `docs/`, `.changes/` and root Markdown files), one that covers its parent. Squash-merging an up-to-date branch whose quality run passed has the branch's tree, so run the checks on the branch before merging and the merge costs nothing more. If there's no engine for the commit's key, it fails with "no engine for <key>" and the command to build it.

To run it on a branch, once `quality.yml` is on `main`:

```sh
gh workflow run quality.yml --ref <branch>
```

Add `-f report_issue=true` to report the result to the `quality-failure` issue, as a run on `main` does. Without it, only runs on `main` touch the issue. A failure opens the issue or comments on it, and a later pass closes it.

The suite covers the tests in design D12. `ClairRuntimeTests/` holds the XCUITest bundle, which drives the native UI through the accessibility APIs and reads page state over the Chrome DevTools Protocol. `tests/runtime/run.sh` prepares a package of the commit, a newer package to update to, the test appcasts signed with the test-only key (`docs/updates.md`), and a local web server. It retries a failed test once before the test counts.

`run.sh` runs on hosted runners by default, because the tests delete Clair's data directory, preferences and keychain item for the current user. It also runs on your Mac with `CLAIR_RUNTIME_DELETE_MY_DATA=1`, which says you're ready to lose your own Clair data. To debug a failure, read the failing test's message in the job log. A failed job's `runtime-results-updates` or `runtime-results-app` artifact has the result bundle, each launch's Clair log, the web server's log and Sparkle's log. To run part of the suite, pass xcodebuild's options through `run.sh test`, for example `-only-testing:ClairRuntimeTests/UpdateMenuTests`.

A few things in the suite look odd, for reasons that aren't obvious:

- **Launching:** XCUITest sees Clair only when it launches it with `XCUIApplication(url:)`. That handle doesn't follow a relaunch, so tests read the state after a relaunch over DevTools.
- **Failed steps:** tests never set `continueAfterFailure = false`. In an async test, that hangs until the test's time allowance runs out: 2 minutes, or 5 for the idle-install tests. Steps that later ones depend on call `require()`, which throws.
- **The test runner's sandbox:** Xcode sandboxes UI test runners by default, and `ClairRuntimeTests.entitlements` turns that off, so the tests can reset Clair's state.
- **Downloads:** ungoogled-chromium asks where to save every download, so the download test sets a folder over DevTools.

## Editing patches

Clair's patch series is `engine/patches/series`. Paths in it are relative to `engine/patches/`, and it is applied after ungoogled-chromium's own series, so that series has to be applied first. To edit or add a patch, use quilt (`brew install quilt`) on a fetched source tree:

```sh
./build.sh fetch
cd build/src
python3 ../../ungoogled-chromium/utils/patches.py apply . ../../ungoogled-chromium/patches
# QUILTRC=- skips quilt's own config, which would replace these settings.
export QUILTRC=- QUILT_PATCHES="$PWD/../../patches" QUILT_SERIES=series
export QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
quilt push -a       # apply Clair's patches one by one
```

To change an existing patch, go back to it, edit, and save the change. Use `quilt add <file>` first if the patch doesn't touch that file yet:

```sh
quilt pop clair/my-change.patch
# edit the file...
quilt refresh
```

To add a patch, start it where it belongs in the series. `quilt new` adds it to `engine/patches/series` after the current patch:

```sh
quilt new clair/my-change.patch
quilt add path/to/file.cc
# edit the file...
quilt refresh
```

`git diff engine/patches/` should show only your change, plus any hunk line numbers that quilt updated. Then rebuild the engine from a branch of this repository:

```sh
git switch -c fix/my-change
git add patches && git commit -m "fix: describe the change"
git push -u origin fix/my-change
gh workflow run engine.yml -f ref=fix/my-change
gh run list --workflow engine.yml --limit 1   # gives the run ID
gh run view <run ID> --log
```

The owner's Mac doesn't fetch Chromium by hand, because that's left to `engine.yml`. To write a patch there, read the engine workspace without changing it: the `build/` folder of the self-hosted runner's workspace, which a development machine sees through a read-only share. Diff against `build/base`, the source before Clair's patches. `build/src` has had name and domain substitution applied, so its context lines won't match.

## Adding new source files: the overlay

New Chromium source files go in `engine/overlay/`, at their paths in the Chromium tree, for example `engine/overlay/chrome/browser/clair/clair_host.mm`. `prepare` copies them in right after `engine/patches/series` (`engine/steps/apply-overlay.sh`). The overlay only adds files: one whose path already exists in Chromium, or that a patch creates, fails `prepare` and is named in the log. Changes to Chromium's existing files are patches. Wiring a new file into the build (a `BUILD.gn` dependency, a call site) is a patch too, so keep that patch to the hook and put the logic in the overlay.

## Updating the engine

A bot opens the pull request. `.github/workflows/engine-update.yml` checks [ungoogled-chromium-macos](https://github.com/ungoogled-software/ungoogled-chromium-macos)'s tags every 6 hours (`scripts/engine-update.sh`), since Clair needs that repository's files for a version. Each of its tags pins ungoogled-chromium as a submodule. When the newest one pins an ungoogled-chromium tag newer than `main`'s pin, the bot opens a draft pull request from the branch `engine-update` that moves the pin to that ungoogled-chromium tag and adds its release note (a Changie fragment of kind `Updated`, replacing any unreleased engine fragment on `main`), and nothing else. Its description says whether the update is patch-level or a new major, and links the ungoogled-chromium-macos tag it follows and that repository's changes since the tag of `main`'s pin. It never starts an engine build or merges.

- **One pull request at a time.** A newer tag, of the same major or the next, adds a commit on top of the branch, so fixes already pushed carry over, and the pull request returns to draft. Once the owner has started an engine build for the branch's pin (an `engine.yml` run titled `Engine: engine-update`, whatever its result), the pin is **held**: the bot leaves the branch alone and says in the description which newer tag it didn't take. Merge the pull request, and the next run opens one for the newer tag, or take it now with `gh workflow run engine-update.yml -f take-newest=true`.
- **Declining a tag.** Close the pull request without merging it. The bot opens no new one until a newer tag exists.
- **Draft and ready.** After each CI run on the pull request's head, `.github/workflows/engine-update-status.yml` (`scripts/engine-update-status.sh`) marks it ready for review when the patch check passed, and returns it to draft when it failed. One comment lists every Clair patch that doesn't apply, or gives the command that builds the engine. Push fixes to `engine-update`: each push re-runs the patch check, and the pull request turns ready by itself once every patch applies. Ready means the patches apply, not that the engine compiles.
- **Building.** Any pin change compiles Chromium from scratch on the owner's Mac (about 4 hours). Only the owner starts it, once the pull request is ready: `gh workflow run engine.yml -f ref=engine-update`.
- **The branch.** The bot never force-pushes, rebases or merges. When the pull request conflicts with `main`, GitHub runs no CI on it, and the description says so: merge `main` into the branch. If `engine-update` exists with no open pull request, the bot deletes it when every commit on it is the bot's, and otherwise stops and names it, for the owner to delete or rename.

A patch-level update usually needs nothing more. For a new major, or when the patch check names a macOS patch, sync the files copied from ungoogled-chromium-macos with the tag the pull request follows (see `CREDITS.md`), on the `engine-update` branch: `engine/downloads-arm64.ini`, `engine/retrieve_and_unpack_resource.py`, `engine/flags.macos.gn`, the patches in `engine/patches/ungoogled-chromium-macos/` (add and remove them in `engine/patches/series` as its own series does) and any change to the toolchain steps of its `build.sh` and `build_crubit.sh`, which `build.sh`'s `configure` stage ports. Update the commit in `CREDITS.md`. The pull request stays a draft until its patches are synced.

Every download in `engine/downloads*.ini` must declare a hash: `engine/retrieve_and_unpack_resource.py` refuses a file with a download that has none, before downloading anything, and `engine/steps/retrieve-and-unpack-resource.test.sh` checks the files in CI. Upstream pins no hash for `[rust]` and `[rustc-dev]`, so keep Clair's `sha256` lines when syncing and update them with the version: each is the one rust-lang publishes beside the archive, at its URL with `.sha256` appended.

Check the Xcode that ungoogled-chromium-macos's CI builds that tag with (`BASE_XCODE_PATH` in `.github/scripts/github_prepare_xcode.sh`): it is the newest SDK known to work with that Chromium. When its major version differs from `engine/macos-sdk-major`, set the file to it, or note in the pull request why Clair stays. Confirm the SDK version that Xcode ships rather than assuming it matches Xcode's, and that the runner has it: a new major version compiles the engine from scratch.

Fix the Clair patches the comment lists from the top, using ungoogled-chromium-macos's and Helium's updates as references: a skipped patch can make a later one that builds on it fail too.

To move the pin by hand instead, for a tag the bot doesn't follow (ungoogled-chromium-macos doesn't tag every version: of 157, it skipped `157.0.8103.38` and `157.0.8103.50`):

```sh
git -C ungoogled-chromium fetch --tags
git -C ungoogled-chromium checkout <new tag>
git add ungoogled-chromium
```

### The engine update App

A pull request opened with a workflow's own token starts no checks, and a workflow's own token can't change a pull request's draft state, so `engine-update.yml`, and `engine-update-status.yml` for the draft state only, act as a GitHub App, installed on this repository only, with the repository permissions "Contents: read and write" and "Pull requests: read and write". In the repository's settings, the `engine-update` environment holds its ID (the variable `ENGINE_UPDATE_APP_ID`) and private key (the secret `ENGINE_UPDATE_APP_PRIVATE_KEY`). Its deployment branches are limited to `main`, so only workflows running from `main` can make the App's token. `main`'s ruleset still requires the merge gate from the App, and the App has no access to the `release` environment. To replace the key, generate a new one in the App's settings, update the secret and delete the old key.

## Engine build times

Measured on the self-hosted Mac (M1 Pro, 32 GB, internal disk) for the first engine, `chromium-engine-70bf0b64d9e3cb3c` (Chromium 156.0.8078.73), on 2026-10-31:

| Stage | Time |
|---|---|
| Fetch, prepare and configure, with `build/download_cache` already filled | 9 min |
| Full compile from scratch, 57,495 ninja actions (rebuild of the same engine, 2026-10-31) | 3 h 58 min |
| Verify, smoke test, package and publish | about 1 min |
| A run whose engine is already published | 12 s |
| Fresh tree that also creates `build/base` (`fetch prepare configure compile` with `-k`, PR #17) | 3 h 48 min for the Build step, 3 h 50 min for the run |
| Patch fix in place (`update configure compile`: a one-line change to one `.cc` file, 2026-11-01) | 5 min 30 s for the Build step, 6 min 30 s from start to published |

In the patch-fix run, the update took about 1.5 minutes (`sync_tree: 6 copied, 0 removed, 1459 unchanged`). After its first action, ninja's restat cut the work to 14 steps: the changed object, the framework relink and the library checks. Besides the patched file, the sync copies `chrome/app/theme/chromium/mac/Assets.car`, which `actool` doesn't build byte for byte the same, and a few grit `__pycache__` files. Neither costs a noticeable rebuild.

## Engine workspace size

Measured with `du` in the same workspace after the full compile:

| Part | Size |
|---|---|
| `build/src` without `out/` (the prepared source, including 4.6 GB of LLVM, 1.8 GB of Rust toolchain and 1.4 GB of `.git`) | 18.8 GB |
| `build/src/out/Default` (7.4 GB of objects, 2.8 GB of dSYMs, the 0.37 GB `Clair.app`) | 18.2–19.3 GB |
| `build/download_cache` | 0.9 GB |
| Whole workspace | about 38 GB |
| Published engine zip | 164 MB |

`prepare` deletes the files in `build/download_cache` that neither ungoogled-chromium's `downloads.ini` nor `engine/downloads-arm64.ini` names any more (`engine/steps/prune-download-cache.py`), so the archives an engine update replaces, such as an old Rust nightly or Chromium source archive, don't pile up. Everything under `build/src/out` is deleted whenever `prepare` runs.

`build/base`, the pristine clone kept by `build.sh -k`, shares its blocks with `build/src` through APFS and adds only the files Clair's layer changes, but `du` counts it in full. `engine.yml` sizes the workspace without it and allows 50 GB for a fresh tree, plus the 30 GB reserve. That estimate is generous for an incremental build: when it refuses one, `gh workflow run engine.yml -f ref=<branch> -f skip_free_space_check=true` skips the check, and the build still stops if free space falls below 10 GB.

# Section 04: update and release chain

## What this section is

Everything between a commit and a running copy of Clair on someone's Mac, and then the next update to it. Sparkle 2 delivers updates: the Swift update files drive it, `clair_update_relaunch` and its patch let Chromium relaunch into a new version, `package.sh` embeds `ClairUI` and Sparkle, writes the version and Sparkle keys into `Info.plist`, signs and builds the DMG, and the release scripts publish it and append to `.sparkle/appcast.xml`, which is served straight from `main`. The six workflows build, test and release; the engine is built on the owner's self-hosted Mac.

Whoever controls this chain controls every installed copy. It is also the section with the most things that freeze at first release: the signing identity, the Sparkle key and the feed URL cannot be changed for existing users afterwards.

## Specs to judge against

`openspec/specs/software-updates`, `release-distribution`, `build-pipeline` and `app-identity`, plus `docs/releasing.md` and `docs/updates.md`.

## Where to look in the engine tree

Little is needed. Check what `update-relaunch-hook.patch`, `versioning.patch` and `branding.patch` change, starting from the files they name, mostly under `chrome/browser/` and `chrome/app/`.

## What to establish

**Update integrity**
- What does an installed Clair verify before installing an update: the EdDSA signature, the code signature, both? Is there any path (deltas, the test appcast, a configuration override, a debug build setting) that installs without the check?
- The feed is a file on `main`. Who and what can change it: which workflows write it, with what token, behind which branch protection? Could a pull request, a compromised action or a workflow with write permission publish an appcast entry?
- Can the feed or a download be downgraded, replayed or redirected? Is everything fetched over HTTPS with no fallback?
- Where does the Sparkle private key live, which jobs can read it, and is the public key in the repository the one `package.sh` embeds?

**The pipeline as an attack surface**
- For each workflow: its triggers, its `permissions`, the secrets and environments it can reach, and whether every third-party action is pinned to a commit. Flag `pull_request_target`, untrusted input interpolated into `run:` steps, and artifacts or caches that flow from an untrusted job into a trusted one.
- `CLAUDE.md` states that the self-hosted Mac never runs pull-request jobs and that release secrets never reach engine builds or quality checks. Verify both against the workflow files rather than taking them as given.
- The engine is built once and cached as a prerelease keyed by `scripts/engine-key.sh`. What stops a tampered or stale engine from being packaged into a release, and is the engine artifact's integrity checked when it is downloaded?
- The engine tree you read from may sit inside a CI runner's working directory, in which case the runner's registration files are within reach of the review machine. Do not open them. Do assess the arrangement: what those files would allow, and what else can read that location.

**Patch lag**

A browser is only as safe as its engine is recent: Chromium ships security fixes every week or two, and their details become public soon after. `Upstream versions` in your dispatch message names a file with recent ungoogled-chromium releases and their dates; `run.md` gives the Chromium version under review.

- How far behind is the reviewed engine, in versions and in days?
- Trace a Chromium security release to an installed copy of Clair, step by step: the ungoogled-chromium tag, the submodule bump, the patch check, the engine build, the quality checks, the release, Sparkle's next check, the install and the relaunch. For each step say who or what starts it, how long it takes, and what it waits on. Which steps need the owner, and which need the one self-hosted Mac? What is the shortest possible time end to end, and what would it realistically be?
- What notices that a new upstream release exists? If the answer is the owner happening to look, say so.
- Clair follows ungoogled-chromium, which follows Chromium, and copies build patches from ungoogled-chromium-macos, which the file shows releasing later still. What happens when one of them is late or stops? Could Clair move to a newer Chromium on its own, and what would that take?
- Which of Clair's patches are most likely to stop applying on a bump, judged by their size and the code they touch? Each is a delay on the day a fix is needed. Section 07 reviews the patch series; report what you see from the release side.
- Can a release that carries only an engine update ship while `main` holds half-finished work or the quality checks are failing for an unrelated reason? Is there a path for it, or does a security fix wait for `main` to be releasable?
- After a release is published, how long until an installed copy runs it: the update check interval, what the idle installer waits for, and whether a user who never quits is ever moved to the new version?
- The same questions, briefly, for what else is bundled or fetched at build time: Sparkle, the toolchains in `engine/downloads-arm64.ini`, and the pinned GitHub actions.
- Does any spec state how quickly an engine fix must reach users? If none does, that is a finding for section 08 as well.

**Signing and entitlements**
- Read the four entitlement files against what each process needs. Which entitlements weaken the hardened runtime (JIT, unsigned executable memory, disabled library validation, DYLD variables), and is each one necessary for that process?
- `ClairUI` is a framework Chromium loads at start-up. What ensures only the signed framework from the bundle is loaded?
- What do `verify-app.sh` and `release-preflight.sh` actually check, and what would they miss?

**Scripts**
- The release scripts build XML and shell from inputs such as versions and release notes. `CLAUDE.md` requires validating those. Check each input that reaches the appcast, a plist or a command line.
- Are failures loud? Look for steps that can fail and still publish.

# Section 07: build and test infrastructure

## What this section is

How the engine gets built and how Clair gets tested. `build.sh` stages the Chromium build (`fetch`, `prepare`, `configure`, `compile`); `retrieve_and_unpack_resource.py` and `downloads-arm64.ini` fetch toolchains; `utils/` and the engine scripts apply patches, the overlay and the branding; `patches/series` orders the patches. The GN flag files and the build patches copied from ungoogled-chromium-macos belong to section 09, which reviews them for what they do to Chromium's hardening. `tests/runtime` is the runtime suite (XCUITest plus the Chrome DevTools Protocol) that the quality workflow runs after every merge, and `tests/probe` is hand-driven tooling for comparing Clair with Arc.

Two things make this section worth the time. The build fetches and runs third-party binaries, so it is a supply-chain surface. And the runtime suite has become the slowest part of the development loop, which the owner wants diagnosed.

## Specs to judge against

`openspec/specs/build-pipeline` and `chromium-engine`, plus `docs/building.md`. The workflow files belong to section 04; read `quality.yml` and `ci.yml` to understand how the tests are run, and send security observations about them there.

## Where to look in the engine tree

Only to confirm what a build script produces.

## What to establish

**Build and supply chain**
- Every download: is it pinned to a version and checked against a hash before anything is unpacked or run? What happens on a mismatch? Are any toolchains fetched from a personal or third-party release page, and what would a compromise of that source give an attacker?
- Unpacking: can an archive write outside its target directory?
- Is the engine key complete? `scripts/engine-key.sh` hashes the engine's inputs. Look for a file that changes the built engine and is not in the manifest, since that would let a stale engine pass as current.
- Is the patch series minimal and ordered so that a failure is easy to place when the engine is bumped? Section 04 asks how fast a Chromium security fix can reach users, and a patch that is hard to rebase is part of the answer. Which of Clair's own patches would be better as overlay files, given the rule that patches are for build fixes, identity, versioning and hooks only?
- Script quality: unquoted expansions, unchecked exit codes, inputs that reach `eval`, XML or a command line unvalidated, and Bash 4 or GNU-only constructs in scripts that must run on Bash 3.2 with BSD tools. Does each script's test exercise its failure paths?

**The cost of the runtime suite**

`timings.txt` in the run directory lists each test's duration from a recent quality run, slowest first, with a total per test class. The suite takes most of half an hour and grows with every feature. Work out where the time goes and what would cut it, without proposing to delete coverage that matters.

- Read the slowest tests and the harness. What does each test spend its time on: launching and relaunching the app, fixed sleeps, waiting on timeouts that only expire, repeated set-up that could be shared?
- Which tests exist to check logic that `FakeBrowser` and `FakeHost` could express, and so could run as unit tests in seconds? Which genuinely need a running browser?
- Where do two tests, or a runtime test and a unit test, check the same behaviour?
- The suite already runs as two jobs. How could it be split further so that classes run in parallel, and what shared state (the user's Clair data, the keychain item, ports, the page server) stands in the way?
- Which tests are likely to fail intermittently, judged from the code: timing assumptions, reliance on animation, order dependence, leftover state from a previous test?
- Give a ranked list of changes with a rough estimate of the minutes each would save.

**The test tooling**
- `tests/runtime/run.sh` deletes the current user's Clair data, keychain item and preferences. How well is that guarded against being run by accident on a developer's machine?
- The page servers and `make-crx.py`: anything that binds beyond localhost, or that would be unsafe if left running?
- Is the probe tooling still in step with the app, or has it drifted?

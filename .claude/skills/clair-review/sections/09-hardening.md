# Section 09: engine hardening

## What this section is

Chromium ships with layers of exploit mitigation: the sandbox, site isolation, control-flow integrity, the V8 sandbox, a hardened allocator, and security data that is refreshed between releases. Clair's engine is that Chromium after three sets of changes it did not write (ungoogled-chromium's patches and flags, the build patches copied from ungoogled-chromium-macos, the patches adapted from Helium) and one it did (`engine/patches/clair/` and `engine/overlay/`). Each of those was made for another reason: removing Google services, getting the build to pass, adding a feature. This section asks what they cost in hardening along the way.

The files that are yours are small: the two GN flag files and the copied macOS build patches. The work is in the engine tree. You are the only reviewer who looks at every patch, and you look at each for one thing only. The other sections review their patches for what they do; you review all of them for what they weaken.

Nobody chose most of what you will find. A mitigation that is off because a flag was copied from another project, or because the service that switches it on was removed, is the finding this section exists for.

## Specs to judge against

`openspec/specs/chromium-engine` and `build-pipeline`, plus `docs/building.md`. Expect them to say little about hardening. Where a mitigation is off and no spec or document records the decision, that silence is part of the finding.

## Where to look in the engine tree

- `out/Default/args.gn` under `engine_src`: the arguments the engine was configured with. This one file is the exception to the rule about leaving `out/` alone. Read nothing else there.
- `flags.gn` and `patches/` at `ungoogled_src`, with its `patches/series` for the order.
- The defaults of every argument you assess, in `build/config/` (especially `compiler/`, `sanitizers/` and `mac/`), `build_overrides/`, `v8/gni/v8.gni` and `v8/BUILD.gn`, `base/allocator/partition_allocator/`, and `build/config/c++/`. Take what stock Chrome ships from these files and never from memory: defaults differ by platform and architecture and change between milestones, and a statement about them is a finding like any other, so cite the line.
- `sandbox/mac/`, `sandbox/policy/mac/` (the `.sb` profiles), `content/browser/` for site isolation and `ChildProcessSecurityPolicy`, and `chrome/app/` and `content/app/` for process start-up.
- `testing/variations/fieldtrial_testing_config.json` for features that are enabled by server configuration.

`Upstream versions` in your dispatch message names a file listing recent ungoogled-chromium releases with their dates. Section 04 owns the question of how fast Clair follows them; use the file only to say how old the reviewed engine is.

## What to establish

**Build settings**
- For each mitigation that is decided when the engine is compiled, give the value in Clair's build, the value an official Chrome build for Apple Silicon Macs would have, and where the difference comes from. Cover at least: `is_official_build` and what it implies, control-flow integrity (`is_cfi` and its cast and indirect-call variants) and arm64 pointer authentication and branch protection, the V8 sandbox, pointer compression and V8's own control-flow integrity, PartitionAlloc as the allocator with BackupRefPtr and its dangling-pointer checks, libc++ hardening, stack protection and automatic initialisation of locals, `DCHECK` and iterator-debugging settings, and the Rust toolchain settings that `fix-build-with-rust.patch` and `set-rustc-nightly-capability.patch` change.
- Which flags in `engine/flags.macos.gn` exist only because another project needed them? `fatal_linker_warnings=false`, `enable_iterator_debugging=false`, `use_sysroot=false` and `v8_use_metagen=false` each need a reason that holds for Clair.
- Does `gn gen --fail-on-unused-args` in `build.sh` mean a misspelt or retired hardening argument fails the build, or can one be silently ignored?

**The process model**
- Does any patch, GN argument, command-line switch or feature default change the sandbox: the Seatbelt profiles, the points where each process type enters the sandbox, any path that starts a process unsandboxed?
- Is site isolation in its stock configuration: full site isolation, origin isolation for the cases Chrome isolates, and the `ChildProcessSecurityPolicy` checks intact? ungoogled changes default flags and features; follow each one that touches process allocation.
- `ClairUI` is loaded at start-up. In which process types is it loaded, and in each, before or after the sandbox is entered? A Swift framework initialised in a renderer or a utility process would be code running there that Chromium's sandbox profile was not written for.
- Clair holds hidden browser windows and opens peeks. Does anything it does force two sites or two profiles into one renderer process, or reuse a process across a boundary Chromium would have kept?

**Features that arrive by server configuration**
- Chrome turns many security features on through field trials before their default changes in code. ungoogled removes that channel. Using the testing configuration and the feature definitions, list the security-relevant features that are default-off in this tree and on for Chrome's users, and say which Clair should enable itself.

**Security data that is refreshed between releases**
- With the component updater, Safe Browsing and Google's endpoints gone, what does the user lose, and what is frozen at the day the engine was built? Go through at least: the certificate revocation set, certificate transparency log lists and their enforcement when the list goes stale, the root store, the extension blocklist, the subresource filter and safety-tip data, download protection, and password-leak checks. For each: absent, frozen at build time, or still working, and what an engine that is some weeks old then gets wrong.
- `fix-disabling-safebrowsing.patch` finishes a removal that ungoogled starts. Does it remove only what was intended?

**Every patch, for its hardening effect**
- Walk ungoogled's series and then `engine/patches/series` in the order they are applied. For each patch, say in a line whether it touches anything security-relevant: `sandbox/`, `content/` security checks, certificate verification or `net/`, V8, the allocator, compiler or linker flags, crash reporting, permission or policy code. Read in full the ones that do.
- Name these in particular: `revert-v8-sanitizer-changes.patch`, `disable-crashpad-handler.patch`, `disable-clang-version-check.patch`, `disable-symbol-order-verification.patch`, `no-unknown-warnings.patch` and `add-local-network-usage-description.patch`. What does each revert or disable, and is a check that guarded against something now gone?
- The copied macOS patches need provenance as well: confirm each keeps its original header, and flag any that does more than fix the build.
- A patch owned by another section is still yours for this question. Report what it weakens here, and leave what it does to its owner.

**Privileged pages and bindings**
- `CLAUDE.md` says Clair uses WebUI only for Chromium's internal pages. Verify it. Across `engine/overlay/` and every Clair and Helium patch, list anything that adds or changes a `chrome://` page, a `WebUIController` or message handler, a Mojo interface a renderer can reach, a binder registration, or a script injected into pages. `first-run-page.patch`, the two logo-icon patches and `chrome-webstore.js` are the known candidates; section 03 reviews the store script in detail, so state only what privileges it runs with and who can reach it.
- Which origins can reach each of those, and does any accept input from ordinary web content?
- Can web content cause a `chrome://`, `file:` or extension page to load in a surface Clair added (a peek, a pinned item, an extension popup window, a link opened from another app), and does such a page then keep the restrictions Chromium applies to it in a normal tab?

**What only a running build can show**

This review reads source. Arguments say what was asked for, and some of what matters can only be seen in the built app: that each process type is sandboxed, which site-isolation mode is in force, which entitlements and hardened-runtime flags the signed bundle and each helper carry. For each claim you could not settle from the tree, say so under "Limits", and recommend the check that would settle it for good: a test in `tests/runtime` (it drives the app through the DevTools protocol and can read `chrome://` pages), or an assertion in `scripts/verify-app.sh`. Section 04 owns the entitlement files and section 07 the runtime suite; address the recommendation to them under "Questions for other sections".

## Reporting

Use the standard format. Under "Architecture notes", give the result as one table: the mitigation, stock Chrome on this platform, Clair, and the cause of any difference (an ungoogled flag or patch, a copied macOS patch, a Clair choice, a removed service). Mark each difference as recorded in a spec or document, or unrecorded. The synthesis pass copies this table into the final report.

A mitigation that is off is a finding even when no exploit is shown; `report-format.md` says how to rate it.

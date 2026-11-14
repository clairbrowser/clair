# Section 03: extensions and the web store

## What this section is

ungoogled-chromium removes the Chrome Web Store integration and the extension update machinery on purpose. Clair puts part of it back: `restore-web-store.patch` and the `clair_store_fixups` component (adapted from Helium) make the store usable again, `clair_extensions.mm` exposes extensions to the native interface, and the Swift files draw the extensions menu, pinned extensions, popups and the install and permission prompts.

Extensions are the most privileged third-party code a browser runs, and this section re-opens paths that the upstream project closed. It is small, which also makes it the pilot: the report here calibrates the format and the cost for the rest of the review.

## Specs to judge against

`openspec/specs/extensions`.

## Where to look in the engine tree

Start from the files the three patches touch. Expect to need `chrome/browser/extensions/` (especially `api/webstore_private/` and the install prompt code), `extensions/browser/`, `extensions/common/extension_urls.*`, and `components/clair_store_fixups/` as built. ungoogled's own patches are under `patches/` at the `ungoogled_src` path in `run.md`; read the ones that remove store and update support to see exactly what Clair re-enables. Remember that Google domains in the tree are rewritten by domain substitution, which matters for any URL matching here.

## What to establish

**What was re-enabled**
- List precisely which capabilities come back: installing from the store, the `webstorePrivate` API, update checks, anything else. For each, which origins can use it and how is that origin decided?
- `chrome-webstore.js` runs in store pages. What does it change, with what privileges, and what does it trust from the page? Could a page that is not the store, or content injected into the store, drive it?
- How do the extension IDs in `extension_ids.h` gain their privileges, and can another extension claim one of those IDs?

**Installation and updates**
- Follow an install from click to enabled extension. Where is the package's signature and ID checked, and does any Clair or ungoogled change weaken a check that Chromium normally makes?
- Do installed extensions update? If they do, over what channel and with what verification; if they do not, users keep running extensions with known vulnerabilities, which is its own finding.
- Compare the native install and permission prompts with Chromium's own. Does the user see the same permissions and the same warnings, can web content or an extension's own name and icon mislead the prompt, and can a prompt be accepted by a click the user did not mean?

**The native extension surface**
- Extension popups are shown in a native window. Which `WebContents` hosts them, does the popup keep the isolation and the lifetime Chromium gives it, and what happens when the extension is disabled, updated or uninstalled while its popup is open?
- With window groups, an extension sees the hidden per-profile browser windows through `chrome.windows`. What can it do to them?
- `no-extension-uninstall-page.patch` removes behaviour. Check what else used the code it disables.

**Quality**
- Is extension state held once, or copied between `clair_extensions.mm` and the Swift views?
- What do `tests/runtime/extensions/` and `ExtensionPromptTests`/`ExtensionsMenuTests` cover, and what security-relevant behaviour above has no test?

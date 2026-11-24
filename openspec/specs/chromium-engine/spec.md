# chromium-engine Specification

## Purpose

Defines Clair's engine baseline. Clair is a build of a specific ungoogled-chromium release with that release's privacy defaults and feature removals intact, and it can move to any newer ungoogled-chromium release on its own schedule.

## Requirements

### Requirement: Built from a pinned ungoogled-chromium release
Each Clair build SHALL come from exactly one tagged ungoogled-chromium release, with its full patch series, binary pruning and domain substitution applied, and SHALL record the tag in its source tree. The one exception is a list in Clair's source of files that domain substitution leaves out. It SHALL hold only files that name the Chrome Web Store's addresses, its update responses' XML namespace or Google's update service's address, for services "Google services Clair turns back on" allows.

#### Scenario: Engine release is identifiable from source
- **WHEN** the Clair source at a release tag is inspected
- **THEN** it identifies exactly one ungoogled-chromium tag, for example `156.0.8078.47-1`, as the engine the release was built from

#### Scenario: Patch that does not apply fails the build
- **WHEN** any ungoogled-chromium, macOS or Clair patch fails to apply cleanly during a build
- **THEN** the build stops with an error naming the patch and produces no app bundle

#### Scenario: Files left out of domain substitution
- **WHEN** the list of files that domain substitution leaves out is read
- **THEN** every file on it names the Chrome Web Store's addresses, the XML namespace of its update responses, or the update service's address and nothing else, and a file on it that no longer exists in ungoogled-chromium's substitution list stops the build with an error naming it

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, the default search engine and search suggestions that `search-engine` specifies, and the Google services that "Google services Clair turns back on" allows. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked and preload pages disabled, except that Clair's default search engine is Google and its search suggestions are on

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** its only requests to Google are the certificate data check to Google's update service and the downloads it points to, and none go to Safe Browsing, sync, sign-in, metrics, extension updates, variations servers or Google Search, including no preconnection to the search engine

#### Scenario: Google contacted only for store extensions
- **WHEN** the user has installed an extension from the Chrome Web Store
- **THEN** Clair contacts Google's extension servers and its extension update service only to download that extension and to check it for updates, and contacts no other Google service besides the certificate data check

#### Scenario: Component updater stays off
- **WHEN** a profile with store extensions has run its extension update checks
- **THEN** those checks named only extensions, and Clair has made no component update check besides the certificate data check

#### Scenario: Component updater checks only the revocation list
- **WHEN** Clair has run its component update checks
- **THEN** each check named only the certificate revocation list and the PKI metadata component, and no other component was checked, downloaded or updated

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from what Clair's own capabilities specify (`app-identity`, `native-layer`, `software-updates`, `browser-window`, `sidebar`, `command-bar`, `spaces`, `profiles`, `link-rules`, `extensions`) and the password and autofill features it turns off, Clair SHALL behave as its ungoogled-chromium release: page rendering, settings, `chrome://` pages, each profile's data, history, extensions' APIs, and the menus and shortcuts the native window keeps.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions, and the absent "Autofill and passwords" and "On startup" sections

#### Scenario: Links from other apps without rules
- **WHEN** Clair has no link rules and a link arrives from another app
- **THEN** it opens where the same ungoogled-chromium release would open it

### Requirement: Changes to Chromium limited to hooks and identity
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, hooks, the Google services "Google services Clair turns back on" allows (restoring their code, routing their requests through it and limiting what they send), and the search defaults `search-engine` specifies. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `engine/patches/clair/` and `engine/patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, a hook, the store and update restoration, or the default search engine and its suggestions, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing the store restoration
- **WHEN** a patch that restores a Google service is read
- **THEN** the service is on "Google services Clair turns back on"'s list, and each hunk puts back code that ungoogled-chromium's patches removed for it, routes its requests through that code, or removes data from what it sends, and adds no other behavior

### Requirement: What Clair's Chromium hooks may do
Each of Clair's hooks SHALL only redirect to Clair's code or switch a Chromium feature off. The hooks load the native layer, hand browser windows and extension alerts to Clair, register its component extensions and preferences, tag its tabs in saved sessions, free its shortcuts, turn off or hide passwords, autofill and extensions' uninstall pages, restore the last session by default, and offer links from other apps to its link rules first.

#### Scenario: Reviewing a window hook
- **WHEN** a hunk of the native-window hook patch is read
- **THEN** it calls into Clair's overlay files or the native layer, makes Chromium skip UI the native window replaces, or switches off a feature Clair removes, and any behavior is in Clair's files

#### Scenario: Reviewing a session hook
- **WHEN** a hunk of a patch to Chromium's session code is read
- **THEN** it calls into Clair's overlay files to write or read a tag on a tab, and decides nothing itself

#### Scenario: Reviewing the link rules hook
- **WHEN** the hunk that hooks links from other apps is read
- **THEN** it hands each link to Clair's overlay files and opens only the links they leave, as Chromium would, and decides nothing itself

#### Scenario: Reviewing the extension alert hook
- **WHEN** the hunk that hooks Chromium's blocklisted-extension alert is read
- **THEN** it hands the alert to Clair's overlay files, and decides nothing itself

### Requirement: Engine updates without third-party macOS packaging
Clair SHALL be able to move to any newer ungoogled-chromium release tag without waiting for a matching `ungoogled-chromium-macos` release. Moving to a new tag SHALL only require changing the pinned engine tag, plus adjusting a macOS or Clair patch where one no longer applies.

#### Scenario: Security patch release
- **WHEN** ungoogled-chromium publishes a new patch-level tag for the Chromium major version Clair already uses, and all of Clair's patches still apply
- **THEN** a Clair release on that tag can be produced by changing only the pinned engine tag, with no other source changes

### Requirement: Passwords and autofill turned off
Clair SHALL NOT offer to save passwords and SHALL NOT fill saved passwords, addresses or payment methods into pages, whatever the profile's earlier settings were. The "Autofill and passwords" section of `chrome://settings` SHALL be hidden. Passwords saved before this change SHALL stay in the profile and viewable at `chrome://password-manager`, so the user can export them to a password manager.

#### Scenario: Signing in to a site
- **WHEN** the user submits a sign-in form with a username and password
- **THEN** Clair offers no prompt to save the password, and none is saved

#### Scenario: Filling an address form
- **WHEN** the user focuses an address field in a form, in a profile that has saved addresses
- **THEN** no autofill suggestions appear

#### Scenario: Settings page
- **WHEN** the user opens `chrome://settings`
- **THEN** it has no "Autofill and passwords" section

### Requirement: Google services Clair turns back on
Clair SHALL turn back on a Google service that ungoogled-chromium removes or disables only if it is the Chrome Web Store, a feed that protects users from harm, or Google Search with its suggestions, and only through a change that adds it to this requirement's list. Each service SHALL send Google only what it needs to work, with no usage, activity, device or identifying data beyond the cookies `search-engine` allows.

#### Scenario: The services Clair turns back on
- **WHEN** the Google services Clair turns back on are listed
- **THEN** they are the Chrome Web Store's pages and installs, store extension update checks with the flags they return, Chromium's certificate revocation list (CRLSet), Chromium's PKI metadata component (the CT log list, static key pins and Chrome Root Store), and Google Search with its search suggestions, and nothing else

#### Scenario: Proposing another service
- **WHEN** a change proposes turning on another Google service that ungoogled-chromium removes
- **THEN** the service is the store's or protects users from harm, the change says what each request sends and why each field is needed, and it adds the service to "The services Clair turns back on"

#### Scenario: A convenience service
- **WHEN** a Google service would only add convenience, such as sync, sign-in, translation, field trials, downloading media components, or Google Search's other features such as Lens, the doodle or the new tab page's search box
- **THEN** this requirement doesn't allow it, and turning it on needs a change that amends this requirement first

#### Scenario: What a turned-on service sends
- **WHEN** a request from a service on the list is captured
- **THEN** it carries only the fields its change named, and no install or device identifiers, usage pings or hardware and OS details beyond the platform and architecture

### Requirement: Certificate revocation data kept current
Clair SHALL fetch Chromium's certificate revocation list (CRLSet) from Google's update service about a minute after launch and every five hours after that, as Chrome does, and SHALL apply the newest list it has to every certificate it verifies. It SHALL keep the last list it fetched, and use it from launch, until a newer one arrives.

#### Scenario: A revoked intermediate
- **WHEN** a site's certificate chains through an intermediate certificate that the current list revokes
- **THEN** Clair refuses the connection with Chromium's revoked-certificate error, as Chrome does

#### Scenario: First launch
- **WHEN** Clair is launched for the first time and has a network connection
- **THEN** it has fetched the list and applies it within a few minutes, with no user action

#### Scenario: Offline
- **WHEN** Clair has fetched a list before and is launched with no network connection
- **THEN** it applies the list it has

### Requirement: Certificate transparency and key pins kept current
Clair SHALL fetch Chromium's PKI metadata component in the same check as the certificate revocation list, and SHALL apply its Certificate Transparency log list, static key pins and Chrome Root Store when they're newer than the engine's own. It SHALL keep the last component it fetched, and use it from launch, until a newer one arrives.

#### Scenario: An engine older than 10 weeks
- **WHEN** Clair runs on an engine whose compiled-in CT log list and pins are more than 10 weeks old, and it has fetched the current component
- **THEN** it still requires CT for publicly trusted certificates and still enforces the static key pins, as Chrome does

#### Scenario: A certificate that isn't logged
- **WHEN** a site presents a publicly trusted certificate with no proof that it was logged in CT
- **THEN** Clair refuses the connection with Chromium's CT error

#### Scenario: A pinned domain
- **WHEN** a site on the static pin list presents a certificate from an authority its pins don't allow
- **THEN** Clair refuses the connection with Chromium's pinning error

#### Scenario: First launch
- **WHEN** Clair is launched for the first time and has a network connection
- **THEN** it has fetched the component and applies it within a few minutes, with no user action

#### Scenario: Offline
- **WHEN** Clair has fetched the component before and is launched with no network connection
- **THEN** it applies the component it has

### Requirement: HSTS preload list enforced at any age
Clair SHALL enforce the HSTS preload list compiled into its engine however old the engine is.

#### Scenario: An engine older than 10 weeks
- **WHEN** Clair runs on an engine built more than 10 weeks ago, and the user opens `http://` on a domain in the preload list
- **THEN** Clair loads it over HTTPS without sending a plain-HTTP request, as Chrome does with a current build

#### Scenario: A certificate error on a preloaded domain
- **WHEN** a domain in the preload list presents an invalid certificate, whatever the engine's age
- **THEN** Clair's certificate error offers no way to proceed

### Requirement: What a certificate data check sends
A certificate data check SHALL send only each component's ID and version, the hash of the package Clair has for it, Clair's Chromium version and channel, the platform and architecture, and random per-request IDs, over HTTPS only. Both components SHALL share one request. It SHALL NOT send the language or any field "What a store update check sends" in `extensions` rules out, and Clair SHALL send no report after a component installs.

#### Scenario: Reading a revocation check
- **WHEN** a certificate data check is captured
- **THEN** its body names the revocation list's and the PKI metadata component's IDs and versions, the Chromium version and channel, `mac` and `arm64`, and nothing this requirement rules out

#### Scenario: Plain HTTP refused
- **WHEN** Google's update service answers with download addresses over both HTTP and HTTPS
- **THEN** Clair downloads each component over HTTPS only, and makes no check over plain HTTP

#### Scenario: List updated as a patch
- **WHEN** Clair has a component and a newer one is published
- **THEN** Clair downloads a patch to the version it has when Google offers one, or the full component when it doesn't

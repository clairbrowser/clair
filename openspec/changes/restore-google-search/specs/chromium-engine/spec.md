# Spec Delta

## MODIFIED Requirements

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

### Requirement: Changes to Chromium limited to hooks and identity
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, hooks, the Google services "Google services Clair turns back on" allows (restoring their code, routing their requests through it and limiting what they send), and the search defaults `search-engine` specifies. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `patches/clair/` and `patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, a hook, the store and update restoration, or the default search engine and its suggestions, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing the store restoration
- **WHEN** a patch that restores a Google service is read
- **THEN** the service is on "Google services Clair turns back on"'s list, and each hunk puts back code that ungoogled-chromium's patches removed for it, routes its requests through that code, or removes data from what it sends, and adds no other behavior

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

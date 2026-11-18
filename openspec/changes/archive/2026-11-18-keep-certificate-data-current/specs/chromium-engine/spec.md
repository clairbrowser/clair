# Spec Delta

## ADDED Requirements

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

## RENAMED Requirements

- FROM: `### Requirement: What a revocation check sends`
- TO: `### Requirement: What a certificate data check sends`

## MODIFIED Requirements

### Requirement: Google services Clair turns back on
Clair SHALL turn back on a Google service that ungoogled-chromium removes or disables only if it is the Chrome Web Store or a feed that protects users from harm, such as flags on malware extensions or certificate revocation data. It SHALL do so only through a change that adds the service to this requirement's list. Each service SHALL send Google only what it needs to work, and no usage, activity, device or identifying data.

#### Scenario: The services Clair turns back on
- **WHEN** the Google services Clair turns back on are listed
- **THEN** they are the Chrome Web Store's pages and installs, store extension update checks with the flags they return, Chromium's certificate revocation list (CRLSet), and Chromium's PKI metadata component (the CT log list, static key pins and Chrome Root Store), and nothing else

#### Scenario: Proposing another service
- **WHEN** a change proposes turning on another Google service that ungoogled-chromium removes
- **THEN** the service is the store's or protects users from harm, the change says what each request sends and why each field is needed, and it adds the service to "The services Clair turns back on"

#### Scenario: A convenience service
- **WHEN** a Google service would only add convenience, such as sync, sign-in, translation, field trials or downloading media components
- **THEN** this requirement doesn't allow it, and turning it on needs a change that amends this requirement first

#### Scenario: What a turned-on service sends
- **WHEN** a request from a service on the list is captured
- **THEN** it carries only the fields its change named, and no install or device identifiers, usage pings or hardware and OS details beyond the platform and architecture

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, and the Google services that "Google services Clair turns back on" allows. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** its only requests to Google are the certificate data check to Google's update service and the downloads it points to, and none go to Safe Browsing, sync, sign-in, metrics, extension updates or variations servers

#### Scenario: Google contacted only for store extensions
- **WHEN** the user has installed an extension from the Chrome Web Store
- **THEN** Clair contacts Google's extension servers and its extension update service only to download that extension and to check it for updates, and contacts no other Google service besides the certificate data check

#### Scenario: Component updater stays off
- **WHEN** a profile with store extensions has run its extension update checks
- **THEN** those checks named only extensions, and Clair has made no component update check besides the certificate data check

#### Scenario: Component updater checks only the revocation list
- **WHEN** Clair has run its component update checks
- **THEN** each check named only the certificate revocation list and the PKI metadata component, and no other component was checked, downloaded or updated

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

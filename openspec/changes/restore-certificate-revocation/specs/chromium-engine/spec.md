# Spec Delta

## MODIFIED Requirements

### Requirement: Built from a pinned ungoogled-chromium release
Each Clair build SHALL come from exactly one tagged ungoogled-chromium release. That release's full patch series, binary pruning and domain substitution SHALL be applied, and the tag SHALL be recorded in the Clair source tree. The only exception is a list kept in Clair's source of files that domain substitution leaves out. It SHALL hold only files that name the Chrome Web Store's addresses, the XML namespace of its update responses, or the address of Google's update service, for the services "Google services Clair turns back on" allows.

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
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, and the Google services that "Google services Clair turns back on" allows. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** its only requests to Google are the certificate revocation check to Google's update service and the download it points to, and none go to Safe Browsing, sync, sign-in, metrics, extension updates or variations servers

#### Scenario: Google contacted only for store extensions
- **WHEN** the user has installed an extension from the Chrome Web Store
- **THEN** Clair contacts Google's extension servers and its extension update service only to download that extension and to check it for updates, and contacts no other Google service besides the certificate revocation check

#### Scenario: Component updater stays off
- **WHEN** a profile with store extensions has run its extension update checks
- **THEN** those checks named only extensions, and Clair has made no component update check besides the certificate revocation list's

#### Scenario: Component updater checks only the revocation list
- **WHEN** Clair has run its component update checks
- **THEN** each check named only the certificate revocation list, and no other component was checked, downloaded or updated

### Requirement: Google services Clair turns back on
Clair SHALL turn back on a Google service that ungoogled-chromium removes or disables only if it is the Chrome Web Store or a feed that protects users from harm, such as flags on malware extensions or certificate revocation data. It SHALL do so only through a change that adds the service to this requirement's list. Each service SHALL send Google only what it needs to work, and no usage, activity, device or identifying data.

#### Scenario: The services Clair turns back on
- **WHEN** the Google services Clair turns back on are listed
- **THEN** they are the Chrome Web Store's pages and installs, store extension update checks with the flags they return, and Chromium's certificate revocation list (CRLSet), and nothing else

#### Scenario: Proposing another service
- **WHEN** a change proposes turning on another Google service that ungoogled-chromium removes
- **THEN** the service is the store's or protects users from harm, the change says what each request sends and why each field is needed, and it adds the service to "The services Clair turns back on"

#### Scenario: A convenience service
- **WHEN** a Google service would only add convenience, such as sync, sign-in, translation, field trials or downloading media components
- **THEN** this requirement doesn't allow it, and turning it on needs a change that amends this requirement first

#### Scenario: What a turned-on service sends
- **WHEN** a request from a service on the list is captured
- **THEN** it carries only the fields its change named, and no install or device identifiers, usage pings or hardware and OS details beyond the platform and architecture

## ADDED Requirements

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

### Requirement: What a revocation check sends
A certificate revocation check SHALL send only the list's component ID and version, the hash of the list package Clair has, Clair's Chromium version and channel, the platform and architecture, and random per-request IDs, over HTTPS only. It SHALL NOT send the language or any field "What a store update check sends" in `extensions` rules out, and Clair SHALL send no report after a list installs.

#### Scenario: Reading a revocation check
- **WHEN** a revocation check is captured
- **THEN** its body names the list's component ID and version, the Chromium version and channel, `mac` and `arm64`, and nothing this requirement rules out

#### Scenario: Plain HTTP refused
- **WHEN** Google's update service answers with download addresses over both HTTP and HTTPS
- **THEN** Clair downloads the list over HTTPS only, and makes no check over plain HTTP

#### Scenario: List updated as a patch
- **WHEN** Clair has a list and a newer one is published
- **THEN** Clair downloads a patch to the list it has when Google offers one, or the full list when it doesn't

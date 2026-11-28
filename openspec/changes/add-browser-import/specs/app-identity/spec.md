# Spec Delta

## MODIFIED Requirements

### Requirement: Clair-specific keychain item
The application SHALL store its OS-encrypted storage key in the login keychain under the service name "Clair Safe Storage". It MUST NOT read or create the keychain items of other Chromium-based browsers, except that an import the user starts from a browser whose data is encrypted, such as Dia (`browser-import`), MAY read that browser's storage key, after macOS asks the user, only to read its data on this Mac. It MUST NOT create, change or keep a copy of that item.

#### Scenario: Keychain item on first launch
- **WHEN** Clair first needs to encrypt local data, such as cookies
- **THEN** a "Clair Safe Storage" item is created in the login keychain, and no "Chromium Safe Storage" item is created or read

#### Scenario: Importing from Dia
- **WHEN** the user imports from Dia and allows the keychain request
- **THEN** Clair reads "Dia Safe Storage" once for that import, leaves the item unchanged, and keeps no copy of it

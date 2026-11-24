## MODIFIED Requirements

### Requirement: Stable bundle identifier
The application SHALL use the bundle identifier `com.clairbrowser.clair`. Every helper app inside the bundle SHALL use an identifier prefixed with `com.clairbrowser.clair.`. These identifiers MUST NOT change in later releases.

#### Scenario: Main bundle identifier
- **WHEN** the `CFBundleIdentifier` of the shipped `Clair.app` is read
- **THEN** it is exactly `com.clairbrowser.clair`

#### Scenario: Helper bundle identifiers
- **WHEN** the bundle identifiers of all helper apps inside `Clair.app` are listed
- **THEN** each one starts with `com.clairbrowser.clair.`

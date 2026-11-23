# Spec Delta

## Purpose

Defines a profile's default search engine and search suggestions: what a new profile searches with, what searches and suggestion requests send, and how the user changes either.

## ADDED Requirements

### Requirement: Google is the default search engine
A new profile's default search engine SHALL be Google, in every country, and Clair SHALL NOT show Chromium's search engine choice screen. A search SHALL open `https://www.google.com/search` with the query in its `q` parameter, without Chromium's tracking, experiment or client parameters.

#### Scenario: Searching from the command bar
- **WHEN** a new profile's user types `clair browser` in the command bar and presses Return
- **THEN** the tab opens `https://www.google.com/search?q=clair+browser`, and the address has no `rlz`, `aqs`, `sourceid`, `client` or `gs_lcrp` parameter

#### Scenario: A country with a choice screen
- **WHEN** Clair starts with a new profile in a country where Chromium shows its search engine choice screen, such as Germany
- **THEN** no choice screen appears and Google is the default search engine

#### Scenario: Site search keyword
- **WHEN** the user types `google.com`, presses Tab, types `Arc` and presses Return
- **THEN** Google's results page for "Arc" opens

### Requirement: Search suggestions on by default
A new profile SHALL have search suggestions turned on. While the user types a query, the command bar SHALL include the default engine's suggestions among its rows. No suggestion request SHALL be sent before the user types, including when the command bar opens holding the current page's address.

#### Scenario: Suggestions as the user types
- **WHEN** a new profile's user types `weather` in the command bar
- **THEN** one or more rows are searches that Google suggested, besides the row searching for exactly `weather`

#### Scenario: Opening the command bar
- **WHEN** the user presses Cmd+T, or Cmd+L on a page, and types nothing
- **THEN** no request is sent to the search engine

### Requirement: What a suggestion request sends
A suggestion request to Google SHALL go over HTTPS to `www.google.com/complete/search`. Its address SHALL hold only the query and a fixed client name, with no address of the current page, cursor position, session token or experiment parameters. It SHALL carry the profile's own google.com cookies, as Chrome's do, and SHALL NOT save cookies from the response.

#### Scenario: A captured suggestion request
- **WHEN** a suggestion request is captured while the user types `weath`
- **THEN** its URL is `https://www.google.com/complete/search` with only `client` and `q=weath` in its query

### Requirement: Changing the search engine and suggestions
The user SHALL be able to choose another default engine and to turn search suggestions off, per profile, in Chromium's settings. With suggestions off, the command bar SHALL send no suggestion requests.

#### Scenario: Choosing another engine
- **WHEN** the user makes DuckDuckGo the default in `chrome://settings/search` and searches `clair browser` from the command bar
- **THEN** DuckDuckGo's results page for "clair browser" opens

#### Scenario: Turning suggestions off
- **WHEN** the user turns off "Autocomplete searches and URLs" in `chrome://settings/syncSetup` and types `weather` in the command bar
- **THEN** no request goes to `www.google.com/complete/search`, and no row is a suggestion from Google

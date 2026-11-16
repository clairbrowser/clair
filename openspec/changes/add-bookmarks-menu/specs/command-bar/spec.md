# Spec Delta

## MODIFIED Requirements

### Requirement: Suggestions from Chromium's autocomplete
As the user types, the command bar SHALL list suggestions from Chromium's autocomplete for the window's profile, from the sources the omnibox uses: what-you-typed, history, bookmarks, open tabs and the default search engine. A bookmark SHALL be suggested by its title or URL even if the user has never visited it, in a row that looks like a history row, and a page that's both visited and bookmarked SHALL be listed once. Each row SHALL show an icon, a title and, when it differs, the URL's domain. The first row SHALL be selected.

#### Scenario: History match
- **WHEN** the user has visited `https://en.wikipedia.org/wiki/Arc` and types `wiki arc`
- **THEN** a row for that page is listed with its title and `en.wikipedia.org`

#### Scenario: Bookmark match
- **WHEN** the profile has a bookmark titled "Clair Reading List" for a page the user has never visited, and the user types `reading list`
- **THEN** a row for that bookmark is listed with its title and its domain, and choosing it opens the page

#### Scenario: Search
- **WHEN** the user types `clair browser` and presses Return
- **THEN** the default search engine's results page for "clair browser" opens

#### Scenario: Incognito
- **WHEN** the command bar is used in an incognito window
- **THEN** it suggests from the incognito profile's autocomplete, which includes the regular profile's bookmarks, and what is typed isn't added to the regular profile's history

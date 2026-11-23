# Proposal

## Why

Clair has no working search engine out of the box. ungoogled-chromium's `replace-google-search-engine-with-nosearch.patch` replaces Chromium's Google entry with "No Search", whose search URL is `http://{searchTerms}`. So in a new profile, typing words into the command bar and pressing Return opens a broken address, and a user has to find `chrome://settings/search` before searching works at all. ungoogled-chromium also turns search suggestions off (`0006-modify-default-prefs.patch`), so the command bar never completes a query. Arc searches Google and suggests completions out of the box. Clair should too.

## What Changes

- **Google is every new profile's default search engine.**
  - A Clair patch, `restore-google-search.patch`, reverts `replace-google-search-engine-with-nosearch.patch`'s one hunk, as `restore-web-store.patch` reverts upstream hunks, so Chromium's Google entry is back.
  - The restored entry points at `https://www.google.com/` itself, because domain substitution rewrites Chromium's `{google:baseURL}`. It drops Chromium's tracking and experiment parameters.
  - Google is the default in every country, and Clair doesn't show Chromium's search engine choice screen.
  - Users can still pick another engine in `chrome://settings/search`. "No Search" goes, since it was the Google entry rewritten.
- **Search suggestions are on by default.** The same Clair patch reverts the `kSearchSuggestEnabled` hunk of ungoogled-chromium's `0006-modify-default-prefs.patch`. The rest of that patch stays. As the user types in the command bar, Google's suggestions appear among the rows. A suggestion request sends the query and a fixed client name to `www.google.com`, with the profile's google.com cookies, as Chrome does. Nothing is sent before the user types. Users can turn suggestions off in `chrome://settings/syncSetup` ("Autocomplete searches and URLs").
- **The privacy policy is amended to allow this.** `chromium-engine`'s "Google services Clair turns back on" so far allows only the Chrome Web Store and feeds that protect users from harm. It gains Google Search as the default search engine, with its suggestions. "ungoogled-chromium privacy defaults preserved" names the default engine and search suggestions as exceptions. An idle launch still contacts Google only for the certificate data check.

## Capabilities

### New Capabilities

- `search-engine`: a profile's default search engine and search suggestions: Google by default, suggestions on, what a search and a suggestion request send, and how the user changes either.

### Modified Capabilities

- `chromium-engine`:
  - "ungoogled-chromium privacy defaults preserved" makes the default search engine and search suggestions exceptions.
  - "Changes to Chromium limited to hooks and identity" allows the patch that defines the default engine and turns suggestions on.
  - "Google services Clair turns back on" adds Google Search and its suggestions to its list.
- `command-bar`: "Suggestions from Chromium's autocomplete" gains a scenario for the search engine's suggestions.

## Impact

- **Engine** (the engine key changes):
  - `patches/clair/restore-google-search.patch` changes the Google entry in `prepopulated_engines.json` and the default in `Profile::RegisterProfilePrefs`.
  - The choice screen is turned off, for example with Chromium's `--disable-search-engine-choice-screen` switch.
  - The command bar's autocomplete in `overlay/` sends nothing to the search engine while the text is still what Cmd+L opened with.
- **Build scripts:** no change. `utils/domain_substitution_exclude.list` doesn't change.
- **`ClairUI` and `ClairHost.h`:** no change. The command bar already shows search rows.
- **Network:** each search goes to `www.google.com`. While the user types, suggestion requests go to `www.google.com/complete/search`.
- **Existing profiles** keep "No Search". Clair isn't released, so nothing migrates them.
- **Runtime suite:** command bar tests that expect exact rows may now also get Google's suggestions, and need suggestions turned off in their profile.
- **Docs:** a Changie fragment.

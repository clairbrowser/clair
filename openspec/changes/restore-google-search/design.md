# Design

## Context

See `proposal.md` for why. Three things in ungoogled-chromium stand between Clair and Google search:

- `core/ungoogled-chromium/replace-google-search-engine-with-nosearch.patch`, one hunk, rewrites the `google` entry (prepopulated ID 1) in `third_party/search_engines_data/resources/definitions/prepopulated_engines.json` into "No Search". No other patch in either series touches that file.
- `extra/inox-patchset/0006-modify-default-prefs.patch` registers `prefs::kSearchSuggestEnabled` as `false`. It has twelve other hunks (background mode, cookies, preloading and so on) that must stay.
- Domain substitution rewrites `google.com` in `components/google/core/common/google_util.cc`. Chromium's Google entry builds its URLs from `{google:baseURL}` and `{google:baseSuggestURL}`, which come from `kGoogleHomepageURL` there, so even the original entry would search `www.9oo91e.qjz9zk`. `prepopulated_engines.json` isn't on ungoogled-chromium's substitution list, so a literal address in it survives.

Chromium's default engine for a new profile is `GetPrepopulatedFallbackSearch()`, which looks up prepopulated ID 1 (`google`) in the country's list. Google is in every country's list in `regional_settings.json`. In EEA countries Chromium also shows its search engine choice screen, unless `--disable-search-engine-choice-screen` is set.

`SearchProvider` sends a suggest request for any input except what `IsQueryPotentiallyPrivate()` holds back: schemes other than http, https and ftp, credentials, ports, queries, and https paths. `RemoteSuggestionsService` sends the profile's cookies for the suggest URL and doesn't save the response's (`LOAD_DO_NOT_SAVE_COOKIES`).

## Goals / Non-Goals

**Goals:**
- Google search and suggestions that work in a new profile, and that send no more than `search-engine` allows.

**Non-Goals:**
- Native search settings. Arc has Search engine and "Include search suggestions" in its profile settings. Clair keeps linking to Chromium's pages for now.
- The engine's icon in keyword mode (`keywordIcon` returns nil). That's a separate command-bar bug fix.
- Google's other features: Lens, the doodle, the new tab page's search box, AI mode. They use `{google:baseURL}` or `google_util` and stay substituted and dead.
- Migrating existing profiles from "No Search".

## Decisions

### D1. One Clair patch reverts the two upstream hunks

`patches/clair/restore-google-search.patch` follows `restore-web-store.patch`: its header says what it restores, and each hunk is preceded by a comment naming the upstream patch and hunk it reverts.

- It reverts `replace-google-search-engine-with-nosearch.patch`'s hunk, writing the Google entry D2 describes in place of "No Search".
- It reverts `0006-modify-default-prefs.patch`'s `profile.cc` hunk (D4).

It applies with no fuzz, like every Clair patch, so an upstream change to either hunk stops the patch check and names this patch.

Alternative: leaving the nosearch patch out of ungoogled-chromium's series. Both produce the same source. But the series is applied to `build/base`, so leaving a patch out makes the base depend on that choice. Every change to it would rebuild the engine from fresh source, about 4 hours on the owner's Mac instead of minutes, and needs new build tooling. A revert patch is an ordinary layer change.

### D2. Clair's Google entry uses literal `www.google.com` addresses

The revert puts back Chromium's Google entry with these changes:

- `search_url`: `https://www.google.com/search?q={searchTerms}&ie={inputEncoding}`
- `suggest_url`: `https://www.google.com/complete/search?client=chrome&q={searchTerms}`. `client=chrome` returns the JSON format with the `google:suggesttype` fields that `SearchSuggestionParser` reads.
- `alternate_urls`: the same five forms, on `https://www.google.com/`, so Chromium still recognizes Google results pages.
- Removed: `image_url`, `image_translate_*`, `contextual_search_url`, `image_url_post_params` and `search_intent_params`. They lead to Lens and image search, which stay off.
- Kept: ID 1, name "Google", keyword `google.com`, `favicon_url`, `base_builtin_resource_id` and `type`.

Without the `{google:…}` tracking and experiment parameters (`RLZ`, `assistedQueryStats`, `searchFieldtrialParameter`, `sourceId`, `searchClient`, `currentPageUrl`, `cursorPosition`, `sessionToken`, `pageClassification` and so on), neither URL carries more than `search-engine` allows.

Alternatives:
- Leave `google_util.cc` out of domain substitution. That brings back Google-domain detection across the whole browser, and `chromium-engine` limits the exclusion list to store and update addresses.
- Chromium's `--google-base-url` switch. It's global too, and would revive every `{google:baseURL}` user, such as the doodle.

### D3. Google everywhere, with no choice screen

Chromium already falls back to Google in every country once the entry exists. Clair adds `--disable-search-engine-choice-screen` to the browser process's command line before profiles load, from its existing start-up code in `overlay/chrome/browser/clair/`. If no hook runs early enough, a one-line patch makes the choice screen's check return false. The switch keeps it in Clair's own files. To verify, launch with `--search-engine-choice-country=DE` on a new profile: no dialog appears, and the default is Google.

### D4. Suggestions default on through a one-hunk revert

The revert of `0006-modify-default-prefs.patch`'s `profile.cc` hunk makes `kSearchSuggestEnabled` default to `true`. The rest of that patch stays. Only the default changes. A profile where the user turned suggestions off keeps its setting. The toggle stays in `chrome://settings/googleServices` ("Improve search suggestions"), where ungoogled-chromium leaves it; `chrome://settings/syncSetup` redirects to `chrome://settings/people`.

### D5. Suggestion requests keep Chromium's cookie behaviour

Suggestion requests send the profile's google.com cookies and save none from the response, as Chrome's do. Google's results page gets the same cookies when the user searches, so leaving them out would only make suggestions less relevant for a signed-in user, for little privacy gain. Stripping them would need a patch to `RemoteSuggestionsService`. Third-party cookie blocking doesn't apply, because the request's `site_for_cookies` is the suggest URL.

### D6. No request before the user types

- Cmd+T and a new window start with an empty field. Clair builds that list itself and doesn't start the controller (`showEmptyQueryList`), so zero-suggest never runs.
- Cmd+L starts a query with the page's address (`CommandBarModel.init`). `IsQueryPotentiallyPrivate()` holds back https paths, queries and credentials, but not `http://host/path`.

So `ClairChromiumAutocomplete` marks the opening query as one to leave the network out of: while the text is still exactly what the command bar opened with, `AutocompleteInput::set_omit_asynchronous_matches(true)` keeps every remote provider quiet. Once the user edits the text, queries run normally. This lives in the overlay, so `ClairHost.h` doesn't change, because the session already knows its starting text from the first `query`.

## Risks / Trade-offs

- **Upstream changes either hunk.** The revert's context no longer matches, so the patch check fails and names `restore-google-search.patch`, and the engine update PR's comment lists it. Rewriting the revert against the new hunk fixes it.
- **ungoogled-chromium adds `prepopulated_engines.json` to its substitution list.** The literal addresses would then become `9oo91e.qjz9zk` and searches would break. → The runtime test that searches checks the results page's host.
- **Command bar tests that expect exact rows.** With suggestions on, Google's rows can push other rows down, and network timing makes that flaky. → The runtime suite turns suggestions off in its profiles, except for the tests that check suggestions.
- **Suggestion tests depend on Google** being reachable from hosted runners. → They assert only that some suggested row appears for a common query, and the request-capture test checks the request, not the response.
- **Preconnect to the search engine at idle.** `SearchEnginePreconnector` is enabled by default but follows the preloading setting, which ungoogled-chromium turns off. → The idle-launch scenario forbids it, and a runtime check captures idle traffic.
- **Cookies in suggestion requests** tie typing to a signed-in Google account (D5). That's a deliberate trade-off, and the user can turn suggestions off.

## Migration Plan

New profiles only. Existing profiles keep the engine stored in their Web Data, so "No Search" stays the default where it was. Clair isn't released, so nothing migrates. Rolling back is removing the patch, which the next engine build does incrementally.

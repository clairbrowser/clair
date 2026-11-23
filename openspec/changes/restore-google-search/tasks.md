# Tasks

## 1. Google as the default search engine

- [x] 1.1 Add `patches/clair/restore-google-search.patch` to `patches/series`, after `clair/restore-web-store.patch`. Give it a header saying what it restores and why the addresses are literal. Its first hunk reverts `replace-google-search-engine-with-nosearch.patch`, with a comment naming it, writing the Google entry D2 describes: `search_url`, `suggest_url` and `alternate_urls` on `https://www.google.com/` with no `{google:…}` parameters, and Lens, image and contextual search fields removed (D1, D2). Verify that the patch check applies it with no fuzz.
- [x] 1.2 Turn Chromium's search engine choice screen off from Clair's start-up code in the overlay with `--disable-search-engine-choice-screen`, or with a one-line hunk in 1.1's patch if no hook runs before profiles load (D3). Verify that it's in the engine built in 2.3.
- [x] 1.3 Add a hunk to `restore-google-search.patch` that makes `NewTabURLDetails::ForProfile` always open the third-party New Tab page, so it stays ungoogled-chromium's (D7). Verify on a new profile of the rebuilt engine that a new tab shows no Google logo or search box, as on `main`.

## 2. Search suggestions

- [x] 2.1 Add a hunk to `restore-google-search.patch` reverting `0006-modify-default-prefs.patch`'s `kSearchSuggestEnabled` hunk, with a comment naming that patch and hunk (D1, D4). Verify that the patch check applies it.
- [x] 2.2 In `overlay/chrome/browser/clair/window/clair_autocomplete.mm`, run a query whose text is still exactly the command bar's starting text with `set_omit_asynchronous_matches(true)`, and other queries as now (D6). Verify that the engine compiles with it.
- [x] 2.3 Build the engine (`gh workflow run engine.yml -f ref=<branch>`), run it with `scripts/run-local.sh` on a new profile, and capture its traffic. Verify:
  - searching `clair browser` opens `https://www.google.com/search?q=clair+browser&ie=UTF-8`;
  - typing `weath` sends `https://www.google.com/complete/search?client=chrome&q=weath`, and the bar shows Google's suggestions;
  - Cmd+L on an `http://` page with a path sends no suggestion request until the text changes;
  - an idle launch makes no request or preconnection to `www.google.com`;
  - with `--search-engine-choice-country=DE`, no choice screen appears and Google is the default;
  - turning off "Improve search suggestions" stops suggestion requests.

  Note the results in the PR.

## 3. Runtime suite, release notes and checks

- [ ] 3.1 Turn search suggestions off in the profiles of runtime tests that expect exact command bar rows, through the harness's profile setup (`Harness.swift`). Verify that the command bar tests pass in the quality checks on the branch.
- [ ] 3.2 Add runtime tests: on a new profile, searching from the command bar opens `www.google.com/search` with only `q` and `ie`, and typing `weather` lists one or more suggested searches with the search icon. Verify that they pass in the quality checks on the branch (`gh workflow run quality.yml --ref <branch>`).
- [ ] 3.3 Add a Changie fragment (`changie new`): new profiles search Google and show its suggestions as you type, and both can be changed in Chromium's settings. Verify that it's in the PR.
- [ ] 3.4 Run the merge gate. Verify that CI passes.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.

// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import XCTest

/// Google search and its suggestions on a new profile (restore-google-search
/// task 3.2). Both search from Cmd+L, so the tab's DevTools session sees the
/// results page's request before Google can redirect it. The suggestion
/// requests themselves are the browser's, which DevTools doesn't show.
@MainActor
final class SearchTests: NativeWindowTestCase {
  /// Starts on a new profile, with suggestions on as Clair ships them, and
  /// reports the tab's network requests.
  private func start() async throws -> (Browser, DevToolsSession) {
    let (browser, tab) = try await startWithPage(searchSuggestions: true)
    try await tab.send("Network.enable")
    return (browser, tab)
  }

  /// Opens the command bar on the page's address and selects it, so typing
  /// replaces it.
  private func editAddress(_ browser: Browser) throws -> XCUIElement {
    browser.ui.typeKey("l", modifierFlags: .command)
    let field = browser.element("clair.commandBarField")
    try require(field.waitForExistence(timeout: 10), "Cmd+L didn't open the command bar")
    field.typeKey("a", modifierFlags: .command)
    return field
  }

  /// The query of the tab's next request for a Google results page, as sent.
  private func resultsPageQuery(_ tab: DevToolsSession) async throws -> String {
    let request = try await tab.waitForEvent("Network.requestWillBeSent", within: .seconds(60)) {
      $0["type"] as? String == "Document"
        && (($0["request"] as? [String: Any])?["url"] as? String)?.hasPrefix("https://www.google.com/") == true
    }
    let address = try XCTUnwrap((request["request"] as? [String: Any])?["url"] as? String)
    let components = try XCTUnwrap(URLComponents(string: address))
    XCTAssertEqual(components.path, "/search", "The search didn't open Google's results page: \(address)")
    return components.percentEncodedQuery ?? ""
  }

  /// Return searches Google with only the query and its encoding (search-engine
  /// spec, "Searching from the command bar").
  func testSearchingOpensGoogle() async throws {
    let (browser, tab) = try await start()
    defer { tab.close() }
    try editAddress(browser).typeText("clair browser\n")
    let query = try await resultsPageQuery(tab)
    XCTAssertEqual(query, "q=clair+browser&ie=UTF-8", "The results page's address has other parameters")
  }

  /// Typing lists searches Google suggested, and choosing one opens Google's
  /// results for it (command-bar spec, "Search engine suggestions"). On a new
  /// profile, a row whose title starts with the typed text and shows no
  /// domain, tab or bookmark is a suggestion, unless it's the typed text itself
  /// or an address Google suggested.
  func testSuggestionsFromGoogle() async throws {
    let (browser, tab) = try await start()
    defer { tab.close() }
    try editAddress(browser).typeText("weather")
    let suggested = browser.ui.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier == 'clair.suggestion' AND label BEGINSWITH[c] 'weather' AND NOT (label ==[c] 'weather')"
          + " AND NOT (label CONTAINS ', ') AND NOT (label CONTAINS '.')")
    ).firstMatch
    try require(
      suggested.waitForExistence(timeout: 30),
      "Typing weather lists no suggestion from Google: \(browser.suggestionLabels)")
    let suggestion = suggested.label
    suggested.click()
    let query = try await resultsPageQuery(tab)
    // The engine writes a space in the query as +.
    let searched = URLComponents(string: "?" + query.replacingOccurrences(of: "+", with: "%20"))?
      .queryItems?.first { $0.name == "q" }?.value
    XCTAssertEqual(searched, suggestion, "Choosing \(suggestion) didn't search for it: \(query)")
  }
}

extension Browser {
  /// The command bar's rows, as VoiceOver reads them.
  fileprivate var suggestionLabels: [String] {
    ui.descendants(matching: .any).matching(identifier: "clair.suggestion").allElementsBoundByIndex.map(\.label)
  }
}

// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Testing

@testable import ClairUI

private func tab(_ title: String, name: String? = nil) -> ImportItem {
  .tab(ImportTab(url: "https://\(title.lowercased()).example/", title: title, name: name))
}

private func pane(_ title: String) -> ImportTab {
  ImportTab(url: "https://\(title.lowercased()).example/", title: title)
}

/// The names of folders and the titles of tabs, splits as "A|B".
private func outline(_ items: [ImportItem]) -> [String] {
  items.map { item in
    switch item {
    case .tab(let tab): tab.name ?? tab.title
    case .split(let panes, _): panes.map(\.title).joined(separator: "|")
    case .folder(let name, let children): "\(name)[\(outline(children).joined(separator: ","))]"
    }
  }
}

// MARK: Making trees fit Clair (browser-import "Pinned tabs and folders", "Splits from an import")

struct ImportShapeTests {
  @Test func nestedFolderFollowsItsParentNamedWithItsPath() {
    let items: [ImportItem] = [
      .folder(
        name: "Parent Folder",
        children: [
          .split(panes: [pane("Verge"), pane("Ars")], ratio: 0.5),
          .folder(name: "Child Folder", children: [tab("BBC", name: "RENAMED TAB")]),
        ]),
      tab("After"),
    ]
    #expect(
      outline(ImportShape.pinned(items)) == [
        "Parent Folder[Verge|Ars]", "Parent Folder / Child Folder[RENAMED TAB]", "After",
      ])
  }

  @Test func deeperNestingDropsFoldersHoldingOnlyFolders() {
    let items: [ImportItem] = [
      .folder(name: "A", children: [.folder(name: "B", children: [.folder(name: "C", children: [tab("One")])])])
    ]
    #expect(outline(ImportShape.pinned(items)) == ["A / B / C[One]"])
  }

  @Test func siblingsKeepTheirOrderDepthFirst() {
    let items: [ImportItem] = [
      .folder(
        name: "A",
        children: [
          tab("One"),
          .folder(name: "B", children: [tab("Two"), .folder(name: "C", children: [tab("Three")])]),
          .folder(name: "D", children: [tab("Four")]),
          tab("Five"),
        ])
    ]
    #expect(outline(ImportShape.pinned(items)) == ["A[One,Five]", "A / B[Two]", "A / B / C[Three]", "A / D[Four]"])
  }

  @Test func anEmptyFolderStays() {
    #expect(outline(ImportShape.pinned([.folder(name: "Empty", children: [])])) == ["Empty[]"])
  }

  @Test func aFolderOfOnlyEmptyFoldersLeavesThem() {
    let items: [ImportItem] = [.folder(name: "A", children: [.folder(name: "B", children: [])])]
    #expect(outline(ImportShape.pinned(items)) == ["A / B[]"])
  }

  @Test func threePanesBecomeTabsInPlace() {
    let items: [ImportItem] = [tab("Before"), .split(panes: [pane("Africa"), pane("Europe"), pane("Asia")], ratio: 0.33)]
    #expect(outline(ImportShape.flat(items)) == ["Before", "Africa", "Europe", "Asia"])
  }

  @Test func twoPanesStayASplitWithTheirRatio() {
    let shaped = ImportShape.flat([.split(panes: [pane("Docs"), pane("Mail")], ratio: 0.6)])
    #expect(shaped == [.split(panes: [pane("Docs"), pane("Mail")], ratio: 0.6)])
  }

  @Test func aRatioOutOfRangeBecomesEqual() {
    #expect(ImportShape.flat([.split(panes: [pane("A"), pane("B")], ratio: 1.4)]) == [.split(panes: [pane("A"), pane("B")], ratio: 0.5)])
    #expect(ImportShape.flat([.split(panes: [pane("A"), pane("B")], ratio: .nan)]) == [.split(panes: [pane("A"), pane("B")], ratio: 0.5)])
  }

  @Test func aSinglePaneIsATab() {
    #expect(outline(ImportShape.flat([.split(panes: [pane("Only")], ratio: 1)])) == ["Only"])
  }

  @Test func todayAndFavoritesHoldNoFolders() {
    let items: [ImportItem] = [.folder(name: "Trip", children: [tab("D"), .folder(name: "Inner", children: [tab("E")])]), tab("F")]
    #expect(outline(ImportShape.flat(items)) == ["D", "E", "F"])
  }

  @Test func splitsInsideFoldersAreShapedToo() {
    let items: [ImportItem] = [.folder(name: "F", children: [.split(panes: [pane("A"), pane("B"), pane("C")], ratio: 0.3)])]
    #expect(outline(ImportShape.pinned(items)) == ["F[A,B,C]"])
  }
}

// MARK: The plan's JSON (design D3)

struct ImportPlanJSONTests {
  private func everyKind() -> ImportPlan {
    ImportPlan(
      source: "arc", sourceName: "Arc",
      profiles: [
        ImportPlan.Profile(
          sourceKey: "Default", sourceName: "Your Arc", destination: .profile("Default"),
          spaces: [
            ImportPlan.Space(
              name: "Space 2", icon: "😀",
              pinned: [
                .folder(name: "Parent Folder", children: [tab("BBC", name: "RENAMED TAB")]),
                .folder(name: "Parent Folder / Child Folder", children: []),
              ],
              today: [.split(panes: [pane("Docs"), pane("Mail")], ratio: 0.6), tab("Weather")])
          ],
          favorites: [tab("Example")],
          bookmarks: [.bookmark(title: "Google", url: "https://google.com/"), .folder(name: "Work", children: [])],
          history: .chromiumDB("/tmp/clair-import/History"),
          favicons: .chromiumDB("/tmp/clair-import/Favicons"),
          extensions: [ImportPlan.Extension(id: "eimadpbcbfnmbkopoojfekhnkhdbieeh", name: "Dark Reader", enabled: true, pinned: true)]),
        ImportPlan.Profile(
          sourceKey: "Profile 6", sourceName: "Work", destination: .newProfile("Work"),
          history: .safariJSON("/tmp/clair-import/History.json"),
          session: ImportPlan.Session(chromiumSessions: "/tmp/clair-import/Sessions", space: "Work"),
          skipped: [ImportSkip(reason: .notFromWebStore, name: "Unpacked")]),
      ])
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func encodesEveryItemKindAsTheEngineReadsIt() throws {
    let json = try object(try everyKind().json())
    #expect(json["version"] as? Int == 1)
    #expect(json["source"] as? String == "arc")
    let profiles = try #require(json["profiles"] as? [[String: Any]])
    let first = profiles[0]
    #expect((first["destination"] as? [String: String]) == ["profile": "Default"])
    #expect((profiles[1]["destination"] as? [String: String]) == ["newProfile": "Work"])

    let space = try #require((first["spaces"] as? [[String: Any]])?.first)
    #expect(space["icon"] as? String == "😀")
    let pinned = try #require(space["pinned"] as? [[String: Any]])
    let folder = try #require(pinned[0]["folder"] as? [String: Any])
    #expect(folder["name"] as? String == "Parent Folder")
    let named = try #require((folder["children"] as? [[String: Any]])?.first?["tab"] as? [String: Any])
    #expect(named["name"] as? String == "RENAMED TAB")
    #expect(named["url"] as? String == "https://bbc.example/")

    let today = try #require(space["today"] as? [[String: Any]])
    let split = try #require(today[0]["split"] as? [String: Any])
    #expect(split["ratio"] as? Double == 0.6)
    #expect((split["panes"] as? [[String: Any]])?.map { $0["title"] as? String } == ["Docs", "Mail"])
    // A tab with no custom name has no "name".
    #expect((today[1]["tab"] as? [String: Any])?["name"] == nil)

    #expect((first["history"] as? [String: String]) == ["chromiumDB": "/tmp/clair-import/History"])
    #expect((first["favicons"] as? [String: String]) == ["chromiumDB": "/tmp/clair-import/Favicons"])
    #expect((profiles[1]["history"] as? [String: String]) == ["safariJSON": "/tmp/clair-import/History.json"])
    #expect(
      (profiles[1]["session"] as? [String: String])
        == ["chromiumSessions": "/tmp/clair-import/Sessions", "space": "Work"])

    let bookmarks = try #require(first["bookmarks"] as? [[String: Any]])
    #expect((bookmarks[0]["bookmark"] as? [String: String]) == ["title": "Google", "url": "https://google.com/"])
    #expect((bookmarks[1]["folder"] as? [String: Any])?["name"] as? String == "Work")
    // A profile without bookmarks sends none, rather than an empty list.
    #expect(profiles[1]["bookmarks"] == nil)

    let extensions = try #require(first["extensions"] as? [[String: Any]])
    #expect(extensions[0]["id"] as? String == "eimadpbcbfnmbkopoojfekhnkhdbieeh")
    #expect(extensions[0]["enabled"] as? Bool == true)
    #expect(extensions[0]["pinned"] as? Bool == true)
  }

  @Test func roundTrips() throws {
    let plan = everyKind()
    #expect(try JSONDecoder().decode(ImportPlan.self, from: try plan.json()) == plan)
  }

  @Test func decodesASummary() throws {
    let json = Data(
      """
      {"imported": {"spaces": 2, "favorites": 2, "pinnedTabs": 3, "todayTabs": 5, "bookmarks": 10,
                    "history": 120, "extensions": 1},
       "alreadyInClair": {"spaces": 0, "favorites": 1, "pinnedTabs": 0, "todayTabs": 0, "bookmarks": 2,
                          "history": 0, "extensions": 0},
       "skipped": [{"reason": "storeFailed", "name": "Gone Extension"},
                   {"reason": "unreadableData", "name": "History"}]}
      """.utf8)
    let summary = try ImportSummary(json: json)
    #expect(summary.imported.spaces == 2)
    #expect(summary.imported.history == 120)
    #expect(summary.alreadyInClair.bookmarks == 2)
    #expect(
      summary.skipped == [
        ImportSkip(reason: .storeFailed, name: "Gone Extension"), ImportSkip(reason: .unreadableData, name: "History"),
      ])
  }
}

// MARK: The contract (design D3)

@MainActor
struct ImportContractTests {
  @Test func fakeHostRecordsThePlanAndRepliesWithItsSummary() throws {
    let host = FakeHost()
    host.importSummary = ImportSummary(imported: .init(spaces: 1, history: 3))
    let plan = ImportPlan(
      source: "safari", sourceName: "Safari", folder: "/tmp/clair-import-x",
      profiles: [ImportPlan.Profile(sourceKey: "Safari", sourceName: "Safari", destination: .profile("Default"))])
    var phases: [String] = []
    var summary: ImportSummary?
    host.applyImportPlan(try plan.json(), progress: { _, phase in phases.append(phase) }) {
      summary = try? ImportSummary(json: $0)
    }
    #expect(host.importPlans == [plan])
    #expect(phases == ["sidebar", "extensions"])
    #expect(summary?.imported.spaces == 1)
    #expect(summary?.imported.history == 3)
  }
}

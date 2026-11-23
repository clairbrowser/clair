// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// Called by the runtime suite over DevTools. "1" is the Bookmarks Bar's ID.
self.createInBar = (title, url) =>
  chrome.bookmarks.create({ parentId: "1", title, url }).then((node) => node.id);

// The titles of a folder's children: "1" is the Bookmarks Bar, "2" Other
// Bookmarks.
self.childTitles = (folderID) =>
  chrome.bookmarks.getChildren(folderID).then((nodes) => nodes.map((node) => node.title));

// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_PIN_STORE_H_
#define CHROME_BROWSER_CLAIR_CLAIR_PIN_STORE_H_

#include <cstdint>
#include <deque>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/observer_list.h"
#include "base/observer_list_types.h"
#include "base/time/time.h"
#include "url/gurl.h"

#if !defined(__OBJC__)
#error "clair_pin_store.h keeps NSImage icons; include it from .mm files"
#endif

@class NSImage;

class PrefRegistrySimple;
class PrefService;

namespace base {
class SequencedTaskRunner;
}  // namespace base

namespace clair {

// Local State prefs (add-pinned-tabs-and-favorites design D1, add-tab-folders
// design D1, D3).
inline constexpr char kPinsPref[] = "clair.pins";
inline constexpr char kClosedFoldersPref[] = "clair.closed_folders";

// Where a pin is kept: a Space's pinned section, a folder in it, or a
// profile's favorites. A folder container names its Space too. Exactly one of
// `space` and `profile` is set.
struct PinContainer {
  std::string space;
  // A folder of `space`, or empty for the section's top level.
  std::string folder;
  std::string profile;

  static PinContainer OfSpace(std::string_view space);
  static PinContainer OfFolder(std::string_view space, std::string_view folder);
  static PinContainer OfProfile(std::string_view profile);
  bool is_favorites() const { return !profile.empty(); }
  bool is_folder() const { return !folder.empty(); }
  // The pinned section this is in, or the favorites themselves: what
  // observers hear about.
  PinContainer Section() const;
  bool operator==(const PinContainer&) const = default;
  auto operator<=>(const PinContainer&) const = default;
};

// A pinned tab or favorite: a saved item that stays whether or not a page is
// open (D1).
struct Pin {
  Pin();
  Pin(const Pin&);
  Pin& operator=(const Pin&);
  ~Pin();

  // A lowercase UUID, which never changes.
  std::string id;
  // Where it shows: a pin in a folder is in the folder's Space.
  PinContainer container;
  // Its sort key in its container (add-tab-folders D1, clair_order_key.h).
  std::string order;
  // The pinned URL.
  GURL url;
  // The page's title when its tab was last at the pinned URL; may be empty.
  std::string title;
  // The custom name, or empty.
  std::string name;
};

// A folder of pinned tabs in a Space's pinned section (add-tab-folders D1).
struct Folder {
  // A lowercase UUID, which never changes.
  std::string id;
  std::string space;
  // Its sort key among the Space's pinned items.
  std::string order;
  // Never empty.
  std::string name;
};

// Every pin and folder, kept in Chromium's Local State, one record each
// (add-tab-folders design D1):
//
//   clair.pins  { "version": 1,
//                 "items": {
//                   "<uuid>": { "kind": "folder", "space": "<space uuid>",
//                               "order": "a0", "name": "Trip" },
//                   "<uuid>": { "kind": "pin", "space": "<space uuid>",
//                               "folder": "<folder uuid>", "order": "a0",
//                               "url": "https://…", "title": "…",
//                               "name": "…" },
//                   "<uuid>": { "kind": "pin", "profile": "<profile ID>",
//                               "order": "a0", … } } }
//   clair.closed_folders  ["<folder uuid>", …]   // this Mac's (D3)
//
// A folder names its Space; a pinned tab its Space and, in a folder, the
// folder; a favorite its profile, by the ID of ClairProfiles::StoredIDOf.
// Each record carries its sort key, and a container's children are sorted by
// it, then by ID, so a move rewrites only the record that moved, except a
// folder moving to another Space, which rewrites its pins' Space too. A pin
// shows in its folder's Space while the folder exists, and at the top level
// of its own Space when it's missing. Folders hold pins only, one level deep;
// the store refuses any other write. On load, a record whose Space or profile
// is missing, or without a valid sort key, is dropped with its icon.
//
// Each pin's icon is a PNG of at most 64 × 64 pixels in
// `<user data dir>/Clair Pin Icons/<pin uuid>.png`, written and read on a
// background sequence. It also remembers the last 25 pins and folders removed
// this session, for Restore Last Closed Tab (D3, add-tab-folders D7).
class ClairPinStore {
 public:
  class Observer : public base::CheckedObserver {
   public:
    // A Space's pinned section or a profile's favorites changed: pins or
    // folders were added, removed, moved, renamed or edited, a folder was
    // opened or closed, or a pin's icon changed. `section` is never a
    // folder.
    virtual void OnPinsChanged(const PinContainer& section) = 0;
  };

  // A pin or folder removed this session (D3, add-tab-folders D7).
  struct Removal {
    Removal();
    Removal(const Removal&);
    Removal& operator=(const Removal&);
    ~Removal();

    // The folder, for a folder's removal.
    std::optional<Folder> folder;
    bool folder_was_closed = false;
    // The pin, or the folder's pins in order, each with its place and key.
    std::vector<Pin> pins;
    base::Time time;
  };

  static constexpr size_t kMaxNameLength = 200;
  static constexpr size_t kMaxTitleLength = 1024;
  static constexpr size_t kMaxRemovals = 25;
  // The largest icon kept, in pixels.
  static constexpr int kMaxIconSize = 64;

  // browser_prefs.cc, through clair::RegisterLocalStatePrefs.
  static void RegisterPrefs(PrefRegistrySimple* registry);

  // The store, created on first use from the browser process's Local State.
  static ClairPinStore* Get();

  ClairPinStore(const ClairPinStore&) = delete;
  ClairPinStore& operator=(const ClairPinStore&) = delete;

  const Pin* Find(std::string_view id) const;
  const Folder* FindFolder(std::string_view id) const;
  // The IDs of a container's children, in order: a Space's pinned section
  // lists its top-level pins and its folders, a folder and the favorites
  // their pins.
  std::vector<std::string> ChildrenOf(const PinContainer& container) const;
  // A container's pins, in order; a Space's section's top-level ones only.
  std::vector<const Pin*> PinsIn(const PinContainer& container) const;
  // Every pinned tab of a Space, its folders' included, in the sidebar's
  // order (add-tab-folders D9).
  std::vector<const Pin*> AllPinsIn(std::string_view space) const;
  // A Space's folders, in order.
  std::vector<const Folder*> FoldersIn(std::string_view space) const;
  // A pin's or folder's index among its container's children.
  std::optional<size_t> IndexOf(std::string_view id) const;
  // The profile a pin's tab uses: a favorite's own, or its Space's.
  std::string ProfileOf(const Pin& pin) const;
  // The cached icon, or nil.
  NSImage* IconOf(std::string_view id) const;
  // add-tab-folders D3: whether a folder is open on this Mac.
  bool IsOpen(std::string_view folder) const;

  // Adds a pin at `index` in `container`, and returns its ID, or an empty
  // string for an invalid URL or an unknown container.
  std::string Create(const PinContainer& container,
                     size_t index,
                     const GURL& url,
                     std::string_view title,
                     std::string_view name);
  // Moves a pin to `index` in `container`, which may be another, or a folder
  // to `index` in a Space's section, with its pins. Refuses a folder
  // anywhere else and a folder container of another Space. Returns whether
  // anything moved.
  bool Move(std::string_view id, const PinContainer& container, size_t index);
  // Removes the pin. With `remember`, Restore Last Closed Tab can bring it
  // back (D3): the caller removes it before closing its tab, so the tab's
  // own entry in Chromium's recently closed list is the newer.
  void Remove(std::string_view id, bool remember);
  // An empty name clears it.
  void SetName(std::string_view id, std::string_view name);
  void SetTitle(std::string_view id, std::string_view title);
  // Sets the pinned URL; ignored for an invalid one.
  void SetURL(std::string_view id, const GURL& url);
  // Keeps `icon` as the pin's, nil leaving it as it is.
  void SetIcon(std::string_view id, NSImage* icon);

  // --- Folders (add-tab-folders D1, D3, D7, D11) ---
  // Adds an empty, open folder at `index` in `space`'s section, and returns
  // its ID, or an empty string for an empty name or an unknown Space.
  std::string CreateFolder(std::string_view space,
                           size_t index,
                           std::string_view name);
  // An empty name is ignored.
  void RenameFolder(std::string_view id, std::string_view name);
  void SetOpen(std::string_view id, bool open);
  // Adds a copy right after the folder, open, with a copy of each of its
  // pins and their icons. Returns the copy's ID, or empty.
  std::string DuplicateFolder(std::string_view id);
  // Removes the folder and its pins; with `remember`, as one removal that
  // Restore Last Closed Tab brings back whole (D7). Returns the pins' IDs.
  std::vector<std::string> RemoveFolder(std::string_view id, bool remember);

  // add-pinned-tabs-and-favorites D9: a Space was deleted, or a profile
  // removed: its pins, folders and their icons go, unremembered. Returns the
  // IDs of the pins removed.
  std::vector<std::string> RemoveContainer(const PinContainer& container);

  // D3: the newest pin or folder removed this session whose tabs used
  // `profile` and whose Space or profile still exists, or null.
  const Removal* NewestRemoval(std::string_view profile) const;
  // Whether `id` was removed this session, alone or in its folder, and can
  // come back.
  bool WasRemoved(std::string_view id) const;
  // Puts a removal back. A pin goes back to its place and key, in its folder
  // while the folder exists, and otherwise at the end of its Space's
  // section; a folder goes back to its key with its pins, open or closed as
  // it was. Either goes to the end when its key is now taken. Returns
  // whether it did.
  bool Restore(const Removal* removal);
  // Puts back the removal holding the pin `id`: the pin, or its whole
  // folder.
  bool RestorePin(std::string_view id);

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  friend class base::NoDestructor<ClairPinStore>;

  explicit ClairPinStore(PrefService* local_state);

  void Load();
  void Save();
  void SaveClosed();
  // Saves, rebuilds the children index and tells the observers about
  // `container`'s section.
  void Changed(const PinContainer& container);
  void Notify(const PinContainer& container);
  // Rebuilds every container's children, sorted by key, then by ID.
  void Index();
  // Whether `container` exists: its Space or profile, and its folder, which
  // must be of that Space.
  bool IsValid(const PinContainer& container) const;
  // A key for `index` among `container`'s children without `moving`,
  // between that place's neighbours. When two of them share a key, every
  // child gets a new one first.
  std::string KeyAt(const PinContainer& container,
                    size_t index,
                    std::string_view moving);
  // Whether a child of `container` has the key `order`.
  bool KeyTaken(const PinContainer& container, std::string_view order) const;
  // The sort key of a child of a container.
  const std::string& OrderOf(std::string_view id) const;
  void Remember(Removal removal);
  void Forget(const Removal& removal);
  base::FilePath IconPath(std::string_view id) const;
  void DeleteIcon(std::string_view id);
  void IconsLoaded(std::map<std::string, std::vector<uint8_t>> icons);

  const raw_ptr<PrefService> prefs_;
  std::map<std::string, Pin> pins_;
  std::map<std::string, Folder> folders_;
  // The children of each container, in order.
  std::map<PinContainer, std::vector<std::string>> children_;
  std::set<std::string> closed_;
  std::map<std::string, NSImage* __strong> icons_;
  std::deque<Removal> removals_;
  base::FilePath icon_dir_;
  scoped_refptr<base::SequencedTaskRunner> file_runner_;
  base::ObserverList<Observer> observers_;
  base::WeakPtrFactory<ClairPinStore> weak_factory_{this};
};

// D2: whether `url` is `pinned` once both lose their query and fragment.
bool SamePinnedURL(const GURL& url, const GURL& pinned);

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_PIN_STORE_H_

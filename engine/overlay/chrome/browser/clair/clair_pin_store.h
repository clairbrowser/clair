// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_PIN_STORE_H_
#define CHROME_BROWSER_CLAIR_CLAIR_PIN_STORE_H_

#include <cstdint>
#include <deque>
#include <map>
#include <optional>
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

// Local State pref (add-pinned-tabs-and-favorites design D1).
inline constexpr char kPinsPref[] = "clair.pins";

// Where a pin is kept: a Space's pinned section, or a profile's favorites.
// Exactly one of the two is set.
struct PinContainer {
  std::string space;
  std::string profile;

  static PinContainer OfSpace(std::string_view space);
  static PinContainer OfProfile(std::string_view profile);
  bool is_favorites() const { return !profile.empty(); }
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
  PinContainer container;
  // The pinned URL.
  GURL url;
  // The page's title when its tab was last at the pinned URL; may be empty.
  std::string title;
  // The custom name, or empty.
  std::string name;
};

// Every pin, kept in Chromium's Local State (D1):
//
//   clair.pins  { "version": 1,
//                 "spaces":   { "<space uuid>":  ["<pin uuid>", …] },
//                 "profiles": { "<profile dir>": ["<pin uuid>", …] },
//                 "items":    { "<pin uuid>": { "url": "https://…",
//                                               "title": "…",
//                                               "name": "…",
//                                               "parent": "" } } }
//
// Each pin's icon is a PNG of at most 64 × 64 pixels in
// `<user data dir>/Clair Pin Icons/<pin uuid>.png`, written and read on a
// background sequence. It also remembers the last 25 pins removed this
// session, for Restore Last Closed Tab (D3).
class ClairPinStore {
 public:
  class Observer : public base::CheckedObserver {
   public:
    // A container's pins were added, removed, moved, renamed or edited, or
    // one's icon changed.
    virtual void OnPinsChanged(const PinContainer& container) = 0;
  };

  // A pin removed this session (D3).
  struct Removal {
    Removal();
    Removal(const Removal&);
    Removal& operator=(const Removal&);
    ~Removal();

    Pin pin;
    // Its index in its container when it was removed.
    size_t index = 0;
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
  // A container's pins, in order.
  std::vector<const Pin*> PinsIn(const PinContainer& container) const;
  // The pin's index in its container.
  std::optional<size_t> IndexOf(std::string_view id) const;
  // The profile a pin's tab uses: a favorite's own, or its Space's.
  std::string ProfileOf(const Pin& pin) const;
  // The cached icon, or nil.
  NSImage* IconOf(std::string_view id) const;

  // Adds a pin at `index` in `container`, and returns its ID, or an empty
  // string for an invalid URL or an unknown container.
  std::string Create(const PinContainer& container,
                     size_t index,
                     const GURL& url,
                     std::string_view title,
                     std::string_view name);
  // Moves the pin to `index` in `container`, which may be another.
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

  // D9: a Space was deleted, or a profile removed: its pins and their icons
  // go, unremembered. Returns the IDs removed.
  std::vector<std::string> RemoveContainer(const PinContainer& container);

  // D3: the newest pin removed this session whose tab used `profile`, or
  // null.
  const Removal* NewestRemoval(std::string_view profile) const;
  // Whether `id` was removed this session and can come back.
  bool WasRemoved(std::string_view id) const;
  // Puts a removed pin back at its index in its container, if the container
  // still exists. Returns whether it did.
  bool Restore(std::string_view id);

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  friend class base::NoDestructor<ClairPinStore>;

  explicit ClairPinStore(PrefService* local_state);

  void Load();
  void Save();
  void Changed(const PinContainer& container);
  std::vector<std::string>* ListOf(const PinContainer& container);
  const std::vector<std::string>* ListOf(const PinContainer& container) const;
  // Whether `container`'s Space or profile exists.
  bool IsValid(const PinContainer& container) const;
  // Takes `id` out of its list; returns its index.
  std::optional<size_t> Take(std::string_view id);
  base::FilePath IconPath(std::string_view id) const;
  void DeleteIcon(std::string_view id);
  void IconsLoaded(std::map<std::string, std::vector<uint8_t>> icons);

  const raw_ptr<PrefService> prefs_;
  std::map<std::string, Pin> pins_;
  std::map<std::string, std::vector<std::string>> spaces_;
  std::map<std::string, std::vector<std::string>> profiles_;
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

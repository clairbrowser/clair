// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_LINK_RULE_STORE_H_
#define CHROME_BROWSER_CLAIR_CLAIR_LINK_RULE_STORE_H_

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "chrome/browser/clair/clair_space_store.h"
#include "url/gurl.h"

class PrefRegistrySimple;
class PrefService;

namespace clair {

// Local State pref (add-link-rules design D1).
inline constexpr char kLinkRulesPref[] = "clair.link_rules";

// How a rule matches a link (D3), as ClairHost.h's ClairLinkRuleMatch.
enum class LinkRuleMatch {
  // "URLs containing".
  kContains = 0,
  // "this exact URL".
  kExact = 1,
  // "URLs starting with".
  kPrefix = 2,
};

// One link rule: links from other apps that match `text` as `match` says
// open in `space` (D1).
struct LinkRule {
  // A lowercase UUID, which a later change may use to reorder or sync rules.
  std::string id;
  LinkRuleMatch match = LinkRuleMatch::kContains;
  // As the user typed it, trimmed.
  std::string text;
  // The Space's UUID.
  std::string space;
};

// D3: a rule's text read as a URL.
struct LinkRuleURL {
  // A valid http or https URL with a host.
  GURL url;
  // Whether the text had no scheme, so http and https links match alike.
  bool scheme_free = false;
};

// D3's "reading a text": trimmed, not empty and without whitespace, then,
// with "https://" in front when it has no "scheme://", a valid http or https
// URL with a host. Nullopt otherwise.
std::optional<LinkRuleURL> ReadLinkRuleText(std::string_view text);

// D3: whether `rule` matches `link`, ignoring the link's fragment.
bool LinkRuleMatches(const LinkRule& rule, const GURL& link);

// The link rules, in order, kept in Chromium's Local State (D1):
//
//   clair.link_rules  { "version": 1,
//                       "rules": [ { "id": "<uuid>",
//                                    "match": "contains" | "exact" | "prefix",
//                                    "text": "example.com",
//                                    "space": "<space uuid>" } ] }
//
// It keeps only valid rules: a known match, a text ReadLinkRuleText accepts,
// a Space that exists, and no repeat of an earlier rule's match and text. A
// Space's rules go when the Space does.
class ClairLinkRuleStore : public ClairSpaceStore::Observer {
 public:
  // browser_prefs.cc, through clair::RegisterLocalStatePrefs.
  static void RegisterPrefs(PrefRegistrySimple* registry);

  // The store, created on first use from the browser process's Local State.
  static ClairLinkRuleStore* Get();

  ClairLinkRuleStore(const ClairLinkRuleStore&) = delete;
  ClairLinkRuleStore& operator=(const ClairLinkRuleStore&) = delete;

  const std::vector<LinkRule>& rules() const { return rules_; }

  // Replaces every rule with `rules`, in their order, dropping invalid ones
  // and repeats. A rule keeps the ID of an identical rule it replaces, and
  // otherwise gets a new one.
  void Replace(std::vector<LinkRule> rules);

  // The first rule matching `link`, or null. Only http and https links match.
  const LinkRule* FirstMatch(const GURL& link) const;

  // ClairSpaceStore::Observer: drops the rules of Spaces that are gone.
  void OnSpacesChanged() override;

 private:
  friend class base::NoDestructor<ClairLinkRuleStore>;

  // It lives as long as the process, observing the Space store throughout.
  explicit ClairLinkRuleStore(PrefService* local_state);

  // Reads clair.link_rules, keeping only valid rules, and writes back what
  // it dropped.
  void Load();
  void Save();
  // `rules` without invalid rules and repeats, with their texts trimmed.
  static std::vector<LinkRule> Valid(std::vector<LinkRule> rules);

  const raw_ptr<PrefService> prefs_;
  std::vector<LinkRule> rules_;
};

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_LINK_RULE_STORE_H_

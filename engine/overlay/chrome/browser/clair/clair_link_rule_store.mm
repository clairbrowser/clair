// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_link_rule_store.h"

#include <algorithm>
#include <set>
#include <utility>

#include "base/check.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/strings/whitespace_constants.h"
#include "base/uuid.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace clair {

namespace {

constexpr int kVersion = 1;
constexpr char kVersionKey[] = "version";
constexpr char kRulesKey[] = "rules";
constexpr char kIDKey[] = "id";
constexpr char kMatchKey[] = "match";
constexpr char kTextKey[] = "text";
constexpr char kSpaceKey[] = "space";

constexpr char kContains[] = "contains";
constexpr char kExact[] = "exact";
constexpr char kPrefix[] = "prefix";

// Longer texts are dropped as invalid.
constexpr size_t kMaxTextLength = 2048;

std::optional<LinkRuleMatch> MatchFromString(std::string_view match) {
  if (match == kContains) {
    return LinkRuleMatch::kContains;
  }
  if (match == kExact) {
    return LinkRuleMatch::kExact;
  }
  if (match == kPrefix) {
    return LinkRuleMatch::kPrefix;
  }
  return std::nullopt;
}

const char* MatchToString(LinkRuleMatch match) {
  switch (match) {
    case LinkRuleMatch::kContains:
      return kContains;
    case LinkRuleMatch::kExact:
      return kExact;
    case LinkRuleMatch::kPrefix:
      return kPrefix;
  }
  return kContains;
}

// `text` without whitespace at either end, Unicode's included, as Swift's
// trimming in the dialog.
std::string Trim(std::string_view text) {
  return base::UTF16ToUTF8(
      base::TrimWhitespace(base::UTF8ToUTF16(text), base::TRIM_ALL));
}

// Whether `text` starts with "scheme://", a scheme being a letter followed
// by letters, digits, "+", "-" or ".".
bool HasScheme(std::string_view text) {
  const size_t separator = text.find("://");
  if (separator == std::string_view::npos || separator == 0 ||
      !base::IsAsciiAlpha(text[0])) {
    return false;
  }
  return std::ranges::all_of(text.substr(0, separator), [](char c) {
    return base::IsAsciiAlpha(c) || base::IsAsciiDigit(c) || c == '+' ||
           c == '-' || c == '.';
  });
}

// D3's comparison form: the spec without the fragment, and without the
// scheme and "://" when `scheme_free`.
std::string ComparisonForm(const GURL& url, bool scheme_free) {
  std::string spec = url.GetWithoutRef().spec();
  if (scheme_free) {
    const size_t separator = spec.find("://");
    if (separator != std::string::npos) {
      spec.erase(0, separator + 3);
    }
  }
  return spec;
}

}  // namespace

std::optional<LinkRuleURL> ReadLinkRuleText(std::string_view text) {
  const std::string trimmed = Trim(text);
  if (trimmed.empty() || trimmed.size() > kMaxTextLength ||
      base::UTF8ToUTF16(trimmed).find_first_of(base::kWhitespaceUTF16) !=
          std::u16string::npos) {
    return std::nullopt;
  }
  LinkRuleURL read;
  read.scheme_free = !HasScheme(trimmed);
  read.url = GURL(read.scheme_free ? "https://" + trimmed : trimmed);
  if (!read.url.is_valid() || !read.url.SchemeIsHTTPOrHTTPS() ||
      !read.url.has_host() || read.url.host().empty()) {
    return std::nullopt;
  }
  return read;
}

bool LinkRuleMatches(const LinkRule& rule, const GURL& link) {
  if (!link.is_valid() || !link.SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  const std::optional<LinkRuleURL> read = ReadLinkRuleText(rule.text);
  if (!read) {
    return false;
  }
  const std::string form = ComparisonForm(link, read->scheme_free);
  switch (rule.match) {
    case LinkRuleMatch::kContains:
      // The raw text, so a part of a host such as "meet.google" matches.
      return base::ToLowerASCII(form).find(base::ToLowerASCII(
                 Trim(rule.text))) != std::string::npos;
    case LinkRuleMatch::kExact:
      return form == ComparisonForm(read->url, read->scheme_free);
    case LinkRuleMatch::kPrefix:
      return form.starts_with(ComparisonForm(read->url, read->scheme_free));
  }
  return false;
}

// static
void ClairLinkRuleStore::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(kLinkRulesPref);
}

// static
ClairLinkRuleStore* ClairLinkRuleStore::Get() {
  static base::NoDestructor<ClairLinkRuleStore> store(
      g_browser_process->local_state());
  return store.get();
}

ClairLinkRuleStore::ClairLinkRuleStore(PrefService* local_state)
    : prefs_(local_state) {
  CHECK(prefs_);
  Load();
  ClairSpaceStore::Get()->AddObserver(this);
}

// static
std::vector<LinkRule> ClairLinkRuleStore::Valid(std::vector<LinkRule> rules) {
  ClairSpaceStore* spaces = ClairSpaceStore::Get();
  std::vector<LinkRule> valid;
  std::set<std::pair<LinkRuleMatch, std::string>> seen;
  for (LinkRule& rule : rules) {
    rule.text = Trim(rule.text);
    if (!ReadLinkRuleText(rule.text) || !spaces->Contains(rule.space) ||
        !seen.insert({rule.match, rule.text}).second) {
      continue;
    }
    valid.push_back(std::move(rule));
  }
  return valid;
}

void ClairLinkRuleStore::Load() {
  rules_.clear();
  const base::DictValue& stored = prefs_->GetDict(kLinkRulesPref);
  const base::ListValue* list = stored.FindList(kRulesKey);
  if (stored.FindInt(kVersionKey) != kVersion || !list) {
    return;
  }
  std::vector<LinkRule> read;
  std::set<std::string> ids;
  for (const base::Value& value : *list) {
    const base::DictValue* entry = value.GetIfDict();
    if (!entry) {
      continue;
    }
    const std::string* id = entry->FindString(kIDKey);
    const std::string* match = entry->FindString(kMatchKey);
    const std::string* text = entry->FindString(kTextKey);
    const std::string* space = entry->FindString(kSpaceKey);
    std::optional<LinkRuleMatch> parsed =
        match ? MatchFromString(*match) : std::nullopt;
    if (!id || !base::Uuid::ParseLowercase(*id).is_valid() ||
        !ids.insert(*id).second || !parsed || !text || !space) {
      continue;
    }
    read.push_back({*id, *parsed, *text, *space});
  }
  const size_t count = read.size();
  rules_ = Valid(std::move(read));
  // A crash between a Space's deletion and the pruning, or a hand edit, may
  // have left invalid rules: drop them for good.
  if (rules_.size() != count || count != list->size()) {
    Save();
  }
}

void ClairLinkRuleStore::Save() {
  base::ListValue list;
  for (const LinkRule& rule : rules_) {
    base::DictValue entry;
    entry.Set(kIDKey, rule.id);
    entry.Set(kMatchKey, MatchToString(rule.match));
    entry.Set(kTextKey, rule.text);
    entry.Set(kSpaceKey, rule.space);
    list.Append(std::move(entry));
  }
  base::DictValue stored;
  stored.Set(kVersionKey, kVersion);
  stored.Set(kRulesKey, std::move(list));
  prefs_->SetDict(kLinkRulesPref, std::move(stored));
}

void ClairLinkRuleStore::Replace(std::vector<LinkRule> rules) {
  std::vector<LinkRule> valid = Valid(std::move(rules));
  std::set<std::string> used;
  for (LinkRule& rule : valid) {
    auto same = std::ranges::find_if(rules_, [&](const LinkRule& old) {
      return old.match == rule.match && old.text == rule.text &&
             old.space == rule.space && !used.contains(old.id);
    });
    rule.id = same != rules_.end()
                  ? same->id
                  : base::Uuid::GenerateRandomV4().AsLowercaseString();
    used.insert(rule.id);
  }
  rules_ = std::move(valid);
  Save();
}

const LinkRule* ClairLinkRuleStore::FirstMatch(const GURL& link) const {
  auto it = std::ranges::find_if(
      rules_, [&](const LinkRule& rule) { return LinkRuleMatches(rule, link); });
  return it == rules_.end() ? nullptr : &*it;
}

void ClairLinkRuleStore::OnSpacesChanged() {
  ClairSpaceStore* spaces = ClairSpaceStore::Get();
  const size_t count = rules_.size();
  std::erase_if(rules_, [&](const LinkRule& rule) {
    return !spaces->Contains(rule.space);
  });
  if (rules_.size() != count) {
    Save();
  }
}

}  // namespace clair

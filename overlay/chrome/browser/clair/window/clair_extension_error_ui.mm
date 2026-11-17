// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_extension_error_ui.h"

#include <string>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/clair/clair_native_layer.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_extensions.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/grit/branded_strings.h"
#include "chrome/grit/generated_resources.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_set.h"
#include "ui/base/l10n/l10n_util.h"

@interface ClairChromiumExtensionAlert : NSObject <ClairExtensionPrompt>
@property(nonatomic) NSInteger promptID;
@property(nonatomic) ClairExtensionPromptKind kind;
@property(nonatomic, copy) NSString* extensionName;
@property(nonatomic, nullable) NSImage* icon;
@property(nonatomic, copy) NSArray<NSString*>* permissions;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* permissionsHeading;
@property(nonatomic, copy) NSString* acceptLabel;
@property(nonatomic, copy) NSString* cancelLabel;
@end

@implementation ClairChromiumExtensionAlert
@end

namespace clair {

namespace {

std::u16string DisplayName(const extensions::Extension& extension) {
  return extensions::ui_util::GetFixupExtensionNameForUIDisplay(
      extension.name());
}

// The alert's text. Extensions blocked by enterprise policy keep Chromium's
// wording (extension_error_ui_desktop.cc's GenerateTitle and GenerateMessage);
// malware gets Clair's.
struct AlertText {
  std::u16string title;
  std::vector<std::u16string> lines;
};

AlertText MakeAlertText(extensions::ExtensionErrorUI::Delegate* delegate) {
  const extensions::ExtensionSet& forbidden =
      delegate->GetBlocklistedExtensions();
  extensions::ManagementPolicy* policy =
      extensions::ExtensionSystem::Get(delegate->GetContext())
          ->management_policy();
  bool blocked_by_policy = false;
  for (const auto& extension : forbidden) {
    if (policy && !policy->UserMayLoad(extension.get())) {
      blocked_by_policy = true;
    }
  }

  AlertText text;
  if (blocked_by_policy) {
    text.title = l10n_util::GetPluralStringFUTF16(
        IDS_POLICY_BLOCKED_EXTENSION_ALERT_TITLE,
        static_cast<int>(forbidden.size()));
    if (forbidden.size() > 1) {
      text.lines.push_back(l10n_util::GetStringUTF16(
          IDS_POLICY_BLOCKED_EXTENSIONS_ALERT_ITEM_TITLE));
      for (const auto& extension : forbidden) {
        text.lines.push_back(
            l10n_util::GetStringFUTF16(IDS_BLOCKLISTED_EXTENSIONS_ALERT_ITEM,
                                       DisplayName(*extension)));
      }
    } else {
      text.lines.push_back(l10n_util::GetStringFUTF16(
          IDS_POLICY_BLOCKED_EXTENSION_ALERT_ITEM_DETAIL,
          DisplayName(**forbidden.begin())));
    }
    return text;
  }

  // Malware: Clair's own wording, in English like the rest of ClairUI. One
  // extension is named in the title; several are listed under it.
  if (forbidden.size() == 1) {
    text.title = u"“" + DisplayName(**forbidden.begin()) +
                 u"” contains malware and was turned off for your safety.";
    return text;
  }
  text.title =
      u"These extensions contain malware and were turned off for your safety.";
  for (const auto& extension : forbidden) {
    text.lines.push_back(DisplayName(*extension));
  }
  return text;
}

class ClairExtensionErrorUI : public extensions::ExtensionErrorUI,
                              public BrowserCollectionObserver {
 public:
  explicit ClairExtensionErrorUI(
      extensions::ExtensionErrorUI::Delegate* delegate)
      : delegate_(delegate),
        profile_(Profile::FromBrowserContext(delegate->GetContext())) {}
  ClairExtensionErrorUI(const ClairExtensionErrorUI&) = delete;
  ClairExtensionErrorUI& operator=(const ClairExtensionErrorUI&) = delete;

  ~ClairExtensionErrorUI() override {
    if (owner_) {
      owner_->DismissPrompt(prompt_id_);
    }
  }

  // ExtensionErrorUI:
  bool ShowErrorInBubbleView() override {
    // Chromium's returns false with no window, which drops the alert until
    // the next launch. This one shows it on the profile's next window.
    if (!TryShow()) {
      browsers_observation_.Observe(GlobalBrowserCollection::GetInstance());
    }
    return true;
  }

  // The alert has no Details button: chrome://extensions is a menu item away.
  void ShowExtensions() override {}

  // The delegate calls this from OnAlertAccept(). OnAlertClosed()
  // acknowledges the extensions and deletes this.
  void Close() override {
    if (owner_) {
      owner_->DismissPrompt(prompt_id_);
      owner_.reset();
    }
    delegate_->OnAlertClosed();
  }

  // BrowserCollectionObserver:
  void OnBrowserActivated(BrowserWindowInterface* browser) override {
    if (browser->GetProfile() == profile_ && TryShow()) {
      browsers_observation_.Reset();
    }
  }

 private:
  // Shows the alert on the profile's frontmost native window. False when it
  // has none.
  bool TryShow() {
    ClairExtensions* owner = nullptr;
    ProfileBrowserCollection::GetForProfile(profile_)->ForEach(
        [&](BrowserWindowInterface* browser) {
          ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
          if (window && window->extensions()) {
            owner = window->extensions();
            return false;
          }
          return true;
        },
        BrowserCollection::Order::kActivation);
    if (!owner) {
      return false;
    }

    AlertText text = MakeAlertText(delegate_);
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (const std::u16string& line : text.lines) {
      [lines addObject:base::SysUTF16ToNSString(line)];
    }
    ClairChromiumExtensionAlert* alert =
        [[ClairChromiumExtensionAlert alloc] init];
    alert.promptID = owner->NewPromptID();
    alert.kind = ClairExtensionPromptKindOther;
    const extensions::ExtensionSet& forbidden =
        delegate_->GetBlocklistedExtensions();
    alert.extensionName =
        forbidden.size() == 1
            ? base::SysUTF16ToNSString(DisplayName(**forbidden.begin()))
            : @"";
    alert.permissions = lines;
    alert.title = base::SysUTF16ToNSString(text.title);
    alert.permissionsHeading = @"";
    alert.acceptLabel =
        base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_EXTENSION_ALERT_ITEM_OK));
    // No cancel label: ClairUI shows OK alone, and Esc still answers.
    alert.cancelLabel = @"";

    owner_ = owner->AsWeakPtr();
    prompt_id_ = static_cast<int>(alert.promptID);
    owner->ShowPrompt(alert,
                      base::BindOnce(&ClairExtensionErrorUI::Answered,
                                     weak_factory_.GetWeakPtr()));
    return true;
  }

  // OK, Esc or the window closing. As in Chromium, OK goes through
  // OnAlertAccept() and the others close the alert; both acknowledge the
  // extensions and delete this.
  void Answered(bool accepted) {
    owner_.reset();
    if (accepted) {
      delegate_->OnAlertAccept();
    } else {
      delegate_->OnAlertClosed();
    }
  }

  const raw_ptr<extensions::ExtensionErrorUI::Delegate> delegate_;
  const raw_ptr<Profile> profile_;
  base::WeakPtr<ClairExtensions> owner_;
  int prompt_id_ = 0;
  base::ScopedObservation<GlobalBrowserCollection, BrowserCollectionObserver>
      browsers_observation_{this};
  base::WeakPtrFactory<ClairExtensionErrorUI> weak_factory_{this};
};

}  // namespace

extensions::ExtensionErrorUI* CreateExtensionErrorUI(
    extensions::ExtensionErrorUI::Delegate* delegate) {
  if (!IsNativeLayerRunning()) {
    return nullptr;
  }
  return new ClairExtensionErrorUI(delegate);
}

}  // namespace clair

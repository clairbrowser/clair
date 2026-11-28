// Copyright 2026 The Clair Authors
// This Source Code Form is subject to the terms of the Mozilla Public License,
// v. 2.0. If a copy of the MPL was not distributed with this file, You can
// obtain one at https://mozilla.org/MPL/2.0/.
//
// Adapted in part from Crest's CrestBrowserWindow (pauljoda/Crest, MPL-2.0),
// which adapts Mori's (MIT, see CREDITS.md), and from Chromium's own
// WebUIBrowserWindow and BrowserNativeWidgetMac (BSD-3-Clause).

#include "chrome/browser/clair/window/clair_browser_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <type_traits>
#include <vector>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/ref_counted.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/clair_bookmark_bar_drain.h"
#include "chrome/browser/clair/clair_native_layer.h"
#import "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#import "chrome/browser/clair/window/clair_browser_bridge.h"
#include "chrome/browser/clair/window/clair_downloads.h"
#include "chrome/browser/clair/window/clair_extensions.h"
#import "chrome/browser/clair/window/clair_native_window.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/clair/window/clair_space_session.h"
#include "chrome/browser/clair/window/clair_tab_preview.h"
#include "chrome/browser/clair/window/clair_window_group.h"
#include "chrome/browser/clair/window/clair_window_hooks.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/global_keyboard_shortcuts_mac.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/clair/window/clair_splits.h"
#include "chrome/browser/ui/browser_window_state.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar_controller.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "chrome/browser/ui/views/download/download_in_progress_dialog_view.h"
#include "chrome/browser/ui/window_metadata/window_metadata_controller.h"
#include "chrome/browser/ui/zoom/browser_window_zoom_observer.h"
#include "chrome/common/webui_url_constants.h"
#include "chrome/grit/generated_resources.h"
#include "components/find_in_page/find_notification_details.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/tab_interface.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "components/web_modal/modal_dialog_host.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/common/referrer.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/url_constants.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/base/page_transition_types.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/gfx/range/range.h"
#include "ui/native_theme/native_theme.h"
#include "url/gurl.h"

static_assert(!std::is_abstract_v<ClairBrowserWindow>);

ClairTakeOptions::ClairTakeOptions() = default;
ClairTakeOptions::ClairTakeOptions(ClairTakeOptions&&) = default;
ClairTakeOptions& ClairTakeOptions::operator=(ClairTakeOptions&&) = default;
ClairTakeOptions::~ClairTakeOptions() = default;

namespace {

// The browsers shown in native windows.
std::map<const BrowserWindowInterface*, ClairBrowserWindow*>& NativeWindows() {
  static base::NoDestructor<
      std::map<const BrowserWindowInterface*, ClairBrowserWindow*>>
      windows;
  return *windows;
}

// D9: a feature the native window doesn't host does nothing, and says so once.
void LogUnavailable(const char* feature) {
  static base::NoDestructor<std::set<std::string>> logged;
  if (logged->insert(feature).second) {
    LOG(WARNING) << "Clair: " << feature
                 << " isn't available in the native window";
  }
}

// D17: passwords and autofill are off, so their bubbles never show.
class ClairAutofillBubbleHandler : public autofill::AutofillBubbleHandler {
 public:
  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(
      content::WebContents*, autofill::SaveCardBubbleController*, bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowIbanBubble(content::WebContents*,
                                               autofill::IbanBubbleController*,
                                               bool,
                                               autofill::IbanBubbleType) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowOfferNotificationBubble(
      content::WebContents*,
      autofill::OfferNotificationBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveAutofillAiDataBubble(
      content::WebContents*,
      autofill::AutofillAiImportDataController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowAutofillAiLocalSaveNotification(
      content::WebContents*,
      autofill::AutofillAiImportDataController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents*,
      std::unique_ptr<autofill::SaveAddressBubbleController>,
      bool) override {
    return Unavailable();
  }
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowAddressSignInPromo(
      content::WebContents*,
      const autofill::AutofillProfile&) override {
    return Unavailable();
  }
#endif
  autofill::AutofillBubbleBase* ShowUpdateAddressProfileBubble(
      content::WebContents*,
      std::unique_ptr<autofill::UpdateAddressBubbleController>,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowFilledCardInformationBubble(
      content::WebContents*,
      autofill::FilledCardInformationBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollBubble(
      content::WebContents*,
      autofill::VirtualCardEnrollBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollConfirmationBubble(
      content::WebContents*,
      autofill::VirtualCardEnrollBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowMandatoryReauthBubble(
      content::WebContents*,
      autofill::MandatoryReauthBubbleController*,
      bool,
      autofill::MandatoryReauthBubbleType) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveCardConfirmationBubble(
      content::WebContents*,
      autofill::SaveCardBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveIbanConfirmationBubble(
      content::WebContents*,
      autofill::IbanBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowOmniboxAutofillBubble(
      content::WebContents*,
      autofill::OmniboxAutofillBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersBubble(
      content::WebContents*,
      autofill::PaymentsChurnedUsersBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersConfirmationBubble(
      content::WebContents*,
      autofill::PaymentsChurnedUsersBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowWalletReminderNoticeBubble(
      content::WebContents*,
      autofill::WalletReminderNoticeBubbleController*,
      bool) override {
    return Unavailable();
  }

 private:
  static autofill::AutofillBubbleBase* Unavailable() {
    LogUnavailable("Autofill");
    return nullptr;
  }
};

// Whether the browser should handle a key the page didn't, as
// BrowserNativeWidgetMac decides.
bool ShouldHandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled ||
      event.GetType() == input::NativeWebKeyboardEvent::Type::kChar) {
    return false;
  }
  return event.os_event && event.os_event.Get().type == NSEventTypeKeyDown;
}

NSRect ToNSRect(const gfx::Rect& rect) {
  return gfx::ScreenRectToNSRect(rect);
}

}  // namespace

// --- ClairLocationBar --------------------------------------------------------

ClairLocationBar::ClairLocationBar(ClairBrowserWindow* window)
    : LocationBar(nullptr), window_(window) {}

ClairLocationBar::~ClairLocationBar() = default;

void ClairLocationBar::FocusLocation(bool is_user_initiated,
                                     bool clear_focus_if_failed) {
  window_->SetFocusToLocationBar(is_user_initiated);
}

void ClairLocationBar::FocusSearch() {
  window_->SetFocusToLocationBar(true);
}

void ClairLocationBar::AnnounceAlert(const std::u16string& announcement) {}
void ClairLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}

void ClairLocationBar::UpdateContentSettingsIcons() {
  // A permission was used or blocked: the URL field's indicators change.
  if (content::WebContents* active =
          window_->browser()->tab_strip_model()->GetActiveWebContents()) {
    [window_->bridge() tabChanged:active];
  }
}

void ClairLocationBar::SaveStateToContents(content::WebContents* contents) {}
void ClairLocationBar::Revert() {}
OmniboxView* ClairLocationBar::GetOmniboxView() {
  return nullptr;
}
OmniboxPopupView* ClairLocationBar::GetOmniboxPopupView() {
  return nullptr;
}
OmniboxController* ClairLocationBar::GetOmniboxController() {
  return nullptr;
}
bool ClairLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent* event) {
  return false;
}
content::WebContents* ClairLocationBar::GetWebContents() {
  return window_->browser()->tab_strip_model()->GetActiveWebContents();
}
LocationBarModel* ClairLocationBar::GetLocationBarModel() {
  return nullptr;
}
std::optional<bubble_anchor_util::AnchorConfiguration>
ClairLocationBar::GetChipAnchor() {
  return std::nullopt;
}
ChipController* ClairLocationBar::GetChipController() {
  return nullptr;
}
void ClairLocationBar::OnChanged() {}
void ClairLocationBar::UpdateWithoutTabRestore() {}
ui::TrackedElement* ClairLocationBar::GetAnchorOrNull() {
  return nullptr;
}
BrowserWindowInterface* ClairLocationBar::GetBrowser() {
  return window_->browser();
}
Profile* ClairLocationBar::GetProfile() {
  return window_->browser()->GetProfile();
}
bool ClairLocationBar::IsInitialized() const {
  return true;
}
bool ClairLocationBar::IsVisible() const {
  return false;
}
bool ClairLocationBar::IsDrawn() const {
  return false;
}
bool ClairLocationBar::IsFullscreen() const {
  return window_->IsFullscreen();
}
bool ClairLocationBar::IsEditingOrEmpty() const {
  return false;
}
bool ClairLocationBar::IsMouseHovered() const {
  return false;
}
bool ClairLocationBar::IsFocusWithin() const {
  return false;
}
void ClairLocationBar::InvalidateLayout() {}
gfx::Rect ClairLocationBar::Bounds() const {
  return gfx::Rect();
}
gfx::Rect ClairLocationBar::BoundsInScreen() const {
  return window_->SiteControlsAnchorInScreen();
}
gfx::Size ClairLocationBar::MinimumSize() const {
  return gfx::Size();
}
gfx::Size ClairLocationBar::PreferredSize() const {
  return gfx::Size();
}
void ClairLocationBar::Update(content::WebContents* contents) {
  if (contents) {
    [window_->bridge() tabChanged:contents];
  }
}
void ClairLocationBar::ResetTabState(content::WebContents* contents) {}
bool ClairLocationBar::HasSecurityStateChanged() {
  return false;
}
LocationBarTesting* ClairLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

// --- ClairFindBar ------------------------------------------------------------

ClairFindBar::ClairFindBar(ClairBrowserWindow* window) : window_(window) {}

ClairFindBar::~ClairFindBar() {
  if (window_->find_bar() == this) {
    window_->ForgetFindBar();
  }
}

FindBarController* ClairFindBar::GetFindBarController() const {
  return controller_;
}

void ClairFindBar::SetFindBarController(FindBarController* find_bar_controller) {
  controller_ = find_bar_controller;
}

void ClairFindBar::Show(bool animate, bool focus) {
  visible_ = true;
  [window_->clair_window() showFindWithText:base::SysUTF16ToNSString(text_)];
}

void ClairFindBar::Hide(bool animate) {
  if (!visible_) {
    return;
  }
  visible_ = false;
  [window_->clair_window() hideFind];
}

void ClairFindBar::SetFocusAndSelection() {}

void ClairFindBar::ClearResults(
    const find_in_page::FindNotificationDetails& results) {
  [window_->clair_window() findResultDidChange:ClairFindResult{0, 0, true}];
}

void ClairFindBar::StopAnimation() {}
void ClairFindBar::MoveWindowIfNecessary() {}

void ClairFindBar::SetFindTextAndSelectedRange(const std::u16string& find_text,
                                               const gfx::Range& selected_range) {
  text_ = find_text;
  selected_range_ = selected_range;
}

std::u16string_view ClairFindBar::GetFindText() const {
  return text_;
}

gfx::Range ClairFindBar::GetSelectedRange() const {
  return selected_range_;
}

void ClairFindBar::UpdateUIForFindResult(
    const find_in_page::FindNotificationDetails& result,
    const std::u16string& find_text) {
  if (!find_text.empty()) {
    text_ = find_text;
  }
  [window_->clair_window()
      findResultDidChange:ClairFindResult{
                              std::max(result.active_match_ordinal(), 0),
                              std::max(result.number_of_matches(), 0),
                              result.final_update()}];
}

void ClairFindBar::AudibleAlert() {
  NSBeep();
}

bool ClairFindBar::IsFindBarVisible() const {
  return visible_;
}

void ClairFindBar::RestoreSavedFocus() {
  if (content::WebContents* active =
          window_->browser()->tab_strip_model()->GetActiveWebContents()) {
    active->Focus();
  }
}

bool ClairFindBar::HasGlobalFindPasteboard() const {
  return false;
}

void ClairFindBar::UpdateFindBarForChangedWebContents() {}

bool ClairFindBar::CanPopulateFromSelectedText() {
  return true;
}

const FindBarTesting* ClairFindBar::GetFindBarTesting() const {
  return nullptr;
}

bool ClairFindBar::HasFocus() const {
  return visible_;
}

void ClairFindBar::CloseOverlappingBubbles() {}

views::Widget* ClairFindBar::GetHostWidget() {
  return nullptr;
}

void ClairFindBar::FindFromField(const std::u16string& text, bool forward) {
  content::WebContents* active =
      window_->browser()->tab_strip_model()->GetActiveWebContents();
  auto* helper =
      active ? find_in_page::FindTabHelper::FromWebContents(active) : nullptr;
  if (!helper) {
    return;
  }
  if (controller_ && text != text_) {
    controller_->OnUserChangedFindText(text);
  }
  text_ = text;
  if (text.empty()) {
    helper->StopFinding(find_in_page::SelectionAction::kClear);
    ClearResults(helper->find_result());
    return;
  }
  helper->StartFinding(text, forward, /*case_sensitive=*/false,
                       /*find_match=*/true);
}

void ClairFindBar::EndFromField() {
  if (controller_) {
    controller_->EndFindSession(find_in_page::SelectionAction::kKeep,
                                find_in_page::ResultAction::kKeep);
  }
}

// --- ClairExclusiveAccessContext ---------------------------------------------

ClairExclusiveAccessContext::ClairExclusiveAccessContext(
    ClairBrowserWindow* window)
    : window_(window) {}

ClairExclusiveAccessContext::~ClairExclusiveAccessContext() {
  notice_timer_.Stop();
  if (notice_hide_callback_) {
    std::move(notice_hide_callback_)
        .Run(ExclusiveAccessBubbleHideReason::kInterrupted);
  }
}

Profile* ClairExclusiveAccessContext::GetProfile() {
  return window_->browser()->GetProfile();
}

bool ClairExclusiveAccessContext::IsFullscreen() const {
  return window_->IsFullscreen();
}

void ClairExclusiveAccessContext::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {
  // add-profiles D3: a member its group keeps hidden stays as it is, whoever
  // asks (an extension's chrome.windows.update, DevTools): its window never
  // shows on its own, and the group's full screen is the shown member's.
  // Chromium's request ends once it has returned, so that it does not wait
  // for a transition that never comes.
  if (window_->IsHiddenMember()) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ClairBrowserWindow> window) {
                         if (!window || !window->IsHiddenMember()) {
                           return;
                         }
                         if (auto* manager = ExclusiveAccessManager::From(
                                 window->browser())) {
                           manager->ExitExclusiveAccess();
                         }
                       },
                       window_->GetWeakPtr()));
    return;
  }
  // Only a page's own request shows the page alone. The browser's full screen
  // keeps the sidebar.
  if (!exclusive_access_bubble::IsExclusiveAccessModeBrowserFullscreen(
          bubble_type)) {
    SetPageFullscreen(true);
  }
  // add-profiles D4: the group's full-screen window, while this one covers
  // it.
  NSWindow* window = window_->FullscreenNSWindow();
  if (!(window.styleMask & NSWindowStyleMaskFullScreen)) {
    entered_window_fullscreen_ = true;
    entering_window_fullscreen_ = true;
    // The notice shows once the window is in full screen.
    [window toggleFullScreen:nil];
    return;
  }
  UpdateExclusiveAccessBubble({.origin = origin, .type = bubble_type}, {});
}

void ClairExclusiveAccessContext::ExitFullscreen() {
  // Without a page in full screen, Chromium is leaving the window's own,
  // however it was entered, as when Esc is held (arc-popup-notices D3).
  const bool window_fullscreen_only = !page_fullscreen_;
  SetPageFullscreen(false);
  HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
  // add-profiles D4: the group's full-screen window, while this one covers
  // it. A cover leaves the group's full screen only when asked to by the
  // user (IDC_FULLSCREEN, toggleFullScreen:, holding Esc), never with a
  // page's.
  NSWindow* window = window_->FullscreenNSWindow();
  // A page leaves only what entering changed: a window already in full
  // screen stays. add-profiles D3, D4: so does a hidden member's, as the
  // full-screen owner under a cover, whose full screen the cover now shows.
  if ((entered_window_fullscreen_ || window_fullscreen_only) &&
      !window_->IsHiddenMember() &&
      (window.styleMask & NSWindowStyleMaskFullScreen)) {
    [window toggleFullScreen:nil];
  }
  entered_window_fullscreen_ = false;
}

bool ClairExclusiveAccessContext::DeferExitWhileEntering(NSEvent* event) {
  if (!entering_window_fullscreen_ || event.keyCode != 53 /* kVK_Escape */) {
    return false;
  }
  if (event.type == NSEventTypeKeyDown) {
    exit_when_entered_ = true;
  }
  return true;
}

bool ClairExclusiveAccessContext::CountEscapeTap(NSEvent* event) {
  // Only the window's own full screen: a page's leaves on one Esc.
  if (page_fullscreen_ || !window_->IsFullscreen()) {
    return false;
  }
  constexpr NSEventModifierFlags kModifiers =
      NSEventModifierFlagShift | NSEventModifierFlagControl |
      NSEventModifierFlagOption | NSEventModifierFlagCommand;
  if (!event || event.type != NSEventTypeKeyDown ||
      event.keyCode != 53 /* kVK_Escape */ || event.isARepeat ||
      (event.modifierFlags & kModifiers)) {
    return false;
  }
  // A page's Esc that Chromium gives back to the window unhandled reaches
  // cancelOperation: too, as the same event.
  if (event.timestamp == last_escape_tap_) {
    return true;
  }
  const NSTimeInterval previous = last_escape_tap_;
  last_escape_tap_ = event.timestamp;
  // Arc's time between the taps' key-downs: 0.22 s left full screen, 0.24 s
  // didn't.
  constexpr NSTimeInterval kDoubleTapTime = 0.23;
  if (previous > 0 && event.timestamp - previous < kDoubleTapTime) {
    last_escape_tap_ = 0;
    if (auto* manager = ExclusiveAccessManager::From(window_->browser())) {
      manager->fullscreen_controller()->ToggleBrowserFullscreenMode(
          /*user_initiated=*/true);
    }
    return true;
  }
  // An exclusive-access notice, so the end of full screen hides it.
  [window_->clair_window()
      showExclusiveAccessNotice:@"|esc| again to exit fullscreen"];
  notice_in_popup_ = true;
  return true;
}

void ClairExclusiveAccessContext::WindowFullscreenChanged(bool entered) {
  entering_window_fullscreen_ = false;
  last_escape_tap_ = 0;
  if (entered && exit_when_entered_) {
    exit_when_entered_ = false;
    if (auto* manager = ExclusiveAccessManager::From(window_->browser())) {
      manager->ExitExclusiveAccess();
      return;
    }
  }
  exit_when_entered_ = false;
  // Chromium hears every transition, as from its own windows: leaving full
  // screen by the green button or the menu ends the page's full screen too.
  if (auto* manager = ExclusiveAccessManager::From(window_->browser())) {
    manager->fullscreen_controller()->WindowFullscreenStateChanged();
  }
  if (!entered) {
    entered_window_fullscreen_ = false;
    SetPageFullscreen(false);
    HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
  }
}

void ClairExclusiveAccessContext::UpdateUIForTabFullscreen() {
  // A page entering or leaving full screen in a window already in full screen:
  // only what the card shows changes.
  auto* manager = ExclusiveAccessManager::From(window_->browser());
  content::WebContents* contents = GetWebContentsForExclusiveAccess();
  SetPageFullscreen(manager && contents &&
                    manager->fullscreen_controller()->exclusive_access_tab() ==
                        contents);
}

void ClairExclusiveAccessContext::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  // arc-popup-notices D7: a download alone, in full screen or a pointer lock,
  // keeps the popup as it is.
  if (params.type == EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE) {
    if (first_hide_callback) {
      std::move(first_hide_callback)
          .Run(ExclusiveAccessBubbleHideReason::kNotShown);
    }
    if (!params.has_download) {
      HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
    }
    return;
  }
  // The new notice replaces the one showing in the popup, so ClairUI isn't
  // told to hide it first.
  notice_timer_.Stop();
  if (notice_hide_callback_) {
    std::move(notice_hide_callback_)
        .Run(ExclusiveAccessBubbleHideReason::kInterrupted);
  }
  // arc-popup-notices D1-D3, D7: Arc's wording for a hidden cursor, every
  // key as "esc", the window's own full screen too, and no download.
  const std::u16string text =
      params.type == EXCLUSIVE_ACCESS_BUBBLE_TYPE_POINTERLOCK_EXIT_INSTRUCTION
          ? std::u16string(u"Your cursor is hidden. Press |esc| to show cursor.")
          : exclusive_access_bubble::GetInstructionTextForType(
                params.type, u"esc", std::nullopt, /*has_download=*/false,
                /*notify_overridden=*/false);
  [window_->clair_window()
      showExclusiveAccessNotice:base::SysUTF16ToNSString(text)];
  notice_visible_ = true;
  notice_in_popup_ = true;
  notice_hide_callback_ = std::move(first_hide_callback);
  // arc-popup-notices D6: ClairUI times the popup. This timer keeps Chromium's
  // bookkeeping as its own bubble would.
  notice_timer_.Start(
      FROM_HERE, ExclusiveAccessBubble::kShowTime,
      base::BindOnce(&ClairExclusiveAccessContext::NoticeTimedOut,
                     base::Unretained(this)));
}

bool ClairExclusiveAccessContext::IsExclusiveAccessBubbleDisplayed() const {
  return notice_visible_;
}

void ClairExclusiveAccessContext::OnExclusiveAccessUserInput() {}

content::WebContents*
ClairExclusiveAccessContext::GetWebContentsForExclusiveAccess() {
  return window_->browser()->tab_strip_model()->GetActiveWebContents();
}

bool ClairExclusiveAccessContext::CanUserEnterFullscreen() const {
  return true;
}

bool ClairExclusiveAccessContext::CanUserExitFullscreen() const {
  return true;
}

void ClairExclusiveAccessContext::SetPageFullscreen(bool fullscreen) {
  if (page_fullscreen_ == fullscreen) {
    return;
  }
  page_fullscreen_ = fullscreen;
  [window_->clair_window() pageFullscreenDidChange:fullscreen];
}

void ClairExclusiveAccessContext::HideNotice(
    ExclusiveAccessBubbleHideReason reason) {
  notice_timer_.Stop();
  notice_visible_ = false;
  if (notice_in_popup_) {
    notice_in_popup_ = false;
    [window_->clair_window() showExclusiveAccessNotice:nil];
  }
  if (notice_hide_callback_) {
    std::move(notice_hide_callback_).Run(reason);
  }
}

void ClairExclusiveAccessContext::NoticeTimedOut() {
  // The popup hides by itself in ClairUI's time; until then, the end of the
  // mode still hides it.
  notice_visible_ = false;
  if (notice_hide_callback_) {
    std::move(notice_hide_callback_)
        .Run(ExclusiveAccessBubbleHideReason::kTimeout);
  }
}

// --- ClairModalDialogHost ----------------------------------------------------

ClairModalDialogHost::ClairModalDialogHost(ClairBrowserWindow* window)
    : window_(window) {}

ClairModalDialogHost::~ClairModalDialogHost() {
  for (auto& observer : observers_) {
    observer.OnHostDestroying();
  }
}

// The host view is the window's content view, which Chromium also uses as
// the parent of browser-modal dialogs (`platform_util::GetViewForWindow`), so
// both kinds of dialog share one host. They're placed over the card.
gfx::NativeView ClairModalDialogHost::GetHostView() const {
  return gfx::NativeView(window_->ns_window().contentView);
}

// The card's frame in the content view, top-left origin.
gfx::Rect ClairModalDialogHost::CardRect() const {
  NSView* content = window_->ns_window().contentView;
  if (!content) {
    return gfx::Rect();
  }
  id<ClairWindow> window = window_->clair_window();
  NSView* card = window ? window.pageContainerView : nil;
  NSRect rect = card && card.window == content.window
                    ? [content convertRect:card.bounds fromView:card]
                    : content.bounds;
  if (!content.flipped) {
    rect.origin.y = NSHeight(content.bounds) - NSMaxY(rect);
  }
  return gfx::Rect(NSMinX(rect), NSMinY(rect), NSWidth(rect), NSHeight(rect));
}

gfx::Point ClairModalDialogHost::GetDialogPosition(const gfx::Size& size) {
  const gfx::Rect card = CardRect();
  return gfx::Point(card.x() + std::max(0, (card.width() - size.width()) / 2),
                    card.y());
}

gfx::Size ClairModalDialogHost::GetMaximumDialogSize() {
  return CardRect().size();
}

void ClairModalDialogHost::AddObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.AddObserver(observer);
}

void ClairModalDialogHost::RemoveObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.RemoveObserver(observer);
}

void ClairModalDialogHost::NotifyPositionRequiresUpdate() {
  for (auto& observer : observers_) {
    observer.OnPositionRequiresUpdate();
  }
}

// --- ClairStatusBubble -------------------------------------------------------

ClairStatusBubble::ClairStatusBubble(ClairBrowserWindow* window)
    : window_(window) {}

ClairStatusBubble::~ClairStatusBubble() = default;

void ClairStatusBubble::SetStatus(const std::u16string& status) {
  status_ = status;
  Update();
}

void ClairStatusBubble::SetURL(const GURL& url) {
  url_ = url.is_empty() ? std::u16string() : base::UTF8ToUTF16(url.spec());
  url_tab_ = -1;
  Update();
}

void ClairStatusBubble::SetURL(const GURL& url, content::WebContents* source) {
  url_ = url.is_empty() ? std::u16string() : base::UTF8ToUTF16(url.spec());
  url_tab_ = source ? clair::TabIDOf(source) : -1;
  Update();
}

void ClairStatusBubble::Hide() {
  status_.clear();
  url_.clear();
  url_tab_ = -1;
  Update();
}

void ClairStatusBubble::MouseMoved(bool left_content) {}

void ClairStatusBubble::Update() {
  const bool is_link = status_.empty() && !url_.empty();
  const std::u16string& text = status_.empty() ? url_ : status_;
  // add-split-view D13a: the page the text is for, which places the capsule
  // in its pane.
  content::WebContents* active =
      window_->browser()->tab_strip_model()->GetActiveWebContents();
  const ClairTabID tab =
      is_link && url_tab_ >= 0
          ? static_cast<ClairTabID>(url_tab_)
          : (active ? clair::TabIDOf(active) : ClairTabIDNone);
  [window_->clair_window()
      statusTextDidChange:text.empty() ? nil : base::SysUTF16ToNSString(text)
                   isLink:is_link
                      tab:tab];
}

// --- ClairBrowserWindow ------------------------------------------------------

ClairBrowserWindow::ClairBrowserWindow(Browser* browser)
    : browser_(browser),
      location_bar_(this),
      modal_dialog_host_(this),
      exclusive_access_context_(this),
      status_bubble_(this),
      autofill_bubble_handler_(std::make_unique<ClairAutofillBubbleHandler>()) {
  NativeWindows()[browser] = this;

  gfx::Rect bounds;
  ui::mojom::WindowShowState show_state = ui::mojom::WindowShowState::kDefault;
  chrome::GetSavedWindowBoundsAndShowState(browser, &bounds, &show_state);
  initial_show_state_ = show_state;
  restored_bounds_ = bounds;
  ns_window_ = [[ClairNativeWindow alloc] initWithBrowserWindow:this
                                                    contentRect:ToNSRect(bounds)];
  [ns_window_ setFrame:ToNSRect(bounds) display:NO];

  // add-profiles D3: the window joins the group creating it, or starts one.
  ClairWindowGroup::Join(this);
  // add-spaces D3, add-profiles D8: a new window shows the Space last shown
  // in a key window, which is the Space of the window it was opened from,
  // when it's of the window's profile; or else the profile's Space shown
  // most recently, or its first. A member its group creates waits for the
  // group to show a Space. An incognito or guest window shows its profile's
  // own.
  space_tabs_ = ClairSpaceTabs::ForProfile(browser->GetProfile());
  if (!space_tabs_->is_regular()) {
    shown_space_ = space_tabs_->private_space();
  } else if (!IsHiddenMember()) {
    shown_space_ = ClairWindowGroup::SpaceForNewWindow(browser->GetProfile());
    hands_over_ = shown_space_.empty();
  }

  bridge_ = [[ClairChromiumBrowser alloc] initWithBrowserWindow:this];
  // Before the Peeks, so the lists hear of a tab before it's linked.
  space_tabs_->AddBrowser(this);
  extensions_ = std::make_unique<ClairExtensions>(this);
  downloads_ = std::make_unique<ClairDownloads>(this);
  // After the bridge, so the bridge hears of tab strip changes first.
  peeks_ = std::make_unique<ClairPeeks>(this);
  // add-split-view D1: after the Peeks, whose placing it relies on.
  splits_ = std::make_unique<ClairSplits>(this);
  clair::ApplyPasswordAndAutofillOverrides(browser->GetProfile());

  // D2: ClairUI returns a window for every browser. A nil window is a bug that
  // must not go unnoticed, so Clair stops rather than show Chromium's window.
  clair_window_ = clair::CreateClairWindow(bridge_);
  CHECK(clair_window_) << "ClairUI returned no window for a browser";
  [bridge_ attachWindow:clair_window_];
  // add-bookmarks-menu D6: the profile's Bookmarks Bar stays empty.
  ClairBookmarkBarDrain::WindowOpened(this);

  if (auto* zoom = BrowserWindowZoomObserver::From(browser)) {
    zoom_subscription_ = zoom->RegisterZoomChangedCallback(base::BindRepeating(
        &ClairBrowserWindow::ZoomChanged, weak_factory_.GetWeakPtr()));
  }

  // add-profiles D8: a window of a profile no Space uses hands its pages to
  // clair.last_space and closes, once Chromium has given it its tabs.
  if (hands_over_) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ClairBrowserWindow> window) {
                         if (window) {
                           ClairWindowGroup::HandOverToLastSpace(window.get());
                         }
                       },
                       weak_factory_.GetWeakPtr()));
  }
}

ClairBrowserWindow::~ClairBrowserWindow() {
  ClairWindowGroup::Leave(this);
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  splits_.reset();
  peeks_.reset();
  if (space_tabs_) {
    space_tabs_->RemoveBrowser(this);
    space_tabs_ = nullptr;
  }
  DetachFromClairUI();
  zoom_subscription_ = {};
  extensions_.reset();
  downloads_.reset();
  [ns_window_ detachBrowserWindow];
  [ns_window_ orderOut:nil];
  [ns_window_ close];
  NativeWindows().erase(browser_);
}

// static
ClairBrowserWindow* ClairBrowserWindow::FromBrowser(
    const BrowserWindowInterface* browser) {
  auto found = NativeWindows().find(browser);
  return found == NativeWindows().end() ? nullptr : found->second;
}

// static
ClairBrowserWindow* ClairBrowserWindow::FromWebContents(
    content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  return tab ? FromBrowser(tab->GetBrowserWindowInterface()) : nullptr;
}

// static
std::vector<ClairBrowserWindow*> ClairBrowserWindow::All() {
  std::vector<ClairBrowserWindow*> windows;
  for (const auto& [browser, window] : NativeWindows()) {
    windows.push_back(window);
  }
  return windows;
}

void ClairBrowserWindow::DetachFromClairUI() {
  if (detached_) {
    return;
  }
  detached_ = true;
  // The popup belongs to the window's ClairUI side and goes with it, rather
  // than living on, without a window to show in, until this object is deleted.
  if (extensions_) {
    extensions_->HideActivePopup();
  }
  [clair_window_ browserDidClose];
  [bridge_ detach];
  clair_window_ = nil;
}

std::set<content::WebContents*> ClairBrowserWindow::PagesShownWith(
    content::WebContents* active) const {
  std::set<content::WebContents*> pages =
      peeks_ ? peeks_->PagesShownWith(active)
      : active ? std::set<content::WebContents*>{active}
               : std::set<content::WebContents*>();
  // add-split-view D5: the split's other pane, beside the active one or the
  // parent of its Peek.
  tabs::TabInterface* tab =
      active ? tabs::TabInterface::MaybeGetFromContents(active) : nullptr;
  if (tabs::TabInterface* parent = tab && peeks_ ? peeks_->ParentOf(tab) : nullptr) {
    tab = parent;
  }
  if (tabs::TabInterface* partner = ClairSplits::PartnerOf(tab)) {
    pages.insert(partner->GetContents());
  }
  return pages;
}

// --- Spaces (add-spaces D3, D4, D5) ---

void ClairBrowserWindow::SetShownSpace(const std::string& space) {
  if (space == shown_space_) {
    return;
  }
  const std::string previous = shown_space_;
  shown_space_ = space;
  if (IsActive() && space_tabs_ && space_tabs_->is_regular()) {
    clair::ClairSpaceStore::Get()->SetLastSpace(space);
  }
  if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
    group->ShownSpaceChanged(this);
  }
  [bridge_ shownSpaceChangedFrom:previous];
}

namespace {

// share-tabs-across-windows D2: the key window takes back the tab of its
// still, unless the still has ended meanwhile.
void PostTakeBack(base::WeakPtr<ClairBrowserWindow> window) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairBrowserWindow> window) {
                       if (!window || !window->IsActive()) {
                         return;
                       }
                       if (tabs::TabInterface* still =
                               window->still_tab().Get()) {
                         window->ActivateRow(still);
                       }
                     },
                     window));
}

}  // namespace

// static
ClairBrowserWindow* ClairBrowserWindow::HolderOf(const tabs::TabInterface* tab) {
  return tab ? FromBrowser(tab->GetBrowserWindowInterface()) : nullptr;
}

namespace {

// The row `tab` shows in: its parent if it's a Peek, in whichever window;
// for a split's pane, the split's row (add-split-view D2): its pane listed in
// Today, or its leading pane when both are pinned tabs' or favorites'.
tabs::TabInterface* RowOf(tabs::TabInterface* tab) {
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  tabs::TabInterface* parent = peeks && tab ? peeks->ParentOf(tab) : nullptr;
  tabs::TabInterface* row = parent ? parent : tab;
  const std::vector<tabs::TabInterface*> panes = ClairSplits::PanesOf(row);
  if (panes.empty()) {
    return row;
  }
  ClairSpaceTabs* lists = holder ? holder->space_tabs() : nullptr;
  for (tabs::TabInterface* pane : panes) {
    if (lists && lists->PinOf(pane).empty() && !lists->SpaceOf(pane).empty()) {
      return pane;
    }
  }
  return panes.front();
}

// share-tabs-across-windows D2: `row` stopped showing in its window. If no
// window shows it now, the most recently active window with a still of it
// takes it back, without becoming key, as Arc does.
void GiveBackToStill(tabs::TabHandle handle) {
  tabs::TabInterface* row = handle.Get();
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
  if (!row || !holder || holder->IsActiveRow(row)) {
    return;
  }
  ClairBrowserWindow* target = nullptr;
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&target, handle](BrowserWindowInterface* candidate) {
        ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(candidate);
        if (window && window->still_tab() == handle) {
          target = window;
          return false;
        }
        return true;
      });
  // Only into the Space the window shows, which the still belongs to, or a
  // favorite's tab of its profile (add-pinned-tabs-and-favorites D2).
  if (!target || target == holder || !target->space_tabs() ||
      (target->space_tabs()->SpaceOf(row) != target->shown_space() &&
       !target->space_tabs()->IsFavoriteTab(row))) {
    return;
  }
  target->ActivateRow(row);
}

// When the user last looked at `row`, or at its Peek.
base::Time LastActive(tabs::TabInterface* row) {
  base::Time time = row->GetLastActiveTime();
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  if (tabs::TabInterface* peek = peeks ? peeks->PeekOf(row) : nullptr) {
    time = std::max(time, peek->GetLastActiveTime());
  }
  return time;
}

}  // namespace

std::vector<tabs::TabInterface*> ClairBrowserWindow::SpaceTabs() const {
  if (!space_tabs_) {
    return std::vector<tabs::TabInterface*>();
  }
  // share-tabs-across-windows D1: every window lists the Space's tabs; an
  // incognito or guest window lists its own.
  return space_tabs_->is_regular() ? space_tabs_->TabsIn(shown_space_)
                                   : space_tabs_->TabsIn(shown_space_, browser_);
}

std::vector<const clair::Pin*> ClairBrowserWindow::RowPins(
    const std::string& space) const {
  std::vector<const clair::Pin*> pins;
  if (!space_tabs_ || !space_tabs_->is_regular()) {
    return pins;
  }
  // add-tab-folders D9: the Space's items in order: each pinned tab, and a
  // folder's pinned tabs while it's open, or those whose page is open while
  // it's closed, as the sidebar lists them.
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  for (const std::string& id :
       store->ChildrenOf(clair::PinContainer::OfSpace(space))) {
    if (const clair::Pin* pin = store->Find(id)) {
      pins.push_back(pin);
      continue;
    }
    // add-split-view D10: a pinned split's two, in pane order.
    if (store->FindSplit(id)) {
      for (const clair::Pin* pane : store->PinsOfSplit(id)) {
        pins.push_back(pane);
      }
      continue;
    }
    const bool open = store->IsOpen(id);
    for (const clair::Pin* pin :
         store->PinsIn(clair::PinContainer::OfFolder(space, id))) {
      if (open || space_tabs_->BoundTab(pin->id)) {
        pins.push_back(pin);
      }
    }
  }
  return pins;
}

std::vector<tabs::TabInterface*> ClairBrowserWindow::Rows() const {
  // add-pinned-tabs-and-favorites D4: the open pinned tabs, then the Today
  // tabs. Favorites are never rows. add-tab-folders D9: a closed folder's
  // tabs aren't, except the highlighted one.
  std::vector<tabs::TabInterface*> rows;
  for (const clair::Pin* pin : RowPins(shown_space_)) {
    // add-split-view: a pinned split's row is its leading pane's.
    if (tabs::TabInterface* tab = space_tabs_->BoundTab(pin->id);
        tab && RowOf(tab) == tab) {
      rows.push_back(tab);
    }
  }
  for (tabs::TabInterface* tab : TodayRows()) {
    rows.push_back(tab);
  }
  return rows;
}

std::vector<tabs::TabInterface*> ClairBrowserWindow::TodayRows() const {
  std::vector<tabs::TabInterface*> rows = SpaceTabs();
  std::erase_if(rows,
                [](tabs::TabInterface* tab) { return RowOf(tab) != tab; });
  return rows;
}

bool ClairBrowserWindow::IsActiveRow(const tabs::TabInterface* tab) const {
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  if (!tab || !active) {
    return false;
  }
  tabs::TabInterface* shown =
      peeks_ && peeks_->ParentOf(active) ? peeks_->ParentOf(active) : active;
  // add-split-view D2: either pane of the shown split.
  return active == tab || shown == tab || ClairSplits::PartnerOf(shown) == tab;
}

tabs::TabInterface* ClairBrowserWindow::HighlightedRow() const {
  if (tabs::TabInterface* still = still_tab_.Get()) {
    return still;
  }
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  if (!active || ClairSpaceTabs::IsPlaceholder(active->GetContents())) {
    return nullptr;
  }
  // A Peek's parent's row, or a split's (add-split-view D2).
  return RowOf(active);
}

bool ClairBrowserWindow::IsShownElsewhere(const tabs::TabInterface* row) const {
  ClairBrowserWindow* holder = HolderOf(row);
  // add-profiles D5: a hidden member shows no tab.
  return holder && holder != this && !holder->IsHiddenMember() &&
         holder->IsActiveRow(row);
}

void ClairBrowserWindow::ActivateTab(tabs::TabInterface* tab,
                                     ClairTakeOptions options) {
  ClairBrowserWindow* holder = HolderOf(tab);
  if (tab && holder && holder != this) {
    Take(tab, std::move(options));
    return;
  }
  TabStripModel* strip = browser_->tab_strip_model();
  const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    base::AutoReset<bool> choosing(&choosing_next_,
                                   choosing_next_ || options.choosing);
    strip->ActivateTabAt(index,
                         TabStripUserGestureDetails(
                             TabStripUserGestureDetails::GestureType::kOther));
  }
  if (options.choosing) {
    came_from_ = tabs::TabHandle::Null();
  }
  if (options.then) {
    std::move(options.then).Run();
  }
}

void ClairBrowserWindow::ActivateRow(tabs::TabInterface* row,
                                     ClairTakeOptions options) {
  if (!row) {
    if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  ClairBrowserWindow* holder = HolderOf(row);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  // add-split-view: a split shows with the pane focused last.
  tabs::TabInterface* pane = ClairSplits::LastFocusedPane(row);
  tabs::TabInterface* peek = peeks ? peeks->PeekOf(pane) : nullptr;
  ActivateTab(peek ? peek : pane, std::move(options));
}

void ClairBrowserWindow::ChooseRow(tabs::TabInterface* row,
                                   base::OnceClosure* then) {
  ClairTakeOptions options;
  options.choosing = true;
  if (then) {
    // A close waits for the tab it shows instead: the window keeps its tab
    // until the next one is here.
    options.then = std::move(*then);
  } else {
    // Chromium acts at once, as on a page's answer to its leave-page
    // confirmation: the tab moves now, and the still's image follows.
    options.wait_for_copy = false;
  }
  ActivateRow(row, std::move(options));
}

bool ClairBrowserWindow::ShowNextRow(tabs::TabInterface* row,
                                     base::OnceClosure* then) {
  const std::vector<tabs::TabInterface*> rows = Rows();
  auto it = std::ranges::find(rows, row);
  // add-pinned-tabs-and-favorites D4: a favorite's tab is no row, but its
  // close shows the tab it was selected from, or else the first row.
  const bool favorite = space_tabs_ && space_tabs_->IsFavoriteTab(row);
  if (it == rows.end() && !favorite) {
    return false;
  }
  // share-tabs-across-windows D3: from every row, a row another window shows
  // included; it's taken from there. A close another window started takes
  // none: the user is looking at that window, maybe at the very row.
  const bool avoid_shown = closing_for_another_window_;
  auto usable = [&](tabs::TabInterface* candidate) {
    return candidate != row && (!avoid_shown || !IsShownElsewhere(candidate));
  };
  tabs::TabInterface* next = nullptr;
  tabs::TabInterface* came_from = came_from_.Get();
  // A favorite counts as the tab the user came from, though it's no row.
  const bool came_from_listed =
      came_from && (std::ranges::find(rows, came_from) != rows.end() ||
                    (space_tabs_ && space_tabs_->IsFavoriteTab(came_from)));
  if (came_from_listed && usable(came_from)) {
    next = came_from;
  } else if (favorite) {
    for (tabs::TabInterface* candidate : rows) {
      if (usable(candidate)) {
        next = candidate;
        break;
      }
    }
  } else {
    for (auto above = it; !next && above != rows.begin();) {
      --above;
      if (usable(*above)) {
        next = *above;
      }
    }
    for (auto below = it + 1; !next && below != rows.end(); ++below) {
      if (usable(*below)) {
        next = *below;
      }
    }
  }
  if (!next) {
    return false;
  }
  ChooseRow(next, then);
  return true;
}

bool ClairBrowserWindow::IsEmptiedSpacePage(tabs::TabInterface* row) const {
  // add-split-view: a split of new tab pages isn't the emptied Space's page;
  // closing it leaves one.
  if (!row || !space_tabs_ || !space_tabs_->is_regular() || RowOf(row) != row ||
      ClairSplits::PartnerOf(row)) {
    return false;
  }
  const std::vector<tabs::TabInterface*> rows = Rows();
  const GURL& url = row->GetContents()->GetVisibleURL();
  return rows.size() == 1 && rows.front() == row &&
         clair::IsNewTabPageURL(url);
}

bool ClairBrowserWindow::KeepEmptiedSpace(tabs::TabInterface* row) {
  if (!row || !space_tabs_ || !space_tabs_->is_regular() || RowOf(row) != row) {
    return false;
  }
  if (IsEmptiedSpacePage(row)) {
    // Closing the emptied Space's new tab page closes the window, as the
    // user's close does, and the page closes with it.
    if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
      group->CloseByUser(row);
      return true;
    }
    return false;
  }
  // The window stays on its Space, as Arc keeps an empty Space.
  OpenNewTabPage(/*show_command_bar=*/true);
  return false;
}

void ClairBrowserWindow::CloseTab(tabs::TabInterface* tab) {
  if (!tab) {
    return;
  }
  // share-tabs-across-windows D3: in whichever window holds it, which picks
  // its own next tab.
  if (ClairBrowserWindow* holder = HolderOf(tab); holder && holder != this) {
    base::AutoReset<bool> elsewhere(&holder->closing_for_another_window_, true);
    holder->CloseTab(tab);
    return;
  }
  // add-split-view D12: a pane of the shown split closes alone, and the other
  // pane shows by itself in the split's place. A pane of a pinned or
  // favorited split takes its pin out of the split, as in Arc (D10), which
  // Restore Last Closed Tab brings back.
  if (tabs::TabInterface* partner = ClairSplits::PartnerOf(tab);
      partner && IsActiveRow(tab)) {
    clair::ClairPinStore* store = clair::ClairPinStore::Get();
    const clair::Pin* pin =
        space_tabs_ ? store->Find(space_tabs_->PinOf(tab)) : nullptr;
    const clair::Pin* other =
        space_tabs_ ? store->Find(space_tabs_->PinOf(partner)) : nullptr;
    if (pin && other && !pin->split.empty() && pin->split == other->split) {
      // A page that asks before leaving may stay, and its pin with it.
      if (tab->GetContents()->NeedToFireBeforeUnloadOrUnloadEvents()) {
        pending_split_close_ = tab->GetHandle();
        pending_split_pin_ = pin->id;
      } else {
        store->TakeOutOfSplit(pin->id);
      }
    }
    if (browser_->tab_strip_model()->GetActiveTab() == tab ||
        (peeks_ && peeks_->ParentOf(browser_->tab_strip_model()->GetActiveTab()) ==
                       tab)) {
      ClairTakeOptions options;
      options.choosing = true;
      ActivateTab(partner, std::move(options));
    }
    CloseTabNow(tab->GetHandle());
    return;
  }
  // D4: Clair picks the next tab first; without one in the Space, a new tab
  // page takes its place (add-profiles D13).
  if (IsActiveRow(tab)) {
    // D13: the emptied Space's own new tab page closes the window, whatever
    // the page answers about unloading.
    if (IsEmptiedSpacePage(tab)) {
      KeepEmptiedSpace(tab);
      return;
    }
    if (tab->GetContents()->NeedToFireBeforeUnloadOrUnloadEvents()) {
      // Chromium asks the page before it closes the tab, and its leave-page
      // confirmation makes the tab active again. The choice waits for the
      // page's answer, in BeforeUnloadFired().
      pending_close_ = tab->GetHandle();
      pending_close_for_another_window_ = closing_for_another_window_;
    } else {
      // The tab closes once the next one shows, which may wait for a page's
      // copy in another window (share-tabs-across-windows D2): closing first
      // would close a window holding no other tab.
      base::OnceClosure close =
          base::BindOnce(&ClairBrowserWindow::CloseTabNow,
                         weak_factory_.GetWeakPtr(), tab->GetHandle());
      if (!ShowNextRow(tab, &close) && RowOf(tab) == tab &&
          KeepEmptiedSpace(tab)) {
        return;
      }
      if (close) {
        std::move(close).Run();
      }
      return;
    }
  }
  CloseTabNow(tab->GetHandle());
}

void ClairBrowserWindow::CloseTabNow(tabs::TabHandle handle) {
  tabs::TabInterface* tab = handle.Get();
  TabStripModel* strip = browser_->tab_strip_model();
  const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    strip->CloseWebContentsAt(index,
                              TabCloseTypes::CLOSE_USER_GESTURE |
                                  TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
  }
}

void ClairBrowserWindow::BeforeUnloadFired(content::WebContents* contents,
                                           bool proceed) {
  // add-profiles D5: staying on a page cancels the window's close, which
  // Chromium does on hearing the answer, after this; the group's close stops
  // with it.
  if (!proceed &&
      UnloadController::From(browser_)->is_attempting_to_close_browser()) {
    if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
      group->CloseCancelled(this);
    }
  }
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (tab && tab->GetHandle() == pending_split_close_) {
    pending_split_close_ = tabs::TabHandle::Null();
    if (proceed) {
      clair::ClairPinStore::Get()->TakeOutOfSplit(pending_split_pin_);
    }
    pending_split_pin_.clear();
    return;
  }
  if (!tab || tab->GetHandle() != pending_close_) {
    return;
  }
  pending_close_ = tabs::TabHandle::Null();
  base::AutoReset<bool> elsewhere(&closing_for_another_window_,
                                  pending_close_for_another_window_);
  // Staying on the page leaves everything as it was, the came-from row too.
  // The page agreed to leave, so an emptied Space keeps a new tab page
  // rather than closing the window (add-profiles D13).
  if (proceed && IsActiveRow(tab) && !ShowNextRow(tab) && RowOf(tab) == tab &&
      space_tabs_ && space_tabs_->is_regular()) {
    OpenNewTabPage(/*show_command_bar=*/true);
  }
}

void ClairBrowserWindow::CloseTabsBelow(tabs::TabInterface* tab) {
  if (!tab || !space_tabs_) {
    return;
  }
  // Below the tab's Peek, which goes only with the tab (add-peek D8), over
  // the Space's rows in every window (share-tabs-across-windows D3).
  ClairBrowserWindow* holder = HolderOf(tab);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  // add-split-view: a split is one row, which shows where its Today pane is
  // listed when its other pane is a pinned tab or favorite. Neither pane is
  // below it.
  tabs::TabInterface* row = RowOf(tab);
  std::vector<tabs::TabInterface*> panes = ClairSplits::PanesOf(row);
  if (panes.empty()) {
    panes = {row};
  }
  const bool row_pinned = !space_tabs_->PinOf(row).empty();
  const std::string space = space_tabs_->SpaceOf(row);
  // add-pinned-tabs-and-favorites D4: from a pinned tab, the open pinned tabs
  // below it and every Today tab; from a Today tab, the Today tabs below it.
  std::vector<tabs::TabInterface*> tabs;
  if (space_tabs_->is_regular()) {
    // add-tab-folders D9: the pinned rows the window lists.
    for (const clair::Pin* pin : RowPins(space)) {
      if (tabs::TabInterface* bound = space_tabs_->BoundTab(pin->id)) {
        tabs.push_back(bound);
      }
    }
    for (tabs::TabInterface* today : space_tabs_->TabsIn(space)) {
      tabs.push_back(today);
    }
  } else {
    tabs = space_tabs_->TabsIn(space, browser_);
  }
  std::vector<tabs::TabInterface*> own;
  auto cutoff = tabs.end();
  for (tabs::TabInterface* pane : panes) {
    own.push_back(pane);
    tabs::TabInterface* last = peeks ? peeks->LastOfFamily(pane) : pane;
    if (last != pane) {
      own.push_back(last);
    }
    if (space_tabs_->PinOf(pane).empty() == !row_pinned) {
      auto at = std::ranges::find(tabs, last);
      if (at == tabs.end()) {
        at = std::ranges::find(tabs, pane);
      }
      if (at != tabs.end() && (cutoff == tabs.end() || at > cutoff)) {
        cutoff = at;
      }
    }
  }
  if (cutoff == tabs.end()) {
    return;
  }
  std::vector<tabs::TabHandle> below;
  for (auto it = cutoff + 1; it != tabs.end(); ++it) {
    if (std::ranges::find(own, *it) == own.end()) {
      below.push_back((*it)->GetHandle());
    }
  }
  for (const tabs::TabHandle& handle : below) {
    CloseTab(handle.Get());
  }
}

void ClairBrowserWindow::OpenNewTabPage(bool show_command_bar) {
  {
    base::AutoReset<bool> choosing(&choosing_next_, true);
    // An empty URL is the new tab page; clair::NewTabIndex puts it at the
    // top, and it joins the shown Space.
    chrome::AddTabAt(browser_, GURL(), -1, /*foreground=*/true);
  }
  came_from_ = tabs::TabHandle::Null();
  if (show_command_bar) {
    [clair_window_ showCommandBarWithMode:ClairCommandBarModeCurrentTab];
  }
}

void ClairBrowserWindow::OpenInShownSpace(const GURL& url) {
  if (url.is_empty()) {
    OpenNewTabPage(/*show_command_bar=*/true);
    return;
  }
  // At the top of the shown Space, as any new tab.
  NavigateParams params(browser_, url, ui::PAGE_TRANSITION_AUTO_BOOKMARK);
  params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
  Navigate(&params);
}

// --- Split view (add-split-view D2, D8, D10 to D12) ---

void ClairBrowserWindow::BringHere(tabs::TabInterface* tab,
                                   base::OnceClosure then) {
  if (!tab) {
    return;
  }
  if (HolderOf(tab) == this) {
    std::move(then).Run();
    return;
  }
  // share-tabs-across-windows D1: taken at once, its row with it; the other
  // window keeps a still if it showed it.
  ClairTakeOptions options;
  options.wait_for_copy = false;
  options.then = std::move(then);
  Take(tab, std::move(options));
}

void ClairBrowserWindow::SplitTabs(tabs::TabInterface* tab,
                                   tabs::TabInterface* other,
                                   bool other_leading) {
  if (!tab || !other || tab == other || !splits_) {
    return;
  }
  base::OnceClosure make = base::BindOnce(
      [](base::WeakPtr<ClairBrowserWindow> window, tabs::TabHandle first,
         tabs::TabHandle second, bool second_leading) {
        tabs::TabInterface* a = first.Get();
        tabs::TabInterface* b = second.Get();
        if (window && a && b && HolderOf(a) == window.get() &&
            HolderOf(b) == window.get()) {
          window->splits()->Make(a, b, second_leading, 0.5, b);
        }
      },
      weak_factory_.GetWeakPtr(), tab->GetHandle(), other->GetHandle(),
      other_leading);
  base::OnceClosure bring_other = base::BindOnce(
      [](base::WeakPtr<ClairBrowserWindow> window, tabs::TabHandle handle,
         base::OnceClosure then) {
        if (window && handle.Get()) {
          window->BringHere(handle.Get(), std::move(then));
        }
      },
      weak_factory_.GetWeakPtr(), other->GetHandle(), std::move(make));
  BringHere(tab, std::move(bring_other));
}

void ClairBrowserWindow::SplitWithNewTab(tabs::TabInterface* tab) {
  if (!tab || !splits_) {
    return;
  }
  BringHere(tab, base::BindOnce(
                     [](base::WeakPtr<ClairBrowserWindow> window,
                        tabs::TabHandle handle) {
                       if (window && handle.Get()) {
                         window->splits()->MakeWithNewTab(handle.Get());
                       }
                     },
                     weak_factory_.GetWeakPtr(), tab->GetHandle()));
}

void ClairBrowserWindow::ShowSplit(tabs::TabInterface* tab) {
  if (tab) {
    ActivateRow(RowOf(tab));
  }
}

void ClairBrowserWindow::ReplacePane(tabs::TabInterface* pane,
                                     tabs::TabInterface* replacement) {
  if (!pane || !replacement || !splits_ || HolderOf(pane) != this) {
    return;
  }
  BringHere(replacement,
            base::BindOnce(
                [](base::WeakPtr<ClairBrowserWindow> window,
                   tabs::TabHandle pane, tabs::TabHandle replacement) {
                  if (window && pane.Get() && replacement.Get()) {
                    window->splits()->Replace(pane.Get(), replacement.Get());
                  }
                },
                weak_factory_.GetWeakPtr(), pane->GetHandle(),
                replacement->GetHandle()));
}

void ClairBrowserWindow::SeparateSplit(tabs::TabInterface* tab) {
  tabs::TabInterface* partner = ClairSplits::PartnerOf(tab);
  ClairBrowserWindow* holder = HolderOf(tab);
  if (!partner || !holder || !holder->splits()) {
    return;
  }
  // D10: a pinned or favorited split's pins take its place.
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  const clair::Pin* pin =
      space_tabs_ ? store->Find(space_tabs_->PinOf(tab)) : nullptr;
  const clair::Pin* other =
      space_tabs_ ? store->Find(space_tabs_->PinOf(partner)) : nullptr;
  if (pin && other && !pin->split.empty() && pin->split == other->split) {
    clair::SeparatePinnedSplit(pin->split);
    return;
  }
  holder->splits()->Separate(tab);
}

void ClairBrowserWindow::CloseTabsNow(std::vector<tabs::TabHandle> handles) {
  TabStripModel* strip = browser_->tab_strip_model();
  strip->ExecuteCloseTabsCommand(
      base::BindRepeating(
          [](TabStripModel* strip, std::vector<tabs::TabHandle> handles) {
            std::vector<tabs::TabInterface*> tabs_to_close;
            for (const tabs::TabHandle& handle : handles) {
              tabs::TabInterface* tab = handle.Get();
              if (tab && strip->GetIndexOfTab(tab) != TabStripModel::kNoTab) {
                tabs_to_close.push_back(tab);
              }
            }
            return tabs_to_close;
          },
          base::Unretained(strip), std::move(handles)),
      /*delete_groups=*/false);
}

void ClairBrowserWindow::CloseSplit(tabs::TabInterface* tab) {
  const std::vector<tabs::TabInterface*> panes = ClairSplits::PanesOf(tab);
  if (panes.empty()) {
    CloseTab(tab);
    return;
  }
  // In whichever window holds it, which picks its own next tab.
  if (ClairBrowserWindow* holder = HolderOf(tab); holder && holder != this) {
    base::AutoReset<bool> elsewhere(&holder->closing_for_another_window_, true);
    holder->CloseSplit(tab);
    return;
  }
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* pane : panes) {
    handles.push_back(pane->GetHandle());
  }
  tabs::TabInterface* row = RowOf(tab);
  if (IsActiveRow(row)) {
    // D4: the next row first; without one, a new tab page.
    base::OnceClosure close =
        base::BindOnce(&ClairBrowserWindow::CloseTabsNow,
                       weak_factory_.GetWeakPtr(), handles);
    if (!ShowNextRow(row, &close) && KeepEmptiedSpace(row)) {
      return;
    }
    if (close) {
      std::move(close).Run();
    }
    return;
  }
  CloseTabsNow(std::move(handles));
}

void ClairBrowserWindow::ShowPinnedSplit(tabs::TabInterface* lead,
                                         tabs::TabInterface* trail,
                                         double ratio) {
  if (!lead || !trail || !splits_) {
    return;
  }
  base::OnceClosure show = base::BindOnce(
      [](base::WeakPtr<ClairBrowserWindow> window, tabs::TabHandle lead,
         tabs::TabHandle trail, double ratio) {
        tabs::TabInterface* a = lead.Get();
        tabs::TabInterface* b = trail.Get();
        if (!window || !a || !b || HolderOf(a) != window.get() ||
            HolderOf(b) != window.get()) {
          return;
        }
        if (ClairSplits::PartnerOf(a) != b) {
          // A pane in another split, as when a Today tab replaced its
          // partner, leaves it first, keeping both pages.
          for (tabs::TabInterface* pane : {a, b}) {
            if (pane->IsSplit()) {
              window->splits()->Separate(pane);
            }
          }
          if (!window->splits()->Make(a, b, /*other_leading=*/false, ratio,
                                      /*focus=*/nullptr)) {
            return;
          }
        }
        window->ActivateRow(a);
      },
      weak_factory_.GetWeakPtr(), lead->GetHandle(), trail->GetHandle(),
      ratio);
  // Its tabs come here first, apart; a split already open moves whole.
  if (ClairSplits::PartnerOf(lead) == trail) {
    BringHere(lead, std::move(show));
    return;
  }
  base::OnceClosure bring_trail = base::BindOnce(
      [](base::WeakPtr<ClairBrowserWindow> window, tabs::TabHandle handle,
         base::OnceClosure then) {
        if (window && handle.Get()) {
          window->BringHere(handle.Get(), std::move(then));
        }
      },
      weak_factory_.GetWeakPtr(), trail->GetHandle(), std::move(show));
  BringHere(lead, std::move(bring_trail));
}

void ClairBrowserWindow::OpenPeekInSplit(tabs::TabInterface* tab) {
  ClairBrowserWindow* holder = HolderOf(tab);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  if (!peeks || !holder->splits()) {
    return;
  }
  tabs::TabInterface* parent = peeks->ParentOf(tab) ? peeks->ParentOf(tab) : tab;
  tabs::TabInterface* peek = peeks->PeekOf(parent);
  // D11: not while the parent is in a split, which holds two tabs.
  if (!peek || ClairSplits::PartnerOf(parent)) {
    return;
  }
  peeks->Expand(parent);
  holder->splits()->Make(parent, peek, /*other_leading=*/false, 0.5, peek);
}

// --- Window groups (add-profiles D3 to D6, D8, D13) ---

bool ClairBrowserWindow::IsHiddenMember() const {
  ClairWindowGroup* group = ClairWindowGroup::Of(this);
  return group && group->IsHidden(this);
}

void ClairBrowserWindow::BeginSwapIn(const std::string& previous_space,
                                     ClairBrowserWindow* outgoing) {
  [bridge_ swappedInFrom:previous_space
                     for:outgoing ? outgoing->browser()->GetSessionID().id()
                                  : ClairBrowserIDNone];
}

void ClairBrowserWindow::JoinActiveSpace() {
  const NSWindowCollectionBehavior behavior = ns_window_.collectionBehavior;
  if (behavior & NSWindowCollectionBehaviorMoveToActiveSpace) {
    return;
  }
  ns_window_.collectionBehavior = behavior | NSWindowCollectionBehaviorMoveToActiveSpace;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairBrowserWindow> window) {
                       if (window) {
                         window->ns_window().collectionBehavior &=
                             ~NSWindowCollectionBehaviorMoveToActiveSpace;
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

void ClairBrowserWindow::Reveal(NSWindow* above, bool make_key) {
  // The extension actions it missed while hidden, before it shows.
  if (extensions_) {
    extensions_->FlushIfStale();
  }
  JoinActiveSpace();
  if (above && above.visible) {
    [ns_window_ orderWindow:NSWindowAbove relativeTo:above.windowNumber];
  } else {
    [ns_window_ orderFront:nil];
  }
  if (make_key) {
    BrowserActiveStateManager::From(browser_)->DidBecomeActive();
    [ns_window_ makeKeyWindow];
  }
  if (content::WebContents* active =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    for (content::WebContents* page : PagesShownWith(active)) {
      page->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    }
    if (make_key) {
      active->Focus();
    }
  }
}

void ClairBrowserWindow::Conceal(bool order_out) {
  // D5: a still ends when the group swaps away; the tab stays with the
  // window that took it, and the placeholder stays active without a still.
  if (still_tab_ != tabs::TabHandle::Null()) {
    still_tab_ = tabs::TabHandle::Null();
    still_image_ = nil;
    [bridge_ stillChanged];
  }
  CancelPendingTake();
  if (content::WebContents* active =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    // add-tab-switcher-and-tabs-menu D4: the pages leave without an active
    // tab change; the switcher's previews are taken here too.
    KeepPreviews(active, {});
    for (content::WebContents* page : PagesShownWith(active)) {
      page->UpdateWebContentsVisibility(content::Visibility::HIDDEN);
    }
  }
  if (order_out) {
    [ns_window_ orderOut:nil];
  }
}

void ClairBrowserWindow::SetCovering(bool covering) {
  ns_window_.covering = covering;
  // Square corners: no shadow of the rounded frame shows over the owner.
  ns_window_.hasShadow = !covering;
}

NSWindow* ClairBrowserWindow::FullscreenNSWindow() const {
  ClairWindowGroup* group = ClairWindowGroup::Of(this);
  ClairBrowserWindow* owner = group ? group->fullscreen_owner() : nullptr;
  return owner && owner != this && !IsHiddenMember() ? owner->ns_window()
                                                     : ns_window_;
}

void ClairBrowserWindow::CloseTabWithoutChoosing(tabs::TabInterface* tab) {
  TabStripModel* strip = browser_->tab_strip_model();
  const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    strip->CloseWebContentsAt(index, TabCloseTypes::CLOSE_USER_GESTURE);
  }
}

bool ClairBrowserWindow::NeedsBeforeUnload() const {
  TabStripModel* strip = browser_->tab_strip_model();
  for (int i = 0; i < strip->count(); ++i) {
    if (strip->GetWebContentsAt(i)->NeedToFireBeforeUnloadOrUnloadEvents()) {
      return true;
    }
  }
  return false;
}

bool ClairBrowserWindow::HasRealTabs() const {
  TabStripModel* strip = browser_->tab_strip_model();
  for (int i = 0; i < strip->count(); ++i) {
    if (!ClairSpaceTabs::IsPlaceholder(strip->GetWebContentsAt(i))) {
      return true;
    }
  }
  return false;
}

std::vector<GURL> ClairBrowserWindow::PageURLs() const {
  std::vector<GURL> urls;
  TabStripModel* strip = browser_->tab_strip_model();
  for (int i = 0; i < strip->count(); ++i) {
    content::WebContents* contents = strip->GetWebContentsAt(i);
    const GURL& url = contents->GetVisibleURL();
    if (ClairSpaceTabs::IsPlaceholder(contents) || !url.is_valid() ||
        clair::IsNewTabPageURL(url)) {
      continue;
    }
    urls.push_back(url);
  }
  return urls;
}

std::string ClairBrowserWindow::RestoredGroupTag() const {
  TabStripModel* strip = browser_->tab_strip_model();
  for (int i = 0; i < strip->count(); ++i) {
    std::string tag = ClairSpaceTabs::WindowTag(strip->GetWebContentsAt(i));
    if (!tag.empty()) {
      return tag;
    }
  }
  return std::string();
}

void ClairBrowserWindow::ShowRestoredSpace(const std::string& space) {
  if (!space_tabs_ || !space_tabs_->is_regular()) {
    return;
  }
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  // D6: a selected new tab page isn't restored; the tab selected in its
  // place says so.
  const bool new_tab_was_selected =
      active &&
      ClairSpaceTabs::TakeRestoredNewTabWasSelected(active->GetContents());
  // A favorite's tab belongs to no Space, and shows in any of its profile's
  // (add-pinned-tabs-and-favorites D2).
  if (active && !new_tab_was_selected &&
      (space_tabs_->IntendedSpaceOf(active) == space ||
       space_tabs_->IsFavoriteTab(active))) {
    SetShownSpace(space);
    return;
  }
  // D6: the selected tab didn't come back, as a new tab page: one opens.
  if (!clair::ClairSpaceStore::Get()->Contains(space)) {
    return;
  }
  SetShownSpace(space);
  OpenNewTabPage(/*show_command_bar=*/true);
}

void ClairBrowserWindow::ShowSpaceOnNewTab(const std::string& space,
                                           const GURL& url,
                                           bool command_bar) {
  if (!space_tabs_ || !space_tabs_->is_regular() ||
      clair::ClairSpaceStore::Get()->ProfileOf(space) !=
          clair::ClairProfiles::IDOf(browser_->GetProfile())) {
    return;
  }
  SetShownSpace(space);
  if (url.is_empty() && !command_bar) {
    OpenNewTabPage(/*show_command_bar=*/false);
    return;
  }
  OpenInShownSpace(url);
}

bool ClairBrowserWindow::ShowSpaceOnLaunchNewTab(const std::string& space) {
  // With every tab of the session dropped or none to restore, Chromium opens
  // a window on a new tab page (SessionRestoreImpl::FinishedTabCreation),
  // which joined the Space the window shows. Restored tabs are never on one
  // (clair::DropNewTabPages), so that page is the launch's.
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  if (active && space_tabs_ && space_tabs_->is_regular() &&
      space_tabs_->SpaceOf(active) == space &&
      clair::IsNewTabPageURL(active->GetContents()->GetVisibleURL())) {
    SetShownSpace(space);
    return false;
  }
  ShowSpaceOnNewTab(space, GURL(), /*command_bar=*/false);
  return true;
}

void ClairBrowserWindow::OpenCommandBarWhenShown() {
  // Once the window is key and the page has taken focus, which would close
  // it.
  if (!IsActive()) {
    command_bar_when_key_ = true;
    return;
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairBrowserWindow> window) {
                       if (window && window->clair_window() && window->IsVisible()) {
                         [window->clair_window()
                             showCommandBarWithMode:ClairCommandBarModeCurrentTab];
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

void ClairBrowserWindow::FollowActiveTab() {
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  if (!active || !space_tabs_ ||
      ClairSpaceTabs::IsPlaceholder(active->GetContents())) {
    return;
  }
  const std::string space = space_tabs_->SpaceOf(active);
  if (space.empty() || space == shown_space_) {
    return;
  }
  SetShownSpace(space);
  last_active_[space] = active->GetHandle();
}

void ClairBrowserWindow::DropPendingTakeOf(const tabs::TabInterface* tab) {
  if (tab && taking_ == tab->GetHandle()) {
    CancelPendingTake();
  }
}

// --- The tab switcher (add-tab-switcher-and-tabs-menu D1, D4) ---

void ClairBrowserWindow::ShowTab(tabs::TabInterface* tab) {
  ClairBrowserWindow* holder = HolderOf(tab);
  if (!holder || ClairSpaceTabs::IsPlaceholder(tab->GetContents())) {
    return;
  }
  // A Peek's row is its parent's; a split shows with its pane focused last.
  tabs::TabInterface* row = RowOf(tab);
  ClairSpaceTabs* lists = holder->space_tabs();
  if (holder == this ||
      (space_tabs_ && space_tabs_->is_regular() && lists == space_tabs_ &&
       space_tabs_->IsListed(row))) {
    // A tab of another Space shows that Space as it becomes active, ClairUI
    // hearing of the Space first (OnActiveTabChanged).
    ActivateRow(row);
    return;
  }
  // add-profiles D3: another profile's tab; the group swaps to its member.
  if (!space_tabs_ || !space_tabs_->is_regular() || !lists ||
      !lists->is_regular() || !lists->IsListed(row)) {
    return;
  }
  std::string space = lists->SpaceOf(row);
  if (space.empty()) {
    // A favorite belongs to its profile: the Space its window shows.
    space = holder->shown_space();
  }
  ShowSpace(space, /*again=*/false, row);
}

void ClairBrowserWindow::RequestPreview(
    tabs::TabInterface* tab,
    const gfx::SizeF& size,
    base::OnceCallback<void(NSImage*)> done) {
  content::WebContents* contents = tab ? tab->GetContents() : nullptr;
  if (!contents || contents->IsCrashed() || size.IsEmpty() ||
      ClairSpaceTabs::IsPlaceholder(contents)) {
    std::move(done).Run(nil);
    return;
  }
  const CGFloat scale =
      ns_window_.backingScaleFactor > 0 ? ns_window_.backingScaleFactor : 1;
  const int width =
      std::max(1, static_cast<int>(std::lround(size.width() * scale)));
  // The copy, or else the preview kept, cut to the card, in points.
  auto finish = [](tabs::TabHandle handle, gfx::SizeF size, int width,
                   base::OnceCallback<void(NSImage*)> done,
                   const SkBitmap& copy) {
    tabs::TabInterface* tab = handle.Get();
    const SkBitmap& source =
        copy.drawsNothing() && tab ? ClairTabPreview::Get(tab->GetContents())
                                   : copy;
    const SkBitmap cut = ClairTabPreview::CutFromTop(source, size, width);
    if (!tab || cut.drawsNothing()) {
      std::move(done).Run(nil);
      return;
    }
    NSImage* image = skia::SkBitmapToNSImage(cut);
    image.size = NSMakeSize(size.width(),
                            size.width() * cut.height() / cut.width());
    std::move(done).Run(image);
  };
  if (contents->GetVisibility() == content::Visibility::VISIBLE) {
    // A page a window shows, as it is now.
    CopyPage(tab, base::BindOnce(finish, tab->GetHandle(), size, width,
                                 std::move(done)));
    return;
  }
  finish(tab->GetHandle(), size, width, std::move(done), SkBitmap());
}

void ClairBrowserWindow::KeepPreviews(
    content::WebContents* old_contents,
    const std::set<content::WebContents*>& shown) {
  if (!old_contents || ClairSpaceTabs::IsPlaceholder(old_contents) ||
      !IsVisible()) {
    return;
  }
  for (content::WebContents* page : PagesShownWith(old_contents)) {
    tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(page);
    // Each pane of a split. A Peek's parent keeps its own page; the Peek,
    // never a row, has none.
    if (shown.contains(page) || !tab || page->IsCrashed() ||
        ClairSpaceTabs::IsPlaceholder(page) ||
        (peeks_ && peeks_->ParentOf(tab))) {
      continue;
    }
    // Hidden, a page gives up its compositor, and viz never draws the
    // surface the copy waits for. As Chromium's background thumbnails do, a
    // hidden capture keeps it painting, the page told it's hidden, until the
    // copy is back.
    base::ScopedClosureRunner painting = page->IncrementCapturerCount(
        gfx::Size(), /*stay_hidden=*/true, /*stay_awake=*/false,
        /*is_activity=*/false);
    CopyPage(tab, base::BindOnce(
                      [](tabs::TabHandle handle,
                         base::ScopedClosureRunner painting,
                         const SkBitmap& copy) {
                        if (tabs::TabInterface* tab = handle.Get()) {
                          ClairTabPreview::Keep(tab->GetContents(), copy);
                        }
                      },
                      tab->GetHandle(), std::move(painting)));
  }
}

void ClairBrowserWindow::ShowSpace(const std::string& space,
                                   bool again,
                                   tabs::TabInterface* tab) {
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  if (!space_tabs_ || !space_tabs_->is_regular() || !store->Contains(space) ||
      (space == shown_space_ && !again)) {
    return;
  }
  // add-profiles D3: a Space of another profile is the group's to show.
  if (store->ProfileOf(space) !=
      clair::ClairProfiles::IDOf(browser_->GetProfile())) {
    if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
      group->ShowSpace(space, {},
                       tab ? tab->GetHandle() : tabs::TabHandle::Null());
    }
    return;
  }
  // add-tab-switcher-and-tabs-menu D1: the switcher's tab, a row of the Space
  // or a favorite, shows in place of the one Clair would pick, so no other
  // tab shows on the way.
  if (tab && space_tabs_->IsListed(tab) &&
      (space_tabs_->SpaceOf(tab) == space || space_tabs_->IsFavoriteTab(tab))) {
    SetShownSpace(space);
    // The group reveals this member right after: the tab moves here at once,
    // a window that showed it getting its still's image when the copy comes.
    ClairTakeOptions options;
    options.wait_for_copy = false;
    ActivateRow(RowOf(tab), std::move(options));
    return;
  }
  // Shown again: the active tab stays if it's a row of the Space.
  if (space == shown_space_) {
    tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
    if (active && !ClairSpaceTabs::IsPlaceholder(active->GetContents()) &&
        space_tabs_->SpaceOf(active) == space) {
      return;
    }
  }
  // share-tabs-across-windows D3: the tab last active in the Space here,
  // unless another window shows it; else the Space's most recently active row
  // that no window shows, from any window.
  // add-pinned-tabs-and-favorites D2: its open pinned tabs are rows too, and
  // the favorite last shown in it may show again.
  std::vector<tabs::TabInterface*> rows = space_tabs_->PinnedTabsIn(space);
  for (tabs::TabInterface* tab : space_tabs_->TabsIn(space)) {
    if (RowOf(tab) == tab) {
      rows.push_back(tab);
    }
  }
  tabs::TabInterface* target = nullptr;
  if (auto last = last_active_.find(space); last != last_active_.end()) {
    tabs::TabInterface* tab = last->second.Get();
    tabs::TabInterface* row = tab ? RowOf(tab) : nullptr;
    if (row &&
        (std::ranges::find(rows, row) != rows.end() ||
         space_tabs_->IsFavoriteTab(row)) &&
        !IsShownElsewhere(row)) {
      target = tab;
    }
  }
  if (!target) {
    for (tabs::TabInterface* row : rows) {
      if (!IsShownElsewhere(row) &&
          (!target || LastActive(row) > LastActive(target))) {
        target = row;
      }
    }
  }
  // ClairUI hears of the Space before the tab that shows it.
  SetShownSpace(space);
  if (!target) {
    OpenNewTabPage(/*show_command_bar=*/true);
    return;
  }
  if (RowOf(target) == target) {
    ActivateRow(target);
  } else {
    ActivateTab(target);
  }
}

bool ClairBrowserWindow::ExecuteTabCommand(int command) {
  const bool select_index =
      command >= IDC_SELECT_TAB_0 && command <= IDC_SELECT_TAB_7;
  // add-tab-switcher-and-tabs-menu D5a: Ctrl+Tab is ClairUI's switcher.
  const bool step = command == IDC_SELECT_NEXT_TAB ||
                    command == IDC_SELECT_PREVIOUS_TAB;
  TabStripModel* strip = browser_->tab_strip_model();
  tabs::TabInterface* active = strip->GetActiveTab();
  // While the window shows a still, the still's row stands for the active
  // one, as the sidebar highlights it.
  tabs::TabInterface* active_row = HighlightedRow();
  if (select_index || step || command == IDC_SELECT_LAST_TAB) {
    // Over the rows the sidebar lists, where a tab and its Peek are one
    // stop, and never into another Space. A row another window holds is
    // taken from it (share-tabs-across-windows D3). Every pinned tab is a
    // row, open or not, and landing on one that isn't opens it; favorites
    // are none (add-pinned-tabs-and-favorites D4). A closed folder's pinned
    // tabs are none either, except those whose page is open
    // (add-tab-folders D9).
    struct Slot {
      raw_ptr<tabs::TabInterface> tab;
      std::string pin;
    };
    std::vector<Slot> slots;
    std::set<std::string> split_slots;
    for (const clair::Pin* pin : RowPins(shown_space_)) {
      // add-split-view: a pinned split is one row.
      if (!pin->split.empty() && !split_slots.insert(pin->split).second) {
        continue;
      }
      slots.push_back({space_tabs_->BoundTab(pin->id), pin->id});
    }
    for (tabs::TabInterface* row : TodayRows()) {
      slots.push_back({row, std::string()});
    }
    if (slots.empty()) {
      return true;
    }
    auto activate = [this](const Slot& slot) {
      if (slot.tab) {
        ActivateRow(slot.tab);
      } else {
        clair::OpenPin(this, slot.pin);
      }
    };
    const int count = static_cast<int>(slots.size());
    if (select_index) {
      const int index = command - IDC_SELECT_TAB_0;
      if (index < count) {
        activate(slots[index]);
      }
      return true;
    }
    if (command == IDC_SELECT_LAST_TAB) {
      activate(slots.back());
      return true;
    }
    auto it = std::ranges::find_if(slots, [&](const Slot& slot) {
      return slot.tab && active_row &&
           (slot.tab == active_row ||
            ClairSplits::PartnerOf(slot.tab) == active_row);
    });
    const bool forward = command == IDC_SELECT_NEXT_TAB;
    // From a favorite, the first or last row.
    const int position = it == slots.end()
                             ? (forward ? -1 : count)
                             : static_cast<int>(it - slots.begin());
    activate(slots[(position + (forward ? 1 : -1) + count) % count]);
    return true;
  }
  switch (command) {
    case IDC_MOVE_TAB_NEXT:
    case IDC_MOVE_TAB_PREVIOUS: {
      // One row down or up within its section, stopping at the ends as
      // Chromium does (add-pinned-tabs-and-favorites D4), and within its
      // folder (add-tab-folders D9). The strip keeps its order, which means
      // nothing to the user (D2).
      if (!space_tabs_) {
        return true;
      }
      const bool down = command == IDC_MOVE_TAB_NEXT;
      if (const std::string pin = space_tabs_->PinOf(active_row);
          !pin.empty()) {
        clair::ClairPinStore* store = clair::ClairPinStore::Get();
        const clair::Pin* record = store->Find(pin);
        std::optional<size_t> index = store->IndexOf(pin);
        if (!record || !index || record->container.is_favorites()) {
          return true;
        }
        // A top-level pin steps over a folder as over a pin.
        const size_t count = store->ChildrenOf(record->container).size();
        if (down ? *index + 1 < count : *index > 0) {
          store->Move(pin, record->container, down ? *index + 1 : *index - 1);
        }
        return true;
      }
      const std::vector<tabs::TabInterface*> rows = TodayRows();
      auto it = std::ranges::find(rows, active_row);
      if (it == rows.end()) {
        return true;
      }
      if (down ? it + 1 != rows.end() : it != rows.begin()) {
        space_tabs_->MoveTabBeside(active_row, down ? *(it + 1) : *(it - 1),
                                   /*after=*/down);
      }
      return true;
    }
    case IDC_RESTORE_TAB:
      // add-pinned-tabs-and-favorites D3: a pin removed after the last tab
      // Chromium would reopen comes back first. add-profiles D3: what closed
      // last in any of the group's profiles comes back.
      return clair::RestoreLastClosed(this);
    case IDC_CLOSE_WINDOW:
      // The user closes the window: its tabs may move to another
      // (share-tabs-across-windows D4).
      WindowCloseRequested();
      return true;
    case IDC_FULLSCREEN:
      // add-profiles D4: a window covering its group's full-screen one
      // leaves the group's full screen; Chromium would try to enter its own.
      if (NSWindow* fullscreen = FullscreenNSWindow(); fullscreen != ns_window_) {
        [fullscreen toggleFullScreen:nil];
        return true;
      }
      return false;
    case IDC_CLOSE_TAB:
      // A Peek's Cmd+W is ClairPeeks'; it runs first. While the window shows
      // a still, the still's row is the one closed.
      CloseTab(still_tab_.Get() ? still_tab_.Get() : active);
      return true;
    default:
      return false;
  }
}

// --- Tabs shared across windows (share-tabs-across-windows D1, D2, D4) ---

bool ClairBrowserWindow::CanTake(const tabs::TabInterface* tab) const {
  ClairBrowserWindow* holder = HolderOf(tab);
  return tab && holder && holder != this && space_tabs_ &&
         space_tabs_->is_regular() && holder->space_tabs() == space_tabs_ &&
         !detached_ && !browser_->IsDeleteScheduled() &&
         !ClairSpaceTabs::IsPlaceholder(tab->GetContents());
}

void ClairBrowserWindow::Take(tabs::TabInterface* tab,
                              ClairTakeOptions options) {
  if (!CanTake(tab)) {
    if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  tabs::TabInterface* row = RowOf(tab);
  const tabs::TabHandle handle = tab->GetHandle();
  ClairBrowserWindow* holder = HolderOf(tab);
  // D2: the holder keeps a still of what it shows; a hidden member shows
  // nothing (add-profiles D5).
  if (holder->IsActiveRow(row) && !holder->IsHiddenMember()) {
    if (options.wait_for_copy) {
      // The tab waits for its page's copy, taken while the holder still
      // draws it. The same take again joins it: what it runs then, as a
      // second close, waits too.
      if (taking_ == handle) {
        if (options.then) {
          pending_take_thens_.push_back(std::move(options.then));
        }
        return;
      }
      CancelPendingTake();
      taking_ = handle;
      CopyPage(row, base::BindOnce(&ClairBrowserWindow::FinishTake,
                                   weak_factory_.GetWeakPtr(), handle,
                                   ++take_generation_, std::move(options)));
      return;
    }
    // At once: the still's image follows if the copy comes.
    holder->CopyPage(row,
                     base::BindOnce(&ClairBrowserWindow::SetStillImage,
                                    holder->weak_factory_.GetWeakPtr(),
                                    row->GetHandle()));
  }
  CancelPendingTake();
  FinishTake(handle, take_generation_, std::move(options), SkBitmap());
}

void ClairBrowserWindow::CancelPendingTake() {
  if (taking_ == tabs::TabHandle::Null()) {
    return;
  }
  // Its FinishTake() comes with an old generation and moves nothing; what
  // joined it, as a second close, runs once the current task is done, which
  // may be a strip's notification.
  taking_ = tabs::TabHandle::Null();
  ++take_generation_;
  std::vector<base::OnceClosure> thens = std::move(pending_take_thens_);
  pending_take_thens_.clear();
  if (thens.empty()) {
    return;
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](std::vector<base::OnceClosure> thens) {
                       for (base::OnceClosure& then : thens) {
                         std::move(then).Run();
                       }
                     },
                     std::move(thens)));
}

void ClairBrowserWindow::FinishTake(tabs::TabHandle handle,
                                    int generation,
                                    ClairTakeOptions options,
                                    const SkBitmap& copy) {
  if (generation != take_generation_) {
    // Cancelled: another tab became active here meanwhile.
    if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  std::vector<base::OnceClosure> thens;
  if (taking_ == handle) {
    taking_ = tabs::TabHandle::Null();
    thens = std::move(pending_take_thens_);
    pending_take_thens_.clear();
  }
  // What joined the take runs after it.
  if (!thens.empty()) {
    base::OnceClosure first = std::move(options.then);
    options.then = base::BindOnce(
        [](base::OnceClosure first, std::vector<base::OnceClosure> rest) {
          if (first) {
            std::move(first).Run();
          }
          for (base::OnceClosure& then : rest) {
            std::move(then).Run();
          }
        },
        std::move(first), std::move(thens));
  }
  tabs::TabInterface* tab = handle.Get();
  if (!CanTake(tab)) {
    // Here already, as by another way meanwhile, it only becomes active.
    if (tab && HolderOf(tab) == this) {
      ActivateTab(tab, std::move(options));
    } else if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  tabs::TabInterface* row = RowOf(tab);
  ClairBrowserWindow* holder = HolderOf(tab);
  if (holder->IsActiveRow(row) && !holder->IsHiddenMember()) {
    holder->BeginStill(row, copy);
  }
  MoveFamilyHere(holder, row);
  ActivateTab(handle.Get(), std::move(options));
}

void ClairBrowserWindow::SetStillImage(tabs::TabHandle handle,
                                       const SkBitmap& copy) {
  if (still_tab_ != handle || still_image_ || copy.drawsNothing()) {
    return;
  }
  still_image_ = StillImageFrom(copy);
  [bridge_ stillChanged];
}

NSImage* ClairBrowserWindow::StillImageFrom(const SkBitmap& copy) const {
  if (copy.drawsNothing()) {
    return nil;
  }
  // In points, as the card lays it out.
  const CGFloat scale =
      ns_window_.backingScaleFactor > 0 ? ns_window_.backingScaleFactor : 1;
  NSImage* image = skia::SkBitmapToNSImage(copy);
  image.size = NSMakeSize(copy.width() / scale, copy.height() / scale);
  return image;
}

void ClairBrowserWindow::CopyPage(
    tabs::TabInterface* row,
    base::OnceCallback<void(const SkBitmap&)> done) {
  using Pending = base::RefCountedData<base::OnceCallback<void(const SkBitmap&)>>;
  auto pending = base::MakeRefCounted<Pending>(std::move(done));
  // The tab's own page, never its Peek's, which shows over it.
  content::RenderWidgetHostView* view =
      row ? row->GetContents()->GetRenderWidgetHostView() : nullptr;
  if (!view) {
    std::move(pending->data).Run(SkBitmap());
    return;
  }
  // On the UI thread, as Chromium's tab thumbnails take theirs.
  view->CopyFromSurface(
      gfx::Rect(), gfx::Size(), base::Milliseconds(250),
      base::BindOnce(
          [](scoped_refptr<Pending> pending,
             const content::CopyFromSurfaceResult& result) {
            if (pending->data.is_null()) {
              return;
            }
            std::move(pending->data)
                .Run(result.has_value() ? result->bitmap : SkBitmap());
          },
          pending));
  // Should the copy never answer, the take goes ahead without a still image.
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(
          [](scoped_refptr<Pending> pending) {
            if (!pending->data.is_null()) {
              std::move(pending->data).Run(SkBitmap());
            }
          },
          pending),
      base::Milliseconds(400));
}

void ClairBrowserWindow::MoveFamilyHere(ClairBrowserWindow* from,
                                        tabs::TabInterface* row) {
  if (!from || from == this || !row || !space_tabs_) {
    return;
  }
  TabStripModel* source = from->browser()->tab_strip_model();
  TabStripModel* target = browser_->tab_strip_model();
  // add-split-view D7: a split moves whole, as one collection, with its
  // panes' Peeks.
  if (const std::vector<tabs::TabInterface*> panes = ClairSplits::PanesOf(row);
      !panes.empty() && source->GetIndexOfTab(row) != TabStripModel::kNoTab) {
    std::vector<std::pair<tabs::TabInterface*, tabs::TabInterface*>> peeks;
    for (tabs::TabInterface* pane : panes) {
      if (tabs::TabInterface* peek =
              from->peeks() ? from->peeks()->Release(pane) : nullptr) {
        peeks.emplace_back(pane, peek);
      }
    }
    std::vector<tabs::TabInterface*> moving(panes.begin(), panes.end());
    for (const auto& [pane, peek] : peeks) {
      moving.push_back(peek);
    }
    for (tabs::TabInterface* member : moving) {
      space_tabs_->BeginMove(member);
    }
    std::unique_ptr<DetachedTabCollection> split =
        source->DetachSplitTabForInsertion(*row->GetSplit());
    std::vector<std::unique_ptr<tabs::TabModel>> peek_models;
    for (const auto& [pane, peek] : peeks) {
      const int index = source->GetIndexOfTab(peek);
      if (index != TabStripModel::kNoTab) {
        peek_models.push_back(source->DetachTabAtForInsertion(index));
      }
    }
    target->InsertDetachedSplitTabAt(std::move(split), target->count(),
                                     /*pinned=*/false);
    for (std::unique_ptr<tabs::TabModel>& model : peek_models) {
      target->InsertDetachedTabAt(target->count(), std::move(model),
                                  AddTabTypes::ADD_NONE);
    }
    for (tabs::TabInterface* member : moving) {
      space_tabs_->EndMove(member);
    }
    for (const auto& [pane, peek] : peeks) {
      if (peeks_ && target->GetIndexOfTab(pane) != TabStripModel::kNoTab &&
          target->GetIndexOfTab(peek) != TabStripModel::kNoTab) {
        peeks_->Adopt(pane, peek);
      }
    }
    return;
  }
  // The pair leaves the Peek table there before the strip hears of it.
  tabs::TabInterface* peek = from->peeks() ? from->peeks()->Release(row) : nullptr;
  std::vector<tabs::TabInterface*> family{row};
  if (peek) {
    family.push_back(peek);
  }
  for (tabs::TabInterface* member : family) {
    space_tabs_->BeginMove(member);
  }
  // The tabs and their handles survive the move (design Context).
  std::vector<std::unique_ptr<tabs::TabModel>> models;
  for (tabs::TabInterface* member : family) {
    const int index = source->GetIndexOfTab(member);
    if (index != TabStripModel::kNoTab) {
      models.push_back(source->DetachTabAtForInsertion(index));
    }
  }
  for (std::unique_ptr<tabs::TabModel>& model : models) {
    target->InsertDetachedTabAt(target->count(), std::move(model),
                                AddTabTypes::ADD_NONE);
  }
  for (tabs::TabInterface* member : family) {
    space_tabs_->EndMove(member);
  }
  if (peek && peeks_ && target->GetIndexOfTab(row) != TabStripModel::kNoTab &&
      target->GetIndexOfTab(peek) != TabStripModel::kNoTab) {
    peeks_->Adopt(row, peek);
  }
}

tabs::TabInterface* ClairBrowserWindow::placeholder() const {
  tabs::TabInterface* tab = placeholder_.Get();
  return tab && ClairSpaceTabs::IsPlaceholder(tab->GetContents()) &&
                 browser_->tab_strip_model()->GetIndexOfTab(tab) !=
                     TabStripModel::kNoTab
             ? tab
             : nullptr;
}

void ClairBrowserWindow::BeginStill(tabs::TabInterface* row,
                                    const SkBitmap& copy) {
  if (!row || detached_ || browser_->IsDeleteScheduled()) {
    return;
  }
  still_tab_ = row->GetHandle();
  still_image_ = StillImageFrom(copy);
  // ClairUI hears of the still before the placeholder under it becomes
  // active, so the card never shows the placeholder's page.
  [bridge_ stillChanged];
  // The placeholder: Chromium needs an active tab, and any real tab would run
  // as visible behind the still. It's a new tab page, marked before it joins
  // the strip, so it's in no Space and the window keeps the one it shows.
  std::unique_ptr<content::WebContents> contents = content::WebContents::Create(
      content::WebContents::CreateParams(browser_->GetProfile()));
  ClairSpaceTabs::MarkPlaceholder(contents.get());
  contents->GetController().LoadURL(GURL(chrome::kChromeUINewTabURL),
                                    content::Referrer(),
                                    ui::PAGE_TRANSITION_AUTO_TOPLEVEL,
                                    std::string());
  content::WebContents* raw = contents.get();
  TabStripModel* strip = browser_->tab_strip_model();
  strip->InsertWebContentsAt(strip->count(), std::move(contents),
                             AddTabTypes::ADD_ACTIVE);
  if (tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(raw)) {
    placeholder_ = tab->GetHandle();
  }
}

void ClairBrowserWindow::EndStill() {
  const bool had_still = still_tab_ != tabs::TabHandle::Null();
  still_tab_ = tabs::TabHandle::Null();
  still_image_ = nil;
  tabs::TabInterface* placeholder = this->placeholder();
  placeholder_ = tabs::TabHandle::Null();
  if (had_still) {
    [bridge_ stillChanged];
  }
  if (!placeholder) {
    return;
  }
  // Not from inside the strip's notification, which can't be re-entered.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<ClairBrowserWindow> window, tabs::TabHandle handle) {
            tabs::TabInterface* tab = handle.Get();
            if (!window || !tab ||
                !ClairSpaceTabs::IsPlaceholder(tab->GetContents())) {
              return;
            }
            TabStripModel* strip = window->browser()->tab_strip_model();
            const int index = strip->GetIndexOfTab(tab);
            if (index != TabStripModel::kNoTab && strip->GetActiveTab() != tab) {
              strip->CloseWebContentsAt(index, TabCloseTypes::CLOSE_NONE);
            }
          },
          weak_factory_.GetWeakPtr(), placeholder->GetHandle()));
}

void ClairBrowserWindow::StillTabClosed() {
  tabs::TabInterface* placeholder = this->placeholder();
  still_tab_ = tabs::TabHandle::Null();
  still_image_ = nil;
  placeholder_ = tabs::TabHandle::Null();
  [bridge_ stillChanged];
  if (!placeholder || !space_tabs_) {
    return;
  }
  // D2: an ordinary new tab page at the top of the shown Space, with the
  // command bar.
  space_tabs_->ListPlaceholder(browser_->tab_strip_model(), placeholder);
  last_active_[shown_space_] = placeholder->GetHandle();
  came_from_ = tabs::TabHandle::Null();
  [clair_window_ showCommandBarWithMode:ClairCommandBarModeCurrentTab];
}

bool ClairBrowserWindow::HandTabsTo(ClairBrowserWindow* target,
                                    tabs::TabInterface* except) {
  if (!target || target == this || !space_tabs_ || !space_tabs_->is_regular() ||
      target->space_tabs_ != space_tabs_ || detached_ || target->detached_ ||
      target->browser()->IsDeleteScheduled() ||
      browser_shutdown::IsTryingToQuit()) {
    return false;
  }
  // Each row with its Peek, the placeholder and `except` left out, the active
  // row last so Chromium picks this window's next tab only once.
  TabStripModel* strip = browser_->tab_strip_model();
  tabs::TabInterface* active = strip->GetActiveTab();
  tabs::TabInterface* active_row = active ? RowOf(active) : nullptr;
  std::vector<tabs::TabHandle> rows;
  for (int i = 0; i < strip->count(); ++i) {
    tabs::TabInterface* tab = strip->GetTabAtIndex(i);
    // A Peek, and a split's pane that isn't its row, move with their row
    // (add-split-view D7).
    if (!tab || tab == active_row || tab == except ||
        ClairSpaceTabs::IsPlaceholder(tab->GetContents()) ||
        RowOf(tab) != tab) {
      continue;
    }
    rows.push_back(tab->GetHandle());
  }
  if (active_row && active_row != except &&
      !ClairSpaceTabs::IsPlaceholder(active_row->GetContents())) {
    rows.push_back(active_row->GetHandle());
  }
  if (rows.empty()) {
    return false;
  }
  for (const tabs::TabHandle& handle : rows) {
    if (tabs::TabInterface* row = handle.Get()) {
      target->MoveFamilyHere(this, row);
    }
    // D2: a third window with a still of it takes it back, as no window
    // shows it now.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&GiveBackToStill, handle));
  }
  // Emptied, or left with its placeholder or `except`, the browser closes;
  // the window goes now, so it can't become key meanwhile.
  if (!HasRealTabs() ||
      (except && strip->count() == 1 && strip->GetTabAtIndex(0) == except)) {
    [ns_window_ orderOut:nil];
  }
  if (!HasRealTabs() && !strip->empty()) {
    // Only the placeholder is left: it closes, and the browser with it.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ClairBrowserWindow> window) {
                         if (window && !window->HasRealTabs() &&
                             !window->browser()->IsDeleteScheduled()) {
                           window->Close();
                         }
                       },
                       weak_factory_.GetWeakPtr()));
  }
  // The other window showed a still of one of them: it shows the tab now.
  if (tabs::TabInterface* still = target->still_tab_.Get();
      still && HolderOf(still) == target && !target->IsHiddenMember()) {
    target->ActivateRow(still);
  }
  return true;
}

void ClairBrowserWindow::ForgetFindBar() {
  find_bar_ = nullptr;
}

// --- Events from the NSWindow ---

void ClairBrowserWindow::WindowDidBecomeKey() {
  // A browser that's closing has left Chromium's list of browsers, which
  // CHECKs that an active one is in it. Its window can still become key, as
  // when it handed its tabs to another window (share-tabs-across-windows D4)
  // and AppKit orders a child window such as a tooltip.
  if (detached_ || browser_->IsDeleteScheduled() ||
      browser_->tab_strip_model()->empty()) {
    return;
  }
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
    group->Activated();
  }
  if (command_bar_when_key_) {
    command_bar_when_key_ = false;
    OpenCommandBarWhenShown();
  }
  // add-spaces D1: the Space a new window shows.
  if (space_tabs_ && space_tabs_->is_regular()) {
    clair::ClairSpaceStore::Get()->SetLastSpace(shown_space_);
  }
  // share-tabs-across-windows D2: a window showing a still takes its tab
  // back, once AppKit has finished making it key. As in Arc, the click that
  // made it key reaches no row, so it doesn't wait for that click.
  if (still_tab_ != tabs::TabHandle::Null()) {
    PostTakeBack(weak_factory_.GetWeakPtr());
  }
}

void ClairBrowserWindow::WindowDidResignKey() {
  BrowserActiveStateManager::From(browser_)->DidBecomeInactive();
}

void ClairBrowserWindow::WindowGeometryChanged() {
  if (!IsFullscreen() && !IsMinimized() && !ns_window_.zoomed) {
    restored_bounds_ = gfx::ScreenRectFromNSRect(ns_window_.frame);
  }
  // The group's hidden members follow the shown one's frame. Session restore
  // builds the window from the first profile it restores, which may be a
  // hidden member's (add-profiles D6): without this, a window moved or
  // resized while it showed another profile's Space came back at that
  // member's old frame. A hidden member's own change goes no further.
  ClairWindowGroup* group = ClairWindowGroup::Of(this);
  if (group && group->shown() == this && !IsFullscreen() && !IsMinimized()) {
    for (ClairBrowserWindow* member : group->members()) {
      if (member != this &&
          !NSEqualRects(member->ns_window().frame, ns_window_.frame)) {
        [member->ns_window() setFrame:ns_window_.frame display:NO];
      }
    }
  }
  if (!IsFullscreen() && chrome::ShouldSaveWindowPlacement(browser_)) {
    chrome::SaveWindowPlacement(browser_, GetRestoredBounds(),
                                GetWindowShowState());
  }
  modal_dialog_host_.NotifyPositionRequiresUpdate();
}

bool ClairBrowserWindow::HandleExclusiveAccessKey(NSEvent* event) {
  if (!exclusive_access_context_.page_fullscreen() ||
      (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp)) {
    return false;
  }
  if (exclusive_access_context_.DeferExitWhileEntering(event)) {
    return true;
  }
  return ExclusiveAccessManager::From(browser_)->HandleUserKeyEvent(
      input::NativeWebKeyboardEvent(gfx::NativeEvent(event)));
}

bool ClairBrowserWindow::CountEscapeTap(NSEvent* event) {
  return exclusive_access_context_.CountEscapeTap(event);
}

void ClairBrowserWindow::WindowFullscreenChanged(bool entered) {
  exclusive_access_context_.WindowFullscreenChanged(entered);
  WindowGeometryChanged();
  // add-profiles D4: the group's full-screen owner, and its cover.
  if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
    group->FullscreenChanged(this, entered);
  }
}

void ClairBrowserWindow::WindowCloseRequested() {
  // share-tabs-across-windows D4, add-profiles D5: when the user closes the
  // window, by its close button or File > Close Window, and another regular
  // window is open, the tabs of every member of its group move there and
  // none closes. Moving the last one empties a strip, and TabStripEmpty()
  // closes that browser. With none, the members close through Chromium's
  // close flow. Every other close, as by an extension or of a profile, is
  // Chromium's for this browser alone.
  ClairWindowGroup* group = ClairWindowGroup::Of(this);
  if (group && !browser_->IsDeleteScheduled() && space_tabs_ &&
      space_tabs_->is_regular()) {
    group->CloseByUser();
    return;
  }
  Close();
}

void ClairBrowserWindow::UpdateDevTools() {
  [clair_window_ devToolsDidChange];
}

void ClairBrowserWindow::ShowToast(const std::u16string& text) {
  [clair_window_ showToast:base::SysUTF16ToNSString(text)];
}

gfx::Rect ClairBrowserWindow::SiteControlsAnchorInScreen() const {
  id<ClairWindow> window = clair_window_;
  if (!window) {
    return gfx::Rect(GetBounds().origin(), gfx::Size());
  }
  const ClairAnchor anchor = [window anchorForKind:ClairAnchorKindSiteControls
                                         indicator:ClairTabIndicatorsNone
                                       extensionID:nil];
  return gfx::ScreenRectFromNSRect(
      [ns_window_ convertRectToScreen:anchor.rect]);
}

void ClairBrowserWindow::ZoomChanged(bool can_show_bubble) {
  if (!can_show_bubble) {
    return;
  }
  content::WebContents* active = browser_->tab_strip_model()->GetActiveWebContents();
  auto* zoom = active ? zoom::ZoomController::FromWebContents(active) : nullptr;
  if (!zoom) {
    return;
  }
  // arc-popup-notices D4: the level alone, in the popup.
  [clair_window_ showZoomLevel:zoom->GetZoomPercent()];
}

// --- ui::BaseWindow ---

bool ClairBrowserWindow::IsActive() const {
  return ns_window_.keyWindow;
}

bool ClairBrowserWindow::IsMaximized() const {
  return ns_window_.zoomed;
}

bool ClairBrowserWindow::IsMinimized() const {
  return ns_window_.miniaturized;
}

bool ClairBrowserWindow::IsFullscreen() const {
  // add-profiles D4: the cover over a full-screen window is in full screen
  // with its group.
  if (ClairWindowGroup* group = ClairWindowGroup::Of(this);
      group && group->IsFullscreen() && !IsHiddenMember()) {
    return true;
  }
  return (ns_window_.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

gfx::NativeWindow ClairBrowserWindow::GetNativeWindow() const {
  return gfx::NativeWindow(ns_window_);
}

gfx::Rect ClairBrowserWindow::GetRestoredBounds() const {
  return restored_bounds_.IsEmpty() ? GetBounds() : restored_bounds_;
}

ui::mojom::WindowShowState ClairBrowserWindow::GetRestoredState() const {
  return IsMaximized() ? ui::mojom::WindowShowState::kMaximized
                       : ui::mojom::WindowShowState::kNormal;
}

gfx::Rect ClairBrowserWindow::GetBounds() const {
  return gfx::ScreenRectFromNSRect(ns_window_.frame);
}

void ClairBrowserWindow::Show() {
  // The window took its frame in the constructor, before the session tracked
  // it, and WindowGeometryChanged() records only changes: record it once, or
  // a restored window that isn't moved quits with no frame in the session
  // and comes back at the default one on the next launch. Hidden members of
  // a group record theirs too, since session restore builds the window from
  // whichever profile it restores first (add-profiles D6).
  if (!placement_recorded_) {
    placement_recorded_ = true;
    if (chrome::ShouldSaveWindowPlacement(browser_)) {
      chrome::SaveWindowPlacement(
          browser_, GetRestoredBounds(),
          initial_show_state_ == ui::mojom::WindowShowState::kDefault
              ? ui::mojom::WindowShowState::kNormal
              : initial_show_state_);
    }
  }
  // add-profiles D6: session restore's windows wait until it has finished.
  if (ClairWindowGroup::HoldsShow(this)) {
    return;
  }
  // D3: Chromium asks to see a hidden member, as for a link from another app
  // or Switch to Tab: the group switches to it.
  if (ClairWindowGroup* group = ClairWindowGroup::Of(this);
      group && group->IsHidden(this)) {
    // Start-up showing what it restored, after the arrangement chose.
    if (ClairWindowGroup::TakeStartupShow(this)) {
      return;
    }
    group->ShowMember(this);
    if (!IsHiddenMember()) {
      Activate();
    }
    return;
  }
  ShowNow();
}

void ClairBrowserWindow::ShowNow() {
  // As BrowserView::Show(): the browser becomes the last active one now, not
  // when AppKit gets round to making the window key.
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  const bool was_visible = ns_window_.visible;
  if (extensions_) {
    extensions_->FlushIfStale();
  }
  // Change 1's background-relaunch hook keeps this from bringing Clair
  // forward when it relaunched behind another app.
  [NSApp activateIgnoringOtherApps:YES];
  [ns_window_ makeKeyAndOrderFront:nil];
  if (!was_visible) {
    if (initial_show_state_ == ui::mojom::WindowShowState::kMaximized &&
        !ns_window_.zoomed) {
      [ns_window_ zoom:nil];
    } else if (initial_show_state_ == ui::mojom::WindowShowState::kMinimized) {
      [ns_window_ miniaturize:nil];
    } else if (initial_show_state_ == ui::mojom::WindowShowState::kFullscreen) {
      [ns_window_ toggleFullScreen:nil];
    }
    if (content::WebContents* active =
            browser_->tab_strip_model()->GetActiveWebContents()) {
      for (content::WebContents* page : PagesShownWith(active)) {
        page->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
      }
      active->Focus();
    }
  }
}

void ClairBrowserWindow::Hide() {
  [ns_window_ orderOut:nil];
}

bool ClairBrowserWindow::IsVisible() const {
  return ns_window_.visible;
}

void ClairBrowserWindow::ShowInactive() {
  if (ClairWindowGroup::HoldsShow(this) || IsHiddenMember()) {
    return;
  }
  [ns_window_ orderFront:nil];
}

void ClairBrowserWindow::Close() {
  // add-peek D9: Peeks close with the window's other tabs; session restore
  // and Reopen Closed Window leave them out by their tag.
  // Chromium's close flow: beforeunload may veto it; then the tabs close, and
  // TabStripEmpty() calls this again for the empty browser, whose deletion
  // UnloadController then schedules. The browser is never deleted here.
  UnloadController* unload = UnloadController::From(browser_);
  unload->OnWindowClosing();
  if (!browser_->IsDeleteScheduled() &&
      !unload->is_attempting_to_close_browser()) {
    // add-profiles D5: a warning, as of downloads in progress, stopped the
    // close before it started; the group's close stops with it.
    if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
      group->CloseCancelled(this);
    }
    return;
  }
  if (browser_->IsDeleteScheduled()) {
    // add-profiles D4: a cover over this window stays, as the window.
    if (ClairWindowGroup* group = ClairWindowGroup::Of(this)) {
      group->OwnerClosing(this);
    }
    DetachFromClairUI();
    [ns_window_ orderOut:nil];
  }
}

void ClairBrowserWindow::Activate() {
  if (ClairWindowGroup::HoldsShow(this)) {
    ClairWindowGroup::NoteRestoreActivation(this);
    return;
  }
  if (ClairWindowGroup* group = ClairWindowGroup::Of(this);
      group && group->IsHidden(this)) {
    if (ClairWindowGroup::TakeStartupShow(this)) {
      return;
    }
    group->ShowMember(this);
    if (IsHiddenMember()) {
      return;
    }
  }
  [NSApp activateIgnoringOtherApps:YES];
  [ns_window_ makeKeyAndOrderFront:nil];
}

// add-profiles D3: a member its group keeps hidden stays as it is, whoever
// asks (an extension's chrome.windows.update, DevTools): ordering it back
// would show it beside the shown member, and the group gives it the shown
// member's frame when it swaps it in. Activate() reaches it, as a switch.

void ClairBrowserWindow::Deactivate() {
  if (IsHiddenMember()) {
    return;
  }
  [ns_window_ orderBack:nil];
}

void ClairBrowserWindow::Maximize() {
  if (IsHiddenMember()) {
    return;
  }
  if (!ns_window_.zoomed) {
    [ns_window_ zoom:nil];
  }
}

void ClairBrowserWindow::Minimize() {
  if (IsHiddenMember()) {
    return;
  }
  [ns_window_ miniaturize:nil];
}

void ClairBrowserWindow::Restore() {
  if (IsHiddenMember()) {
    return;
  }
  if (ns_window_.miniaturized) {
    [ns_window_ deminiaturize:nil];
  }
  if (ns_window_.zoomed) {
    [ns_window_ zoom:nil];
  }
}

void ClairBrowserWindow::SetBounds(const gfx::Rect& bounds) {
  if (IsFullscreen() || IsHiddenMember()) {
    return;
  }
  [ns_window_ setFrame:ToNSRect(bounds) display:YES];
}

void ClairBrowserWindow::FlashFrame(bool flash) {
  if (flash) {
    [NSApp requestUserAttention:NSInformationalRequest];
  }
}

ui::ZOrderLevel ClairBrowserWindow::GetZOrderLevel() const {
  return ns_window_.level > NSNormalWindowLevel
             ? ui::ZOrderLevel::kFloatingWindow
             : ui::ZOrderLevel::kNormal;
}

void ClairBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {
  ns_window_.level = order == ui::ZOrderLevel::kNormal ? NSNormalWindowLevel
                                                       : NSFloatingWindowLevel;
}

// --- BrowserWindow ---

bool ClairBrowserWindow::IsOnCurrentWorkspace() const {
  return ns_window_.onActiveSpace;
}

bool ClairBrowserWindow::IsVisibleOnScreen() const {
  return (ns_window_.occlusionState & NSWindowOcclusionStateVisible) != 0;
}

void ClairBrowserWindow::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool ClairBrowserWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* ClairBrowserWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* ClairBrowserWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

const ui::ColorProvider* ClairBrowserWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(nullptr,
                                                                     false));
}

int ClairBrowserWindow::GetTopControlsHeight() const {
  return 0;
}

void ClairBrowserWindow::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

std::vector<StatusBubble*> ClairBrowserWindow::GetStatusBubbles() {
  // Chromium treats every status bubble it gets here as a Views one
  // (BrowserWebContentsDelegate), so the native window's is reached through
  // the hook instead.
  return {};
}

void ClairBrowserWindow::SetStatusURL(const GURL& url,
                                      content::WebContents* source) {
  status_bubble_.SetURL(url, source);
}

void ClairBrowserWindow::UpdateTitleBar() {
  // The title isn't drawn, but the Window menu and Mission Control show it.
  // add-pinned-tabs-and-favorites D8: the active row's custom name, if it has
  // one.
  if (tabs::TabInterface* row = HighlightedRow(); row && space_tabs_) {
    if (const std::string name = space_tabs_->NameOf(row); !name.empty()) {
      ns_window_.title = base::SysUTF8ToNSString(name);
      return;
    }
  }
  if (auto* metadata = WindowMetadataController::From(browser_)) {
    ns_window_.title = base::SysUTF16ToNSString(
        metadata->GetWindowTitleForCurrentTab(/*include_app_name=*/false));
  }
}

void ClairBrowserWindow::UpdateLoadingAnimations(bool is_visible) {
  if (content::WebContents* active =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    [bridge_ tabChanged:active];
  }
}

void ClairBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                            content::WebContents* new_contents,
                                            int index,
                                            int reason) {
  // A tab created in the background has never been sized; give it the
  // outgoing tab's size so its first layout isn't at zero.
  if (old_contents && new_contents->GetSize().IsEmpty()) {
    const gfx::Size size = old_contents->GetContainerBounds().size();
    if (!size.IsEmpty()) {
      new_contents->Resize(gfx::Rect(size));
    }
  }
  // add-spaces D3: the window shows the active tab's Space. Chromium tells
  // the window before the lists hear of a new tab: a restored one already
  // carries its Space, and a new one joins the shown Space.
  tabs::TabInterface* new_tab =
      tabs::TabInterface::MaybeGetFromContents(new_contents);
  // share-tabs-across-windows D2: the placeholder under a still is in no
  // Space, and leaves the shown Space and the came-from row alone.
  const bool new_is_placeholder = ClairSpaceTabs::IsPlaceholder(new_contents);
  const bool old_is_placeholder =
      old_contents && ClairSpaceTabs::IsPlaceholder(old_contents);
  if (space_tabs_ && new_tab && !new_is_placeholder) {
    const std::string space = space_tabs_->IntendedSpaceOf(new_tab);
    if (!space.empty() && space != shown_space_) {
      SetShownSpace(space);
    }
    last_active_[shown_space_] = new_tab->GetHandle();
  }
  // D4: the row the user came from, unless a close or Clair's own choice
  // changed the active tab.
  tabs::TabInterface* old_tab =
      old_contents ? tabs::TabInterface::MaybeGetFromContents(old_contents)
                   : nullptr;
  const bool old_closed =
      !old_tab || browser_->tab_strip_model()->GetIndexOfTab(old_tab) ==
                      TabStripModel::kNoTab;
  if (new_is_placeholder) {
    // The still keeps the row the user came to it from.
  } else if (old_is_placeholder) {
    // Taking the still's tab back keeps it too; moving on forgets it.
    tabs::TabInterface* still = still_tab_.Get();
    if (!still || !new_tab || RowOf(new_tab) != still) {
      came_from_ = tabs::TabHandle::Null();
    }
  } else if (choosing_next_ || old_closed) {
    came_from_ = tabs::TabHandle::Null();
  } else if (new_tab) {
    // A tab and its Peek, or a split's panes (add-split-view), are one row.
    tabs::TabInterface* row = RowOf(old_tab);
    if (RowOf(new_tab) != row) {
      came_from_ = row->GetHandle();
    }
  }
  // D1: another tab became active here than the one a take waits for, as
  // when the user selected another row meanwhile: the take is dropped.
  if (!new_is_placeholder && taking_ != tabs::TabHandle::Null() &&
      (!new_tab || new_tab->GetHandle() != taking_)) {
    CancelPendingTake();
  }
  // D2: another tab became active, which ends the still: the still's tab came
  // back, or the user selected another row or Space. A member swapped away
  // kept its placeholder without a still (add-profiles D5); it closes too.
  if (!new_is_placeholder && (still_tab_ != tabs::TabHandle::Null() ||
                              placeholder_ != tabs::TabHandle::Null())) {
    EndStill();
  }
  // D2: the row shown until now goes back to a window with a still of it,
  // if no window shows it once the strip is done.
  if (old_tab && !old_closed && !old_is_placeholder) {
    tabs::TabInterface* old_row = RowOf(old_tab);
    if (!new_tab || RowOf(new_tab) != old_row) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&GiveBackToStill, old_row->GetHandle()));
    }
  }
  // A tab and its Peek show together (add-peek D4).
  const std::set<content::WebContents*> shown = PagesShownWith(new_contents);
  // add-tab-switcher-and-tabs-menu D4: the switcher's previews, while the
  // pages leaving are still in the card: once ClairUI takes a page's view out
  // of the window, its surface can't be copied.
  if (old_contents) {
    KeepPreviews(old_contents, shown);
  }
  // ClairUI swaps the page in the card now, before visibility changes.
  [bridge_ activeTabChanged];
  // As WebUIBrowserWindow: the old page reports hidden, the new one the
  // window's visibility.
  if (old_contents) {
    for (content::WebContents* page : PagesShownWith(old_contents)) {
      if (!shown.contains(page)) {
        page->UpdateWebContentsVisibility(content::Visibility::HIDDEN);
      }
    }
  }
  for (content::WebContents* page : shown) {
    page->UpdateWebContentsVisibility(IsVisible() ? content::Visibility::VISIBLE
                                                  : content::Visibility::HIDDEN);
  }
  if (extensions_) {
    extensions_->ActiveTabChanged();
  }
  UpdateDevTools();
  UpdateTitleBar();
  // As BrowserView: the page takes focus when its tab becomes active in the
  // key window.
  if (IsActive()) {
    new_contents->RestoreFocus();
  }
}

void ClairBrowserWindow::OnTabDetached(content::WebContents* contents,
                                       bool was_active) {
  // add-profiles D5: a hidden member needs no tab of its own; when its last
  // one is taken or closes, it closes.
  if (IsHiddenMember()) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ClairBrowserWindow> window) {
                         ClairWindowGroup* group =
                             window ? ClairWindowGroup::Of(window.get())
                                    : nullptr;
                         if (group) {
                           group->MaybeCloseEmptyHiddenMember(window.get());
                         }
                       },
                       weak_factory_.GetWeakPtr()));
  }
}

gfx::Size ClairBrowserWindow::GetContentsSize() const {
  id<ClairWindow> window = clair_window_;
  NSView* view = window ? window.pageContainerView : ns_window_.contentView;
  return view ? gfx::Size(NSWidth(view.bounds), NSHeight(view.bounds))
              : gfx::Size();
}

void ClairBrowserWindow::SetContentsSize(const gfx::Size& size) {
  const gfx::Size current = GetContentsSize();
  NSRect frame = ns_window_.frame;
  const CGFloat dw = size.width() - current.width();
  const CGFloat dh = size.height() - current.height();
  frame.size.width += dw;
  frame.size.height += dh;
  frame.origin.y -= dh;
  [ns_window_ setFrame:frame display:YES];
}

autofill::AutofillBubbleHandler* ClairBrowserWindow::GetAutofillBubbleHandler() {
  return autofill_bubble_handler_.get();
}

LocationBar* ClairBrowserWindow::GetLocationBar() const {
  return const_cast<ClairLocationBar*>(&location_bar_);
}

ui::AcceleratorProvider* ClairBrowserWindow::GetAcceleratorProvider() {
  return nullptr;
}

PinnedToolbarActions* ClairBrowserWindow::GetPinnedToolbarActions() {
  return nullptr;
}

void ClairBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {
  // Cmd+L: the command bar on the current URL (D10). Chromium also asks for
  // the location bar on its own, as when a new tab page loads, which would
  // open the command bar over every new window; that keeps the page focused.
  if (!is_user_initiated) {
    return;
  }
  [clair_window_ showCommandBarWithMode:ClairCommandBarModeCurrentTab];
}

void ClairBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {
  UpdateLoadingAnimations(true);
}

void ClairBrowserWindow::UpdateToolbar(content::WebContents* contents) {
  content::WebContents* tab =
      contents ? contents : browser_->tab_strip_model()->GetActiveWebContents();
  if (tab) {
    [bridge_ tabChanged:tab];
  }
}

bool ClairBrowserWindow::UpdateToolbarSecurityState() {
  UpdateToolbar(nullptr);
  return true;
}

void ClairBrowserWindow::UpdateCustomTabBarVisibility(bool visible,
                                                      bool animate) {}
void ClairBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}
void ClairBrowserWindow::FocusToolbar() {}
void ClairBrowserWindow::ToolbarSizeChanged(bool is_animating) {}
void ClairBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}
void ClairBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}

void ClairBrowserWindow::FocusAppMenu() {
  LogUnavailable("The app menu");
}

bool ClairBrowserWindow::IsTabStripEditable() const {
  return true;
}

void ClairBrowserWindow::DisableTabStripEditingForTesting() {}

bool ClairBrowserWindow::IsToolbarVisible() const {
  // The sidebar is the toolbar: chrome.action.openPopup() checks this.
  return true;
}

bool ClairBrowserWindow::IsToolbarShowing() const {
  return false;
}

// The URL field and the command bar stand in for the location bar. Chromium
// focuses the location bar for Cmd+L and File > Open Location only while it's
// visible (browser_command_controller.cc, browser_actions.cc).
bool ClairBrowserWindow::IsLocationBarVisible() const {
  return true;
}

void ClairBrowserWindow::ShowUpdateChromeDialog() {}

void ClairBrowserWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {
  LogUnavailable("The intent picker");
  std::move(callback).Run(std::string(), apps::PickerEntryType::kUnknown,
                          apps::IntentPickerCloseReason::STAY_IN_CHROME,
                          false);
}

void ClairBrowserWindow::ShowBookmarkBubble(const GURL& url,
                                            bool already_bookmarked) {
  // D10: no bookmarks in the interface.
  LogUnavailable("The bookmark bubble");
}

ShowTranslateBubbleResult ClairBrowserWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  LogUnavailable("Translate");
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController* ClairBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

void ClairBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  DownloadInProgressDialogView::Show(GetNativeWindow(), download_count,
                                     dialog_type, std::move(callback));
}

void ClairBrowserWindow::ShowAppMenu() {
  LogUnavailable("The app menu");
}

void ClairBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data,
                                             const gfx::PointF& point) {}
void ClairBrowserWindow::PreHandleDragExit() {}
void ClairBrowserWindow::HandleDragEnded() {}

content::KeyboardEventProcessingResult
ClairBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // As BrowserNativeWidgetMac: key equivalents with modifiers were offered to
  // CommandDispatcher already; the page may have them first unless they're a
  // browser shortcut.
  // add-peek D6: Esc while Confirm shows closes the Peek before the page
  // sees it.
  if (peeks_) {
    const content::KeyboardEventProcessingResult result =
        peeks_->PreHandleKeyboardEvent(event);
    if (result != content::KeyboardEventProcessingResult::NOT_HANDLED) {
      return result;
    }
  }
  // arc-popup-notices D3: an Esc for the page counts towards the double tap
  // that leaves the window's full screen, and the page still gets it. A
  // Peek's Esc is the Peek's.
  if (!peeks_ ||
      !peeks_->ParentOf(browser_->tab_strip_model()->GetActiveTab())) {
    exclusive_access_context_.CountEscapeTap(event.os_event.Get());
  }
  NSEvent* ns_event = event.os_event.Get();
  if (ns_event && EventUsesPerformKeyEquivalent(ns_event)) {
    int command = CommandForKeyEvent(ns_event).chrome_command;
    if (command == -1) {
      command = DelayedWebContentsCommandForKeyEvent(ns_event);
    }
    if (command != -1) {
      return content::KeyboardEventProcessingResult::NOT_HANDLED_IS_SHORTCUT;
    }
  }
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool ClairBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  if (!ShouldHandleKeyboardEvent(event)) {
    return false;
  }
  // add-peek D6: an Esc the Peek's page didn't use closes the Peek.
  if (peeks_ && peeks_->HandleKeyboardEvent(event)) {
    return true;
  }
  // Gives CommandDispatcher the chance to finish passing the key on.
  return [[ns_window_ commandDispatcher] redispatchKeyEvent:event.os_event.Get()];
}

std::unique_ptr<FindBar> ClairBrowserWindow::CreateFindBar() {
  auto find_bar = std::make_unique<ClairFindBar>(this);
  find_bar_ = find_bar.get();
  return find_bar;
}

web_modal::WebContentsModalDialogHost*
ClairBrowserWindow::GetWebContentsModalDialogHost() {
  return &modal_dialog_host_;
}

web_modal::WebContentsModalDialogHost*
ClairBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return &modal_dialog_host_;
}

void ClairBrowserWindow::ShowAvatarBubbleFromAvatarButton(
    bool is_source_accelerator) {
  LogUnavailable("The profile menu");
}

void ClairBrowserWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  std::move(failure_callback).Run();
}

ExclusiveAccessContext* ClairBrowserWindow::GetExclusiveAccessContext() {
  return &exclusive_access_context_;
}

std::string ClairBrowserWindow::GetWorkspace() const {
  return std::string();
}

bool ClairBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return false;
}

void ClairBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> ClairBrowserWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  // Null makes the page's EyeDropper.open() reject.
  LogUnavailable("The EyeDropper");
  return nullptr;
}

void ClairBrowserWindow::ShowCaretBrowsingDialog() {
  LogUnavailable("The caret browsing dialog");
}

void ClairBrowserWindow::CreateTabSearchBubble() {
  LogUnavailable("Tab search");
}

void ClairBrowserWindow::CloseTabSearchBubble() {}

void ClairBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {
  LogUnavailable("The incognito clear browsing data dialog");
}

void ClairBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {
  LogUnavailable("The incognito history disclaimer");
}

bool ClairBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

bool ClairBrowserWindow::GetCanResize() {
  return true;
}

ui::mojom::WindowShowState ClairBrowserWindow::GetWindowShowState() const {
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  return ui::mojom::WindowShowState::kNormal;
}

void ClairBrowserWindow::ShowChromeLabs() {
  LogUnavailable("Chrome Labs");
}

BrowserView* ClairBrowserWindow::AsBrowserView() {
  return nullptr;
}

void ClairBrowserWindow::DeleteBrowserWindow() {
  delete this;
}

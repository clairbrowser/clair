// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_NATIVE_LAYER_H_
#define CHROME_BROWSER_CLAIR_CLAIR_NATIVE_LAYER_H_

#if defined(__OBJC__)
@protocol ClairBrowser;
@protocol ClairWindow;
#endif

namespace clair {

// Loads ClairUI.framework from the app's Contents/Frameworks and starts it with
// Chromium's implementation of the ClairHost protocol (ClairHost.h). Call once,
// on the main thread, after the main menu is built. When the framework is
// missing, as in a bare engine, it logs that and returns, and Chromium runs
// with its own windows. When the framework is present but fails to load, it
// logs why, tells the user that Clair couldn't start its interface, and quits
// (replace-browser-window design D2).
void StartNativeLayer();

// Whether ClairUI is running, so normal browser windows are native.
bool IsNativeLayerRunning();

// app_controller_mac.mm's -confirmQuitIfNeeded hook (native-quit-confirmation
// D2): the same as MaybeConfirmQuit for Cmd+Q, which reaches Chromium as the
// IDC_EXIT command rather than through -terminate:. True when the dialog
// shows and the quit must stop.
bool MaybeConfirmKeyboardQuit();

// Whether Clair was relaunched while another app was active and should stay
// behind it. Holds until the user brings Clair forward, or for a minute after
// start-up, by which time the restored windows are showing.
bool ShouldStayInBackground();

#if defined(__OBJC__)
// Asks ClairUI for the window of a native browser window. Only valid while
// IsNativeLayerRunning().
id<ClairWindow> CreateClairWindow(id<ClairBrowser> browser);

// chrome_browser_application_mac.mm's -terminate: hook
// (native-quit-confirmation D2). When the user clicked Clair > Quit Clair
// (`sender` is that menu item) while warn-before-quitting is on, a native
// window is open and no download is in progress, shows ClairUI's quit dialog
// and returns true: the quit waits for the user's answer. Returns false
// otherwise, and the quit goes on. Other quits, such as the Dock's, logging
// out or -[ClairHost quitWithoutWarning], never ask.
bool MaybeConfirmQuit(id sender);
#endif

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_NATIVE_LAYER_H_

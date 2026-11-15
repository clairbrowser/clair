# Section 05: navigation and page-facing UI

## What this section is

The parts of the native interface that show the user something a web page influences, or turn what the user types into a navigation. `URLDisplay` formats the address; `CommandBarModel` and `clair_autocomplete` are the command bar and its suggestions; `SiteControlCenter` shows and changes a site's permissions; Peek opens a link in a preview over the current page (`clair_peeks`, `clair_peek_session`, the Peek views); `clair_downloads` reports downloads; `clair_pinned_link_throttle` turns a link clicked in a pinned tab into a peek; `ClairDialog`, `NoticePopup` and `StatusCapsule` present prompts and status.

Chromium's own versions of these surfaces carry years of anti-spoofing work. Clair redraws them natively, so each one has to earn that protection again. A browser whose address display or permission prompt can be made to lie is unsafe however sound the engine underneath is.

## Specs to judge against

`openspec/specs/command-bar`, `peek`, `site-control-center` and `dialogs`. For links in pinned tabs, `pinned-tabs` and `peek`, with decision D7 in the archived change `add-pinned-tabs-and-favorites`.

## Where to look in the engine tree

Start from the includes of the overlay files and from the patches. Expect to need `components/omnibox/browser/` and `chrome/browser/autocomplete/`, `components/url_formatter/`, `components/page_info/` and `components/permissions/`, `chrome/browser/download/`, `content/public/browser/navigation_throttle.h` and its registry, and whatever `peek-session.patch`, `pinned-link-peek.patch` and `first-run-page.patch` touch.

## What to establish

**What the address shows**
- From which Chromium value is the displayed address derived: the last committed URL, the visible URL, a pending one? During a slow navigation, a redirect, an interstitial or a failed load, can the display name one origin while the page shown belongs to another?
- How are these displayed: internationalised and look-alike hostnames, very long hosts and subdomains, userinfo (`user@host`), right-to-left characters, `data:`, `blob:`, `javascript:`, `view-source:` and `file:` URLs? Does Clair use Chromium's URL formatter and its elision rules or its own string handling?
- Is the security state of the connection shown anywhere, and can the page alter where or whether it appears?

**From text to navigation**
- Follow typed input to a navigation. How is it classified as a URL or a search, and can a crafted suggestion, pasted text or a URL from another app navigate somewhere the user did not see, including to `javascript:` or `chrome:` URLs?
- Which profile's history and suggestions does the command bar draw on, and can suggestions from one profile appear while a Space of another is showing?
- What is the lifetime of the autocomplete controller relative to the window and the profile?

**Permissions and prompts**
- Is the origin shown in the site control center and in each permission prompt the origin that is actually asking, including for iframes and after a navigation while the prompt is open?
- Can a page cause a prompt to appear under the pointer just before a click, or place content over or beside a native prompt so that it reads as browser UI? Chromium delays input on fresh prompts for this reason; does Clair?
- Which Chromium prompts have no native equivalent yet, and what does the user see when one is requested? Make the inventory complete: permission requests, JavaScript dialogs and the leave-page dialog, HTTP authentication, external-protocol and "open in another app" prompts, file choosers, the device choosers (USB, Bluetooth, HID, serial), the screen-share picker, download confirmations, and the notices for full screen, pointer lock and keyboard lock. For each: drawn by Clair, still drawn by Chromium, or dropped; and if dropped, is the request refused or silently granted?
- Which window and which tab does a prompt attach to when the page asking is not the one in front: a background tab, a tab of another Space, a page in another profile's hidden window, a peek, a pinned tab? Can a page the user cannot see get a prompt answered as though the visible page had asked?
- What does a prompt do with the keyboard? Look for a default button that Return or Space activates, focus taken from the page while the user is typing, and a prompt that can be re-raised in a loop until the user gives in.
- Page-controlled text inside a prompt (a dialog message, an authentication realm, a file or protocol name, an origin with a long or look-alike host): is it bounded, kept apart from the browser's own wording, and unable to push the origin or the buttons out of view?
- Clair shows very little browser chrome around the page. Can a page draw something that passes for Clair's own sidebar, command bar, peek or dialog, in a normal window or in full screen, and is there anything on screen a page cannot draw over that tells the user which is real?

**Peek**
- A peek is a second page shown inside the first one's window. Is it always obvious which origin the peek shows, and can the page underneath script, cover or frame it?
- Whose `WebContents` is it, how is it tagged in the session, and what happens to it on expand, on close, on a profile switch and on relaunch? What does `peek-session.patch` change in Chromium's session code and what breaks without it?

**Links in pinned tabs**
- `pinned-link-peek.patch` adds `ClairPinnedLinkThrottle` to every primary main frame navigation, and it turns a link to another site, clicked in a pinned tab or a favourite, into a peek. A page decides when and where it navigates. Which navigations does the throttle treat as a link click, and can a page use script, a redirect, a form submission or a renderer-initiated navigation to be routed into a peek, or to avoid one, when the user did nothing?
- How is "another site" decided, and from which URL: the one the renderer asked for or the one the browser validated? What happens for `javascript:`, `data:`, `blob:`, downloads and external protocols?
- When the throttle cancels a navigation and opens a peek instead, what carries over: the initiator origin, the referrer, the POST body, the opener, the user gesture? Does the new navigation pass the checks the cancelled one would have?
- The throttle runs for every navigation in the browser. What does it cost, and what does it hold on to, for the tabs it does nothing for?

**Downloads**
- Are Chromium's dangerous-download warnings and the per-profile download location honoured, or can a download complete without the checks Chromium's own UI would have shown?

**Quality**
- Where does page-controlled text (titles, URLs, permission strings, download names) reach an AppKit or SwiftUI view, and is it always treated as plain text of bounded length?

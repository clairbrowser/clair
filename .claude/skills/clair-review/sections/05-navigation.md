# Section 05: navigation and page-facing UI

## What this section is

The parts of the native interface that show the user something a web page influences, or turn what the user types into a navigation. `URLDisplay` formats the address; `CommandBarModel` and `clair_autocomplete` are the command bar and its suggestions; `SiteControlCenter` shows and changes a site's permissions; Peek opens a link in a preview over the current page (`clair_peeks`, `clair_peek_session`, the Peek views); `clair_downloads` reports downloads; `ClairDialog`, `NoticePopup` and `StatusCapsule` present prompts and status.

Chromium's own versions of these surfaces carry years of anti-spoofing work. Clair redraws them natively, so each one has to earn that protection again. A browser whose address display or permission prompt can be made to lie is unsafe however sound the engine underneath is.

## Specs to judge against

`openspec/specs/command-bar`, `peek`, `site-control-center` and `dialogs`.

## Where to look in the engine tree

Start from the includes of the four overlay files and from the three patches. Expect to need `components/omnibox/browser/` and `chrome/browser/autocomplete/`, `components/url_formatter/`, `components/page_info/` and `components/permissions/`, `chrome/browser/download/`, and whatever `peek-session.patch` and `first-run-page.patch` touch.

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
- Which Chromium prompts have no native equivalent yet, and what does the user see when one is requested?

**Peek**
- A peek is a second page shown inside the first one's window. Is it always obvious which origin the peek shows, and can the page underneath script, cover or frame it?
- Whose `WebContents` is it, how is it tagged in the session, and what happens to it on expand, on close, on a profile switch and on relaunch? What does `peek-session.patch` change in Chromium's session code and what breaks without it?

**Downloads**
- Are Chromium's dangerous-download warnings and the per-profile download location honoured, or can a download complete without the checks Chromium's own UI would have shown?

**Quality**
- Where does page-controlled text (titles, URLs, permission strings, download names) reach an AppKit or SwiftUI view, and is it always treated as plain text of bounded length?

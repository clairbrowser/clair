# Who attacks a browser shell

Every section that holds code reads this. The section briefs ask what is specific to each area; these are the questions that apply to any code Clair puts on top of Chromium.

Clair's overlay code and `ClairUI` run in the browser process, outside the sandbox and with the user's full rights. Chromium treats that process as the one that must never trust the others. Clair's code has to keep to the same rule.

## The attackers

- **Web content.** Any page, frame or worker. It chooses URLs, titles, favicons, the timing of navigations and of every request for a prompt.
- **A compromised renderer.** Assume an attacker already runs code inside a renderer, as every serious browser exploit does. It can send the browser process any message a renderer may send, with any values, in any order, and it lies about its own origin and URL. Whatever lets it act outside the sandbox is a sandbox escape, and that is the step Clair's code must not provide.
- **An extension.** Code the user installed, with the permissions the user granted and an interest in gaining more. It chooses its own name, icon and popup content.
- **A network attacker.** Controls what comes back from any request that is not authenticated end to end.

## Standing questions

- **Memory safety in the browser process is a sandbox boundary.** A use-after-free or an out-of-bounds read in overlay code that a renderer can trigger is an escape. For every object Clair holds across an asynchronous step (a `WebContents`, a `RenderFrameHost`, a `NavigationHandle`, a `Browser`, a profile), what guarantees it is still alive, given that the renderer decides when a frame goes away, a tab closes or a navigation is cancelled?
- **Whose word is it?** When Clair acts on a URL, an origin, a size, a title or a flag, did the value come from browser-side state (the last committed origin, the navigation the browser itself validated) or from something a renderer supplied? A security decision must use the first kind.
- **The contract boundary.** `ClairHost.h` hands Swift Objective-C objects that stand for Chromium objects (a tab, a browser, a download), identifiers that are resolved later, and completion blocks. What does such an object do when Swift uses it after the Chromium object is gone, what does a stale or made-up identifier resolve to, and can a block run after the thing it captured was destroyed?
- **Acting on a page's behalf.** When Clair opens, moves or re-routes a navigation that a page started, does the navigation keep the initiator, the restrictions and the checks it would have had in a normal tab? A page must not reach `chrome:`, `file:`, `javascript:` or another profile through a path Clair added.
- **New entry points.** Anything Clair exposes that a renderer or an extension can call (a Mojo interface, a WebUI handler, an extension API, an injected script) is attack surface: which origins can reach it, and what does it validate?
- **Text and images in native UI.** Whatever a page or an extension controls and Clair draws natively (titles, URLs, names, icons, prompt text) must be bounded, shown as plain text, and impossible to mistake for the browser's own words.

A finding under any of these needs the path: which attacker, through which call, reaches which line.

# Spec Delta

## REMOVED Requirements

### Requirement: No bookmarks in the interface
**Reason**: The Bookmarks menu and a bookmark dialog come back, with Bookmark This Page… on Shift+Cmd+B and Manage Bookmarks on Opt+Cmd+B, so the interface shows bookmarks again.
**Migration**: The `bookmarks` capability now owns everything about bookmarks in the interface. Its "Bookmarks UI Clair leaves out" requirement keeps what this one still ruled out: no bookmarks bar or star, no View › Always Show Bookmarks Bar, Cmd+D pinning the tab, and existing bookmarks kept. `chrome://bookmarks` is now Manage Bookmarks.

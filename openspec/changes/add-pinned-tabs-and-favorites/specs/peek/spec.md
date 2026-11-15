# Spec Delta

## ADDED Requirements

### Requirement: Links to other sites from pinned tabs and favorites
While the preference for links to other sites is on (`settings-window`), a link the user clicks in a pinned tab's or favorite's page that leads to another site than the page's SHALL open in a Peek of that tab instead of navigating it, as Shift+click does. A link to the same site SHALL navigate the tab. A site here is a scheme and host, as in Arc: another subdomain, `www.` included, is another site, and another port on the same host is the same site.

#### Scenario: Another site
- **WHEN** the favorite "Mail" shows `https://mail.example.com/` and the user clicks a link to `https://news.example.org/`
- **THEN** the link opens in a Peek over "Mail", which keeps its page

#### Scenario: Another subdomain
- **WHEN** the user clicks a link to `https://docs.example.com/` there instead
- **THEN** it opens in a Peek over "Mail" too

#### Scenario: The same site
- **WHEN** the user clicks a link to `https://mail.example.com/inbox/2` there instead
- **THEN** "Mail" navigates to it, and its row or tile shows it navigated away from its pinned URL

#### Scenario: A Today tab
- **WHEN** the user clicks a link to another site in a Today tab
- **THEN** the tab navigates, and no Peek opens

#### Scenario: Preference off
- **WHEN** the preference is off and the user clicks a link to another site in a pinned tab
- **THEN** the pinned tab navigates to it

#### Scenario: Links that open a new tab
- **WHEN** the user Cmd-clicks a link to another site in a pinned tab
- **THEN** it opens as a new tab, as from any page, and no Peek opens

#### Scenario: Pages that navigate themselves
- **WHEN** a pinned tab's page changes its location by script without the user clicking a link
- **THEN** the tab navigates, and no Peek opens

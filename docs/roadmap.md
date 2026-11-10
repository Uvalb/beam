# Roadmap

Feature ideas, roughly in order. Each must keep Beam a fast keyboard jump (see `product.md`). `todo.md` holds the near-term chores; this holds product direction. Nothing here is decided until it has a file in `decisions/`.

## In design: ranking
Branch `claude/ranking-design-876499`.
1. Tab groups rank below tabs (own tier). Today `.tab` and `.tabGroup` share precedence, so a group's exact match beats a tab's prefix match.
2. Closed saved tab groups: new `ItemKind.closedGroup`, read from the bookmarks-bar "Saved Tab Groups" buttons ("<name> group - Closed"), reopened with AXPress. Needs a visible bookmarks bar and English Chrome (see gotchas).
3. User-set order of result kinds in Settings (UserDefaults, `rank` takes the order as a parameter, "Restore defaults"). Affects only strong matches; fuzzy stays score-first.

## Planned
### Browser bookmarks
- Done for Chrome (2026-11-10, decision 0019). Other browsers' bookmarks fall under the next item.

### Other browsers
- Safari, Arc, Edge, Brave, Firefox for tabs and bookmarks. Chrome-only today is a provider detail, not a principle; the provider interface should allow more.
- Open question: which expose tabs without Apple Events permission prompts or AX scraping.

### System Settings panes
- Results for panes ("Wi-Fi", "Displays", "Privacy & Security"), opened via `x-apple.systempreferences:` URLs.
- Needs a static list per macOS version (pane IDs changed in 13). Check how fragile that is before committing.

## Ideas: the command-key actions
These add a second kind of result: not something that exists, but an action on what you typed. The shared design question is the trigger. Holding Cmd inside the input should show the action results in the list, so nothing is hidden behind an unseen shortcut.

### URLs (Cmd+Enter)
- Type `youtube`, press Cmd+Enter: open a new tab at youtube.com. Once Cmd is down, the matching results show in the list first.
- Auto-complete the domain: `.com` by default, and other TLDs according to sites the user has beamed to before (a small local history of typed hosts, kept in UserDefaults).
- Open question: history of typed hosts versus Chrome's own history. Reading Chrome's history file is richer but more invasive.

### Terminal (Cmd+T)
- Paste or type a path, press Cmd+T: open a new Terminal window there.
- Treat input as a path when it starts with `/` or `~/`. Autocomplete either as you type for those inputs, or only after Tab turns it on. Prefer the Tab option first (no surprise latency, no filesystem reads on ordinary queries).
- Open question: Terminal.app only, or the user's default terminal (iTerm, Ghostty)?

### Folder (Cmd+F)
- Same path detection and autocomplete as Terminal: opens a new Finder window at the folder.
- Cmd+F, Cmd+T and Cmd+Enter must not clash with existing shortcuts (check the search bar's key handling and the system-shortcut parsing).

## Not planned
- MCP client, inbound push CLI or URL scheme: Beam stays a fast keyboard jump, not an integration hub.

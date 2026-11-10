# Roadmap

Feature ideas, roughly in order. Each must keep Beam a fast keyboard jump (see `product.md`). `todo.md` holds the near-term chores; this holds product direction. Nothing here is decided until it has a file in `decisions/`.

## In design: ranking
Branch `claude/ranking-design-876499`.
1. Tab groups rank below tabs (own tier). Today `.tab` and `.tabGroup` share precedence, so a group's exact match beats a tab's prefix match.
2. Closed saved tab groups: new `ItemKind.closedGroup`, read from the bookmarks-bar "Saved Tab Groups" buttons ("<name> group - Closed"), reopened with AXPress. Needs a visible bookmarks bar and English Chrome (see gotchas).
3. User-set order of result kinds in Settings (UserDefaults, `rank` takes the order as a parameter, "Restore defaults"). Affects only strong matches; fuzzy stays score-first.

## Planned
### Browser bookmarks
- Match by name (and URL host), like Chrome tabs. Choosing one opens the URL, reusing an open tab with that URL if there is one.
- Chrome first: read `~/Library/Application Support/Google/Chrome/<Profile>/Bookmarks` (JSON). No accessibility scraping, independent of the bookmarks bar. Probably all profiles, labelled with the profile name.
- New `ItemKind.bookmark`, below apps by default, reorderable in Settings. Strong matches only, to avoid noise from hundreds of bookmarks.
- Not available in the sandbox variant.

### Other browsers
- Safari, Arc, Edge, Brave, Firefox for tabs and bookmarks. Chrome-only today is a provider detail, not a principle; the provider interface should allow more.
- Open question: which expose tabs without Apple Events permission prompts or AX scraping.

### System Settings panes
- Results for panes ("Wi-Fi", "Displays", "Privacy & Security"), opened via `x-apple.systempreferences:` URLs.
- Needs a static list per macOS version (pane IDs changed in 13). Check how fragile that is before committing.

## Built: the command-key actions
Hold ⌘ for actions on the typed text: ⌘T Terminal and ⌘F Finder at a path, ⌘↵ new Chrome tab at a host. Done, with the open questions settled, in decision 0020 (still to do: other terminals, host Tab completion).

## Not planned
- MCP client, inbound push CLI or URL scheme: Beam stays a fast keyboard jump, not an integration hub.

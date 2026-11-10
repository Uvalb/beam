# 0016: Result kind order, closed saved groups, order in Settings

Date: 2026-11-10.

Found groups in the vertical tab strip (see changelog 2026-11-09) made a group named "Beam" outrank a tab "Beam — type to jump…": `.tab` and `.tabGroup` shared a precedence and the group's exact match out-scored the tab's prefix match.

Decisions:
- Kinds have a strict order among strong matches: window, tab, tab group, closed saved group, app. A group never jumps above a tab. Considered "group wins only on exact name" (special case, hard to explain) and "groups below apps" (groups too hard to reach).
- Closed saved tab groups are a new kind (`.closedGroup`), read from the bookmarks bar's "Saved Tab Groups" toolbar (buttons titled "<name> group - Closed"). Choosing one presses the button (AXPress), then focuses the group. "Opened" ones are skipped (found as live groups). It ranks below open groups because reopening is heavier. Works only with the bookmarks bar visible and English Chrome.
- The order is user-settable in Settings (drag list, UserDefaults key `resultKindOrder`, "Restore Defaults"). `SearchIndex.rank` takes it as a parameter (default `ItemKind.defaultOrder`) so it stays testable. It only affects strong matches, as before: fuzzy matches stay score-first and URL-only matches stay after every kind, so a custom order can't bury a much better match.

Addendum (same day, after merging Claude sessions and Slack from main): sessions and Slack join the list, default order after apps (they are not open things, so they stay behind apps as before). Every kind has an on/off switch (`resultKindsDisabled`); a switched-off kind's provider is not run at all (closed groups and open groups share one Chrome scan, which still runs if either is on), so turning off what you don't use also saves work. Toggling or reordering posts `KindOrder.changed`, which makes `SearchIndex` reload at once. The Settings section sits last, after "Open at login".

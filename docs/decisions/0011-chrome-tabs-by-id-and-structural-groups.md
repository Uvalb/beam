# 0011: Chrome tabs by stable id, tab groups by structure

Date: 2026-11-09.

Tabs were targeted by window id + tab index from the last scan, so a tab closed, moved or dragged to another window since then opened the wrong tab, and a vanished window just activated Chrome. Tab groups were recognised by English text (`group <name> - N Tabs`, `Part of group <name>`), so they were invisible in any other Chrome language, and the strip finder missed Chrome's vertical tab layout entirely.

Decision:
- Target tabs by Chrome's AppleScript `id of tab`, searching every window. Tested: it survives closing other tabs, drag reordering and tearing a tab into another window. If the id is gone (Chrome restarted), fall back to an exact URL + title match; if that fails too, do nothing rather than focus a different tab.
- Find group headers and members by the tab strip's structure (an empty AXTabGroup with DOM class `TabGroupHeader…`, followed by tab buttons whose titles contain the group name, capped at the header's count). Only the group name has no language-neutral source: it is parsed from the localized header title (English pattern, else a quoted name, else "<group word> <name>" with the group word learned from two or more headers and remembered).

Considered: matching tabs by URL only (duplicates are common), and a table of Chrome's localized strings per language (dozens of languages, changes with Chrome releases).

Cost: one extra `id` per tab in the scan, and focus walks the windows' id lists (one Apple event per window). With a single group in a language without quoted names, the name keeps Chrome's word for "group" ("הקבוצה עבודה") until a second group teaches it.

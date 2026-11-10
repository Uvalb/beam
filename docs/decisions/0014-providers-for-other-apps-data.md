# 0014: Providers that read other apps' own data

Date: 2026-11-10.

Context: contributors proposed jumping to Claude Code sessions (PR 4) and Slack conversations (PR 5). Neither app has a public, local way to list them, so both providers read the app's own undocumented store: Claude desktop's per-session JSON files, and Slack's IndexedDB cache. Both open the result with the app's URL scheme.

Decision: accept them. "Focused scope" still holds, since each is a named thing you jump to with the keyboard, not a search of content. The rules for this kind of provider:
- Read only, local only, no permissions where possible; never show content beyond names (no messages, no transcripts).
- Fail closed: an unexpected format yields no results, never a crash or a prompt.
- Each lives in its own file (`ClaudeSessions.swift`, `Slack.swift`), named after the app, so the undocumented-format code is easy to find and drop. Built-in sources (apps, windows, Chrome) stay where they are.
- Prefer the app's own fields over guessing from paths, but keep the guess as a fallback when the app leaves the fields empty.
- Avoid re-decoding unchanged data on every panel open (cache by modification date).

Cost: an app update can silently break a provider. Detecting that and letting users report it is tracked separately.

Considered: official APIs (e.g. a Slack app with an OAuth token). Rejected for now: network access, a stored token and admin approval, against "everything stays local".

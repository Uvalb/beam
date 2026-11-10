# 0012: Slack results come from Slack desktop's local cache

**Status:** accepted, 2026-11-09

## Context
We wanted Slack channels, people and group DMs in Beam (not message text). Three sources were possible:
- Slack's Web API with a user token: documented and stable, but it needs network access and a stored token, against the "everything stays local" principle.
- Slack's sidebar through the Accessibility API: small, but finds only what's in the sidebar.
- Slack desktop's own IndexedDB cache: local and complete, but an undocumented format.

## Decision
Read the cache. Slack persists its client state as one large IndexedDB value, which Chromium writes as a standalone blob file, so Beam decodes that file (Snappy, Blink envelope, V8 serialization) and never touches LevelDB. Only channels you're in, people and group DMs are used; messages are decoded with the rest but never used or shown.

Conversations you're in rank first: a base boost puts anyone you've talked to above strangers, and Slack's own `channelsPriority` score or the last message's age (over 90 days) adds to it, all within a score boost capped below the gap between match tiers, so a better match type still wins ("Alex" exact beats a recent "Dana Alex").

People's photos come from the same place Slack shows them from: its Chromium HTTP cache. Nothing is downloaded, so a photo Slack never displayed falls back to the Slack icon.

## Consequences
- A Slack or Chromium update can change the format. The decoder fails closed (no Slack results), never crashes.
- Only the direct-download Slack is read; the Mac App Store build keeps its cache in its container and isn't supported yet.
- A small workspace whose state stays under Chromium's blob threshold would be stored inline in LevelDB and not found.

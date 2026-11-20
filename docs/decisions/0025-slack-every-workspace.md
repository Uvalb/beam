# 0025: Read every Slack workspace's blob, newest per workspace

Date: 2026-11-20

## Context
Decision 0012 assumed Slack persists "one large IndexedDB value". With two workspaces signed in, Slack keeps one value per workspace (`persist:slack-client-<team>-<user>`), each its own blob file. Beam stopped at the newest blob that decoded, so it listed one workspace only. Slack rewrites a workspace's blob when its view unloads, which happens every time you switch away from a secondary workspace, so the secondary one was nearly always the newest and the main workspace never showed. Seen on Slack desktop with a 175-entry main workspace and a 7-entry second one.

## Decision
Decode every blob, group by the state's own team (`selfTeamIds.teamId`) and keep the newest blob per team. Entries of all teams are listed together. A channel's subtitle names its workspace. When more than one workspace is listed, people with a job title and group DMs add it too, so the same person in two workspaces is two rows that say which is which; with one workspace they stay as before. A load that had to skip an unreadable blob isn't saved as the App Store build's last good read, since a workspace may be missing from it. Each decoded blob is cached by path and modification date, as the single one was.

## Consequences
- Every blob that is Slack state is decoded once per change, not just the newest. Blobs that aren't Slack's were already remembered as misses.
- A workspace Slack hasn't persisted yet (its view never unloaded since the blob was cleared) still doesn't show until Slack writes it. Beam can't fix that from the cache.
- The health report's "Parsed" is now the number of workspaces read.
- Not checked: what Slack does with a workspace's blob when you sign out of it. If the blob stays, that workspace keeps being listed (with links Slack can't open) until Chromium removes the file. The old "newest blob wins" had the same risk the other way round, since signing out writes that workspace's blob last.

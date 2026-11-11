# 0022: Read the App Store Slack's container lazily, with a saved copy

Date: 2026-11-11

## Context
Reading the Mac App Store Slack's container (`~/Library/Containers/com.tinyspeck.slackmacgap/`) triggers macOS's "access data from other apps" prompt. Tested 2026-11-11: updating from 0.1.3 to 0.1.4 through Sparkle, both notarized Developer ID builds with the same designated requirement, asked again. So a stable signature doesn't keep the grant, and every user was asked at launch after every update, whether or not they search Slack.

## Decision
- The container is not read until a scoped query ("@" or "#") is typed since launch. After that, every panel open reads it as before.
- Each good read is saved to `~/Library/Application Support/Beam/slack-entries.json`. Before the first scoped query, Slack results come from that copy, with Slack's icon instead of photos, because the photos are in the container too.
- The direct-download Slack (no prompt) is read live as before and not saved.

## Consequences
The prompt now comes when you first type "@" after an update, which is when it makes sense. Results from the saved copy can be stale until that first read. A Slack health problem is noticed only once you use Slack search.

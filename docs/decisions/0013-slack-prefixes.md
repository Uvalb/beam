# 0013: Slack results show only behind `@` and `#`

**Status:** accepted, 2026-11-10

## Context
Slack adds hundreds of items (people, channels, group DMs). A short query mixes them with apps, and channel results are shown as `#name`, so typing `#name` found nothing. Product scope says no modes or plugins.

## Decision
Slack results show only behind Slack's own two prefixes. A leading `@` searches only people and group DMs, `#` only channels; the rest of the query ranks as usual. A bare `@` or `#` lists the most recently used ones in that scope (people you've never talked to are left out). Queries without a prefix leave Slack out entirely.

We first tried prefixes as optional narrowing, with Slack also mixed into plain queries. Hundreds of people and channels then competed with apps ("ma" put a recently messaged person above Mail; a recent `#figma` above the Figma app), and launching apps is Beam's core job.

## Consequences
- It matches what Slack users already type. Someone who doesn't know the prefixes won't see Slack results; the README says so.
- Slack's recency boost can't outrank apps, because the two never share a result list.
- A window or tab whose title starts with `@` or `#` can't be found by typing that character first.
- No other prefixes: a new one needs a new decision.

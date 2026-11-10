# Product

**Beam** is a fast, focused replacement for Spotlight: press a hotkey, type a few letters, and jump to an app, an open window, a Chrome tab, a Chrome tab group, a Claude Code session or a Slack channel, person or group DM.

## Who it's for

Mac users who live in many windows and tabs and want to switch by name instead of hunting through the Dock, Mission Control or tab strips. It started as the author's own tool.

## Principles

- **Speed above everything.** Results update on every keystroke. Opening the panel must feel instant.
- **Focused scope.** Apps, windows, tabs, Claude Code sessions and Slack conversations (never message text) only. Slack results show only behind Slack's own `@` (people) and `#` (channels) prefixes, so plain searches stay apps, windows and tabs ([0013](decisions/0013-slack-prefixes.md)). No file search, calculator, web search or plugins.
- **Open things rank first.** Open windows and tabs rank above apps that aren't running. Claude sessions and Slack conversations are stored, not open, so they rank with apps.
- **Respectful.** No telemetry; everything stays local except two kinds of request: the optional update check (Sparkle, asks first on the 2nd launch, no system profile sent) and the one-time license check (only if you enter a key). Reminders to support Beam are gentle and rare (see [monetization](decisions/0002-supporter-pricing-model.md)).

## Non-goals

- Replacing Alfred or Raycast (no extension ecosystem).
- Browsers other than Chrome, for now.
- Locking features behind a payment.

## Distribution and business

- Open source under GPL-3.0 from launch, with the Beam name and icon reserved ([0006](decisions/0006-open-source-gpl.md)). Distributed directly as a signed and notarized build ([0001](decisions/0001-direct-distribution-over-app-store.md)).
- Donation-style supporter model with a suggested $1/month ([0002](decisions/0002-supporter-pricing-model.md)), paid through a merchant of record (Lemon Squeezy).

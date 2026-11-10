# 0002: Supporter pricing model ("we suggest $1/month")

**Date:** 2026-10-20 · **Status:** accepted

## Context
Beam is useful enough to ask for money, but the author doesn't want to lock features. 

## Decision
Follow the nonprofit donation pattern: suggest a value, and let people choose the amount and whether to give once or every year.
- **Yearly (default, pre-selected):** $12/year, presented as "$1/month, billed yearly". Also $24 and $60. Billed yearly because the fixed fee per charge would take about half of a $1 monthly charge.
- **One-time:** pay what you want, pre-filled at $12, minimum $5 (below that, fees take too much), no maximum.
- **Any payment makes someone a supporter for good**, including yearly supporters who cancel. All supporters are treated the same, with no perk tiers.
- **$0 is not a supporter.** Non-supporters see gentle usage-milestone reminders, such as "You've beamed 1,423 times", spaced out over time and never interrupting a search.
- Wording: "suggested", never "price". The reminders say "keep Beam alive", not "remove nags".

## Alternatives considered
- A required subscription: rejected, because Mac users dislike it for a local tool with no server costs.
- Trial then purchase, or a Pro tier: rejected for now.
- Making one-time support last a set period: rejected. Supporter for good is simpler and kinder, and the recurring option is there for people who want to give regularly.

## Consequences
- The license check only confirms that a key is valid, not that a subscription is active, so it needs no regular rechecks.
- Revenue depends on goodwill, so the reminders' tone matters.

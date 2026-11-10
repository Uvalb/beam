# 0006: Open source under GPL-3.0, from launch

**Date:** 2026-10-29 · **Status:** accepted

## Context
[product.md](../product.md) said closed source. The marketing research showed that this costs discovery. Much of the free exposure for Mac utilities comes through GitHub: search, trending, the awesome lists, and r/macapps' trust path for developers with a public GitHub project. Homebrew also counts stars toward notability, but discounts stars on repos that only host binaries.

Beam asks for Accessibility and Automation, which let it see every window and tab, so "no telemetry" matters more when people can check it. In 2024 Bartender's quiet sale and the analytics its new owner added pushed users to the open source Ice. When Ice stalled, users moved to Thaw, a GPL fork.

## Decision
- Publish the source under **GPL-3.0** when Beam launches publicly, not later. The launch week is when stars and trending happen.
- **Reserve the "Beam" name and icon.** They aren't covered by the license, so forks must rename. Before relying on this, check whether "Beam" can be registered as a trademark.
- **Issues are open. PRs need an issue discussion first,** and outside contributions stay small, so the author remains the only copyright holder. That keeps relicensing and commercial licensing possible. Revisit with a CLA if large contributions become worth taking.
- Nothing else changes. The supporter model ([0002](0002-supporter-pricing-model.md)), Lemon Squeezy (decision 0003, now kept with the private business docs) and signed direct downloads ([0001](0001-direct-distribution-over-app-store.md)) stay as they are.

## Alternatives considered
- **Stay closed, with a public repo for issues and releases only.** Gets a place for bug reports, but little trust and almost no Homebrew credit.
- **Source-available license (PolyForm Shield or Noncommercial).** Blocks commercial reuse, but Beam loses the "open source" label and most of the discovery benefit.
- **Delayed open source (BSL or FSL).** Adds complexity to protect code with little to protect.
- **Open core.** Conflicts with the rule against locking features.
- **MIT.** Lets paid competitors (Macscope, TabTab) take the ranking code into closed apps. GPL prevents that.

## Consequences
- Anyone may build Beam and redistribute it without the reminders, under another name. Accepted: those people wouldn't have paid anyway.
- **App Store clones are unlikely.** Window search fails in the sandbox ([0001](0001-direct-distribution-over-app-store.md)).
- Polar.sh and GitHub Sponsors become real options again. Lemon Squeezy stays primary.
- Published code can't be withdrawn. The repo can be archived at any time.
- There's a public issue inbox to triage. Templates, labels and a pinned FAQ keep it small.
- Steps: see "Going open source" in [todo.md](../todo.md).

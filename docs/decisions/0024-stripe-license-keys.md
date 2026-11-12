# 0024: Stripe keys from beamlauncher.app, re-checked monthly

Date: 2026-11-12

## Context
Supporter payments move from Lemon Squeezy to Stripe Managed Payments on beamlauncher.app. Stripe doesn't issue license keys, so the website mints its own (`BEAM-XXXXX-XXXXX-XXXXX-XXXXX`) and answers `POST /api/validate`. Lemon Squeezy keys were checked once and never again, so a refund never revoked one.

## Decision
- `BEAM-` keys are checked with `beamlauncher.app/api/validate`; anything else still goes to Lemon Squeezy, so existing supporters keep working.
- A `BEAM-` key is stored whole in UserDefaults and re-checked at launch every 30 days. Only a definite "invalid" (refund or chargeback) removes supporter status; being offline or an odd answer changes nothing.
- "Receipts and billing" opens link.com, where Stripe Managed Payments orders and cancellations live.

## Consequences
Beam's license check is no longer strictly one-time: about one request a month for `BEAM-` key holders (SECURITY.md and product.md say so). The key is only a supporter flag, so storing it unencrypted is acceptable. Lemon Squeezy support can be dropped in a later decision once no live keys remain.

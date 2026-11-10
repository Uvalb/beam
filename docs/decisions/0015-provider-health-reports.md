# 0015: Noticing and reporting a broken provider

Date: 2026-11-10. Follows 0014, whose cost was "an app update can silently break a provider".

Decision: providers that read another app's undocumented data (Claude Code sessions, Slack) report how each load went to `ProviderHealth`:
- **ok** (something parsed), **noData** (nothing to read: the app is unused, signed out, or its store is missing) or **broken(kind)**: files exist but none could be understood. `kind` is a closed list (`decode-failed`, `missing-field`, `layout-changed`, `snappy`, `envelope`, `v8`, `missing-key`), so a report can never carry text from the other app's data. Not installed stays silent too. A partial failure (some files fine) counts as ok.
- **Gentle and rare:** a failure is confirmed only after 3 loads over at least 24 hours on the same version of the other app. An update of that app restarts the clock. Once confirmed, one result row ("Slack results stopped working", red warning icon) appears at the top when the query matches the provider's name ("slack", "claude"), never otherwise; no popups or badges. Settings also lists confirmed failures with a Report button.
- **Reports are the user's to send:** the sheet shows the exact text first: Beam version, build and commit, macOS version, provider, kind, the other app's version, files seen and parsed, and the date it broke. Then the user picks a prefilled GitHub issue from the `provider_broken.yml` template (which applies the `provider-broken` label for anyone; a `labels=` link parameter only works for triagers), an email to support@beamlauncher.app, or Copy. Email shares their address, which lets the maintainer follow up; that's their choice. Beam itself sends nothing.
- "Don't show this again" dismisses the row for that version of the other app only.

Known false positive: Slack's IndexedDB holds other blobs, so a signed-out Slack with leftover blobs could read as `missing-key`. The 24-hour wait and the plain wording ("probably after an update") keep this mild.

Considered: automatic reporting (against "no telemetry"); a shared protocol every provider implements (only two providers need it; built-in sources fail visibly already, e.g. the Accessibility hint).

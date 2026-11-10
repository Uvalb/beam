# 0008: Choose and pay on the website, not in the app

**Date:** 2026-11-04 · **Status:** accepted

## Context
A first version put the amount picker (yearly $12/$24/$60 or one-time) inside the app. People who open it and leave without paying would be invisible: measuring that funnel would need telemetry, and Beam promises none.

## Decision
Every "Support Beam" entry point opens `https://beamlauncher.app/?from=app#support`. The website, which already has its own funnel, shows the amounts and the Lemon Squeezy checkout. The app only takes the license key: "Enter License Key…", or a `beam://license?key=…` link from the thank-you page, checked once with Lemon Squeezy's `validate` endpoint.

## Consequences
- One less window and one less click; one place to change amounts and checkout URLs (the website).
- Needs the `beam://` scheme in Info.plist, and the website must skip the download for `from=app` and link back to the app after checkout.

# 0001: Distribute directly, not through the Mac App Store

**Date:** 2026-10-21 · **Status:** accepted

## Context
The Mac App Store would handle payments and tax and help people find Beam, but it requires the App Sandbox. A test build (`make sandbox`) checked each feature in the sandbox.

## Findings
- Chrome tabs through AppleScript work, using the temporary exception entitlement for Chrome only. App Review might still reject that entitlement.
- Launch at login works.
- **Window search doesn't work.** Even with Accessibility granted and a Developer ID signature, every app refuses to list its windows to the sandboxed Beam. Window search is a core feature.
- The Accessibility prompt is blocked in the sandbox, and `~/Applications` and Chrome favicons need a fix for the home folder.

An earlier, superseded plan was to keep AppleScript in a single build and only consider a Chrome Accessibility API or extension approach if Apple rejected the entitlement. Window search failing makes that moot.

## Decision
Sell and distribute Beam directly: a Developer ID signed and notarized build, through a merchant of record (decision 0003, kept with the private business docs).

## Consequences
- Needs signing and notarization, an update mechanism and a licensing check.
- No App Store visibility; users come from the website and word of mouth.
- Revisit only if Apple changes how sandboxed apps can use the Accessibility API.

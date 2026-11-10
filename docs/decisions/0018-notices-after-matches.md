# 0018: Health notices rank after real matches; prefixes only with Slack

Date: 2026-11-10. Amends 0013, 0015 and 0017.

**Notices.** 0015 put a "stopped working" row first whenever it matched. Its keys are the app's name, so "cla" + Return opened the report instead of Claude, on every launch until dismissed. Notices now rank after the real matches; they're still listed for the app's name. The "needs access" row (0017) had no dismissal at all; its alert now offers "Don't show this in results again". Settings keeps showing both, so the fix stays findable.

**Prefixes.** 0013 made `@` and `#` always Slack's. When Slack isn't loaded (switched off, not installed), they're now ordinary characters, so "#1234" finds a tab or window titled with an issue number.

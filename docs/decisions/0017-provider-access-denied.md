# 0017: A denied macOS data permission is shown at once, not as a failure

When the App Store Slack's container is unreadable because the user denied macOS's "access data from other apps" prompt, the provider reports `noAccess` (a read failing with EPERM/EACCES or Cocoa's no-permission error), separate from `noData` and `broken`.

- It is shown on the first load, without 0015's 3 loads over 24 h: it isn't flaky, and macOS won't ask again, so waiting helps no one.
- It is never offered as a report: nothing in Beam is broken.
- The fix offered is Full Disk Access, because it covers other apps' containers and has a System Settings pane Beam can open. macOS gives no way for an app to ask for the App Data permission again.
- A denial clears any broken state recorded before it was detected.

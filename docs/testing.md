# Testing

Run `make test` (`swift test`) for the pure logic, then check by hand in the running app for everything that touches the OS.

## Automated tests
`Tests/BeamTests` uses Swift Testing (`@Test`, `#expect`) and imports the `BeamCore` library with `@testable`. They run headless in about a second and need no permissions. They cover:
- `Matcher`: the score tiers, all words in any order (each starting a different word, 2+ words only, below an in-order match), shorter targets winning ties, and fuzzy runs needing word boundaries.
- `SearchIndex.rank`: windows above tabs above apps, an app above a tab that matched only on its URL, an app above a Claude session, the URL tiebreak, strong matches above fuzzy ones, the limit, and unread-badge stripping.
- `ClaudeSessionProvider`: parsing a session record (title, folder, worktree, archived skipped, "No folder"), and `sessions(in:)` on a temp store (non-session JSON skipped, most recently used first).
- `SlackCache` / `SlackProvider`: Snappy literal and overlapping copies, V8 objects, strings, ints, sparse arrays and back-references, the Snappy wrapper, rejecting unknown tags; channels you're in (archived and non-member skipped), a person opening their DM or profile, skipping you, bots and deactivated users, group DM titles, and recency from Slack's priority or the last message. `SearchIndex.rank`: a boost reorders within a tier only. `SearchScope`: parsing, Slack hidden from plain queries, `@`/`#` narrowing, a bare prefix listing recent items and skipping strangers. `SlackAvatars`: cache file name from the key, the body between key and EOF record, rejecting another key or a truncated entry.
- `ProviderHealth`: ok/noData clear the state, confirming only after 3 loads and 24 h, an app update restarting the clock, dismissal per version, the exact report text and URLs, and how Claude files and Slack blobs are classified. By hand: `defaults write com.beam.launcher BeamSimulateBrokenProvider slack` (or `claude-sessions`), open Beam once and type "slack": the notice row appears and Report shows only versions and a kind. Undo with `defaults delete com.beam.launcher BeamSimulateBrokenProvider` plus `health.slack` and `health.slack.dismissedVersion`.
- `Licensing`: `beam://license` links, parsing the license API response (valid, invalid, test-mode, other store) and `Support.markSupporter`.
- `FixesTests`: keeping the selected result across background refreshes (`SearchIndex.keptRow`), Chrome tab-group header parsing and membership from real English, German and Hebrew Chrome strings, search normalization (diacritics, Hebrew points, full-width), the FSEvents path filter and AppleScript quoting, plus a coarse ranking speed guard.
- Chrome parsing: tab rows from the AppleScript output, `urlKey`, stripping " - Part of group …" from window titles, and tab-group header names.
- `LicenseCheck.run` against a stubbed `URLProtocol` (no network): the request, a 404 that still parses, offline, and an unparseable body.
- `SystemShortcut.binding(from:)`, and the panel's arrow-key wrap (`SearchPanel.wrap`).
- `PathInput` / `URLInput`: path detection, pasted-path cleanup, folder completion on a temp directory, host candidates (`.com`, history first, rejects non-hosts) and schemes. By hand (the OS parts): hold ⌘ after typing `~/Doc` and `youtube`; ⌘T, ⌘F, ⌘↵; Tab on `~/Doc` completes, more Tabs cycle.
- `Support`: milestones, the pill window, dismissing it and supporters. `Support.d` is pointed at a throwaway UserDefaults suite, so the suite runs serialized.

CI (`.github/workflows/test.yml`) runs `swift build` and `swift test` on a macOS runner for PRs and pushes to main. It can't cover permissions, AppleScript to Chrome, the hotkey or the panel; those stay on the checklist below.

New pure logic should get a test. Keep OS calls out of the function you test (see `SearchIndex.rank` next to `search`).

## Normal loop
1. `make run`, or `make install` to test the /Applications copy (needed for launch-at-login defaults).
2. Quit every other running Beam first, including builds from other worktrees. Run `pgrep -fl MacOS/Beam` to check. A second copy grabs the hotkey and causes confusing results.

## Permissions
- Window search needs **Accessibility** (Privacy & Security > Accessibility). Chrome tabs need **Automation** for Chrome, which macOS asks for on first use.
- The Makefile pins the signing requirement to the bundle ID, so the Accessibility grant survives rebuilds. If windows still stop appearing (for example a grant from an older build), run `tccutil reset Accessibility com.beam.launcher`, re-add the app, and relaunch.

## Checklist after a change
- [ ] The hotkey opens the panel on the screen with the mouse; Esc and clicking away close it.
- [ ] Apps are found, including ones in `~/Applications`. A new app (`mkdir /Applications/X.app`) shows up a few seconds later without reopening; removing it drops it.
- [ ] A background refresh doesn't move the selection: type, arrow down, wait 3 s, Return opens the row you picked.
- [ ] Windows of other apps are found and focusing one works.
- [ ] Chrome tabs show with favicons; Return switches to the right tab, also after closing, reordering or dragging other tabs to another window while the panel is open. Return on a tab closed meanwhile does nothing.
- [ ] Chrome tab groups are found, with horizontal and vertical tabs. For other languages, start a throwaway Chrome: `open -n -a "Google Chrome" --args --user-data-dir=/tmp/chrome-de --no-first-run -AppleLanguages '(de)'`.
- [ ] With Automation for Chrome denied (`tccutil reset AppleEvents com.beam.launcher`, then Don't Allow), "tabs" shows the Automation hint, which opens that pane.
- [ ] Claude Code sessions show with the Claude icon and badge; Return opens the right session in Claude.
- [ ] Slack channels, people and group DMs show with the Slack icon and badge; Return opens the channel, the DM (or the profile, for someone you've never messaged) in Slack. People show their photo. Plain `tal` shows no Slack results; `@tal` shows only people, `#tal` only channels, `@` alone your recent people.
- [ ] "Support Beam ♥" (menu bar, Settings, ⌘D in the panel) opens beamlauncher.app at the support section. "Enter License Key…": a made-up key shows the "wasn't recognised" message; with Wi-Fi off, the offline message; a real test-mode key shows the thank-you and the reminders stop. `open 'beam://license?key=…'` fills in and checks the key. To retest, `defaults delete com.beam.launcher supportIsSupporter`.
- [ ] Settings: changing the hotkey works and the launch-at-login toggle sticks.

## Debugging
- Read logs with `/usr/bin/log show --last 5m --predicate 'process == "Beam"'`. Use the full path, because zsh has its own `log` command.
- For the sandbox build, output from `NSLog` didn't show up reliably; writing debug lines to a file in the container worked.

## Verifying a release build
One-time, in your own terminal (enter the credentials yourself): `xcrun notarytool store-credentials beam-notary --apple-id <apple id> --team-id P9GCM9K6AH`.
Then `make release` (or `SKIP_NOTARIZE=1 make release` to check signing only). It ends with `stapler validate` and `spctl -a -vv` on the app and dmg. Then mount `build/Beam.dmg`, copy Beam.app to a temp folder, and launch it: Gatekeeper must not warn. Re-grant Accessibility, then check window search (including other Spaces), Chrome tabs and tab groups under the hardened runtime.

## Debugging Chrome tab groups
`defaults write com.beam.launcher BeamDumpChromeTabStrip -bool true`, open Beam's panel once, then read `~/Library/Logs/Beam/chrome-tabstrip.txt`: Chrome's UI tree (no web content) with Beam's `[HEADER]`/`[TAB]` marks, parsed headers, and the groups and member counts Beam found. It holds tab titles, so don't paste it publicly. Turn it off with `defaults delete com.beam.launcher BeamDumpChromeTabStrip`.

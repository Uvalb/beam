# Changelog

Newest first. One line per merged change.

- 2026-11-10: Release 0.1.4 (build 5): command-key actions (⌘T terminal, ⌘F Finder, ⌘↵ Chrome tab) and a terminal choice in Settings.
- 2026-11-10: ⌘T opens your chosen terminal (Terminal, iTerm2, Ghostty, Warp, Kitty, Alacritty or WezTerm), picked in Settings when more than one is installed (decision 0021). ⌘ held: arrows move the selection, and a hint in the bar says what ⌘ does.
- 2026-11-10: Command-key actions: hold ⌘ in the panel for actions on the typed text; ⌘T opens Terminal and ⌘F Finder at a typed path (Tab completes folders), ⌘↵ opens a new Chrome tab at the typed host (`.com` default plus a small history of hosts you've opened) (decision 0020).
- 2026-11-10: Release 0.1.3 (build 4), the first from the public repo.
- 2026-11-10: GitHub Sponsor button (`.github/FUNDING.yml`) links to the website's support section, so supporters still get a license key.
- 2026-11-10: Published from a fresh `Uvalb/beam` with one squashed commit; the old repo is now private `Uvalb/beam-history`. GitHub settings, labels and a pinned FAQ (#1) set up.
- 2026-11-10: Fix: picking a Chrome tab group (open or collapsed) did nothing; the window is now brought forward again after the panel closes.
- 2026-11-10: `BeamDumpChromeTabStrip` defaults switch writes Chrome's tab strip and what Beam made of it to ~/Library/Logs/Beam (docs/testing.md).
- 2026-11-10: Review fixes: a health notice now ranks after real matches (Return on "cla" opens Claude, not the report); the Slack "needs access" row can be hidden from results ("Don't show this in results again"; Settings still shows it); `@`/`#` are plain characters when Slack isn't loaded; Claude's store with only empty folders or `.DS_Store` is no longer "broken"; a Slack blob that fails to read mid-rewrite is retried, not cached as a miss; reordering kinds no longer reloads every provider; Chrome windows' tab strips are walked once per load, not twice; a stored Chrome "group" word no current header uses is forgotten (decision 0018).
- 2026-11-10: Slack from the Mac App Store: if you denied macOS's "access data from other apps" prompt, Beam now shows "Slack results need access" (in results and in Settings) with a way into System Settings › Full Disk Access, instead of silently showing nothing and later calling Slack broken (decision 0017).
- 2026-11-10: Settings: "Show up to N results" (3–30, default 9); the list never grows past the screen and scrolls instead.
- 2026-11-10: Tab groups now rank below tabs; closed saved tab groups (bookmarks bar) are results that reopen the group; Settings has a "Results" list (last section) to reorder kinds (apps, windows, tabs, groups, closed groups, Claude sessions, Slack) and switch each on or off, off meaning not loaded (0016). Ranking tests for all three.
- 2026-11-10: Slack from the Mac App Store: `SlackPaths` falls back to its container when there's no direct-download folder (macOS asks once for access to other apps' data). The badge column sizes to the widest badge, so "Claude Session" isn't cut off.

- 2026-11-09: Slack: `SlackProvider` lists channels you're in, people and group DMs from Slack desktop's IndexedDB cache (decoded by `SlackCache`; messages never used or shown) and opens them through `slack://` links; new `Slack` badge and `SlackTests`. Decision 0012. Recently used conversations and people rank first (`SearchItem.boost`). People show their photo from Slack's HTTP cache (`SlackAvatars`). Anyone you've talked to ranks above strangers (a base boost; recency over 90 days on top). Slack results show only behind `@` (people) and `#` (channels); alone, they list recent ones (decision 0013). A query of 2+ words matches them in any order (`#mobile-core` finds `#core-mobile-team-devs`).

- 2026-11-09: Claude Code sessions: `ClaudeSessionProvider` reads Claude desktop's per-session JSON files (unarchived only) and opens one through the `claude://code/continue?session=` link; new `Claude Session` badge and `ClaudeSessionTests`. Moved to `ClaudeSessions.swift`, parsed files cached by modification date, worktree names from Claude's own fields, session id percent-encoded in the link (decision 0014).

- 2026-11-09: Contributor-reported fixes: a background refresh no longer moves the selection under Return; Chrome tabs are focused by their stable id (never a different tab, 0011); a denied Chrome Automation permission shows a hint row; apps installed or removed while Beam runs are picked up (FSEvents, off the hotkey path); tab groups work in any Chrome language and with vertical tabs. Non-English pass: search ignores diacritics, Hebrew points and full-width forms; app titles use the localized Finder name (`CFBundleAllowMixedLocalizations`).

- 2026-11-10: Added `docs/roadmap.md` (ranking design, bookmarks, other browsers, System Settings panes, Cmd+Enter URLs, Cmd+T / Cmd+F paths).
- 2026-11-09: Tab groups are found in Chrome's vertical tab strip too (headers and tabs sit a few levels deeper there); group pairing is now `pairGroups`, with tests.
- 2026-11-09: Tests 25 → 44: Chrome tab-row, URL-key, group-title and group-header parsing; LicenseCheck via a stubbed URLProtocol; licensing edge cases; system-shortcut parsing; arrow-key wrap. Fix: a query now scores as a word prefix if any occurrence starts a word, not just the first ("code" in "xcode code").
- 2026-11-06: Search bar and results glass now share an NSGlassEffectContainerView on macOS 26, so they adapt light/dark together instead of splitting.

- 2026-11-08: README lists requirements: macOS 13+, Xcode 15+ or its Command Line Tools to build, Xcode 16+ for `make test`, and the KeyboardShortcuts and Sparkle packages.
- 2026-11-05: 0.1.2 (build 3): restores the KeyboardShortcuts resource bundle that 0.1.1 dropped (Settings crashed on open); release.sh now checks for it.

- 2026-11-05: Released 0.1.1 (build 2), the first update shipped through the Sparkle feed.

- 2026-11-05: Pre-launch P3 fixes: GPL-3.0-or-later stated in README and SPDX headers; CI has read-only permissions and SHA-pinned actions; no crash without a screen; guarded AX casts; collapsed-group click only when the header is on top; favicons decoded only as small bitmaps; `make app` copes with no resource bundles; SECURITY.md notes where the supporter email is stored.
- 2026-11-05: Pre-launch review fixes: all AppleScript runs on one serial queue and never launches Chrome after it quit; refreshes are coalesced per provider (no stacked scans, no stale overwrite); favicons read from a cloned snapshot instead of `immutable=1` and the cache is pruned; release builds reject Lemon Squeezy test keys and keys from other stores; only Developer ID builds start Sparkle (0010); release.sh refuses a dirty tree or a non-increasing `CFBundleVersion`; docs and notices now mention Sparkle's update check and license.
- 2026-11-04: Sparkle 2 auto-updates (0009): "Check for Updates…" in the menu bar menu, feed `https://beamlauncher.app/appcast.xml`, EdDSA-signed; `make app` embeds Sparkle.framework, `scripts/release.sh` signs its XPC services/Autoupdate/Updater.app, new `make appcast`.
- 2026-11-04: About shows supporter details (plan, email, key ending) and a subtle "Receipts and billing" link to Lemon Squeezy; the license window shows one thank-you instead of two.
- 2026-11-04: "Support Beam" now opens the website's support section (replacing the old `getchanges.app` link); amounts are chosen there, not in the app (0008). Added "Enter License Key…" with a one-time Lemon Squeezy key check and a `beam://license?key=` link handler. Beam's first network request; SECURITY.md updated.
- 2026-11-04: Added `make release` / `scripts/release.sh`: Developer ID signed (hardened runtime), notarized and stapled `Beam.app` and `Beam.dmg`.
- 2026-11-04: Moved the website, its demo pipeline, marketing and metrics docs and business decisions 0003–0005 to a separate private repo; this repo is now just the app.
- 2026-11-04: Beaming to a Chrome tab in another Chrome window no longer flashes it and drops back to the window you were in: Beam now makes the target window Chrome's main window (Accessibility) before activating Chrome, instead of racing the two.
- 2026-11-04: Tab favicons prefer icons from the page's own origin, so sign-in pages no longer show another site's icon (Chrome maps redirect chains to the final icon).
- 2026-11-04: Added automated tests: split the package into a `BeamCore` library plus a thin `Beam` executable, Swift Testing suites for `Matcher`, `SearchIndex.rank` and `Support`, `make test`, and a GitHub Actions workflow.
- 2026-11-03: README explains that Beam is small on purpose and that features may be declined for that reason.
- 2026-11-03: Reviewed the license choice and kept GPL-3.0. `CONTRIBUTING.md` now asks for a DCO sign-off and a relicensing grant, so a future dual license stays possible.
- 2026-11-02: Docs pass for going public: architecture now covers `Support.swift`, testing no longer says rebuilds drop the Accessibility grant, changelog sorted, README and `CLAUDE.md` explain the AI-agent knowledge base.
- 2026-10-29: Decided to open source Beam under GPL-3.0 at launch (decision 0006) and added the go-public steps to the todo list.
- 2026-10-29: Added GPL-3.0 `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, GitHub issue templates and a README license/name notice; stopped tracking `__pycache__`.
- 2026-10-26: Apps installed inside a vendor folder (e.g. /Applications/DaVinci Resolve/DaVinci Resolve.app) now show up.
- 2026-10-26: Builds now pin their code-signing requirement to the bundle ID, so the Accessibility grant survives rebuilds. Without the permission, searching "window" or "accessibility" shows a result that opens the settings pane.
- 2026-10-26: Added `THIRD_PARTY_NOTICES.txt` (KeyboardShortcuts, MIT), bundled in both app builds and opened from an Acknowledgements… link in Settings.
- 2026-10-24: Tab titles are matched without a leading unread badge like "(11) ", so "what" prefix-matches "(11) WhatsApp".
- 2026-10-22: A tab whose title and URL both match gets a small boost within its match tier. Apps now rank above Chrome tabs that match only on their URL (a tab whose title matches still wins).
- 2026-10-22: Settings window and menu-bar menu now say "Beam Launcher" instead of "Beam" (titles, labels, status text, tooltips); search panel unchanged.
- 2026-10-21: Added the `docs/` project knowledge base and `CLAUDE.md`. Added the opt-in sandbox build (`make sandbox`). Decided on direct distribution, the supporter pricing model and Lemon Squeezy.
- Earlier history: see `git log` (initial launcher; window, tab and tab-group search; Spotlight-style panel; Settings and custom hotkey; launch at login; install scripts and dmg; icons and Chrome favicons).
- 2026-10-26: Windows on other Spaces are listed and focusing one switches to its Space (private AX and SkyLight APIs, decision 0007).
- 2026-11-04: Chrome tabs on other Spaces now switch to their Space. Added About Beam Launcher to the menu bar menu, showing the version and the git commit of the build.
- 2026-11-04: Chrome tab groups in windows on other Spaces are listed and focus correctly.
- 2026-11-05: About shows links to beamlauncher.app and the GitHub repo, with more breathing room.
- 2026-11-06: About is now Beam's own window sized to fit, instead of the standard panel (no scrollbar or white box).
- 2026-11-10: Beam notices when Claude Code sessions or Slack stop working after an app update and offers a report (GitHub issue, email or copy) showing exactly what is sent: versions and an error kind, never your data (decision 0015).
- 2026-11-10: Fresh clone built and ran on a second Mac with `make run`.

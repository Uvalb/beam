# Beam

A laser-focused Spotlight replacement: hit a shortcut, type, and jump to an **app**, **window**, **Chrome tab**,  or **Tab Group**

- Floats over the screen the mouse is on; results update as you type.
- Apps: everything in `/Applications`, `/System/Applications`, `~/Applications`, etc.
- Windows: matches window title and app name (via the Accessibility API).
- Chrome tabs: matches tab title (via AppleScript).
- Claude Code sessions: matches session title and project folder (read from Claude desktop's session files).
- Slack: channels you're in, people and group DMs with their photos (read from Slack desktop's local caches; messages are never used or shown).
- Slack results show only behind Slack's own prefixes: `@` for people and group DMs, `#` for channels; `@` or `#` alone lists the ones you used most recently.
- Ranking: exact → prefix → word-prefix → substring (or all words in any order: `mobile core` finds "core-mobile-team-devs") → fuzzy.

## Small on purpose

Beam does one thing: gets you to what you already have open, fast. No file search, no calculator, no clipboard history, no plugins. That's deliberate. Every extra feature makes the panel a little slower and a little busier, and there are great tools like Raycast and Alfred if you want a Swiss Army knife.

So if you suggest a feature and the answer is "no", please don't take it personally. It usually means the idea is good, just not for Beam. The things Beam will never be are listed in [docs/product.md](docs/product.md#non-goals), and ideas that make the core faster, smarter or more reliable are always welcome.

## Requirements

- macOS 13 (Ventura) or later.
- To build from source: Xcode 15 or later, or at least its Command Line Tools (`xcode-select --install`), which provide Swift 5.9+, `make`, `codesign` and the other tools `make app` uses.
- To run the tests (`make test`): Xcode 16 or later, since they use the Swift Testing framework.
- Swift packages, fetched automatically by SwiftPM on the first build (so the first build needs network access): [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 2.0+ and [Sparkle](https://github.com/sparkle-project/Sparkle) 2.6+.

## Build & run

```bash
make run
```

Builds `build/Beam.app` and launches it (no Dock icon).

## Install

```bash
make install    # build, copy to /Applications/Beam.app, relaunch
make uninstall  # quit Beam and remove /Applications/Beam.app
make dmg        # optional: build/Beam.dmg with an Applications shortcut
```

Beam enables launch-at-login on its own at first run. Uninstalling just removes the app; a stale entry may linger under System Settings > General > Login Items and can be removed there.

## Setup

1. **Hotkey:** Beam defaults to ⌥⌘Space. Change it in **Settings…** from Beam's menu bar icon (opens automatically on first launch). **Use ⌘Space (replace Spotlight)** walks you through turning off Spotlight's shortcut and switches over as soon as you do. Settings also warns if macOS's own shortcuts are holding the keys you picked.
2. **Accessibility:** grant Beam access when prompted (needed to list and raise windows).
3. **Automation:** allow Beam to control Google Chrome on first use (needed for tabs).

Keys: ↑/↓ to move, ↩ to go, Esc to dismiss.

## Acknowledgements

Beam uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus (MIT) and [Sparkle](https://sparkle-project.org) (MIT, with bundled third-party licenses) for updates. Full license text is in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt), which is also bundled in `Beam.app/Contents/Resources/` and opens from **Settings… → Acknowledgements…**.

Forks: change the bundle ID, `SUFeedURL` and `SUPublicEDKey` in `Resources/Info.plist` and `CodeSigning.officialTeamID`; builds not signed with Beam's Developer ID never start the updater.

## License

Beam is free software under the [GNU General Public License v3.0 or later](LICENSE) (GPL-3.0-or-later: version 3 of the GNU GPL, or any later version). You may use, study, change and share it under those terms.

The **Beam** name and the Beam icon are not covered by the license. If you distribute a modified version, give it a different name and icon so people can tell it apart from the official build.

## How this repo works

Beam is built with a lot of help from AI coding agents (Claude Code). [CLAUDE.md](CLAUDE.md) and [docs/](docs/) are the project's knowledge base: what Beam is and isn't ([product.md](docs/product.md)), how the code fits together ([architecture.md](docs/architecture.md)), and why things are the way they are ([decisions/](docs/decisions/)). Start there before reading code.

## Contributing

Bug reports are welcome; please use the issue templates. Before writing a pull request, open an issue so we can agree on the change first. Because Beam is small on purpose, some well-made features won't be merged; checking first saves you the work. See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: see [SECURITY.md](SECURITY.md).

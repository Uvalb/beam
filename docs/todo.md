# Todo

## Next
- Slack: support small workspaces whose state Chromium keeps inline in LevelDB (no blob file), using the existing Snappy decoder.
- Claude Code sessions: check Return by hand on a few kinds of session (plain folder, worktree, "No folder") after each Claude desktop update; the store and `claude://` link are undocumented (0014).
- Going live with payments: done in code (release builds reject test-mode keys, store ID 509476 checked). Before launch, switch the website checkout to live mode and validate one real key in a `make release` build.
- Website (private repo): honour `?from=app` (don't start a download), and point the checkout thank-you page at `beam://license` so supporters land back in the app.
- Sparkle (website, private repo): host `appcast.xml` at `https://beamlauncher.app/appcast.xml` and versioned dmgs (`Beam-<version>.dmg`) at `DOWNLOAD_PREFIX` (default `https://downloads.beamlauncher.app/`, R2; not `/download/`, which counts downloads). Bump `CFBundleVersion` in `Resources/Info.plist` for every release (Sparkle compares it). Back up the EdDSA private key (`generate_keys -x file`); losing it means users can't be updated.
- ~~Final update check against the real HTTPS feed~~ (done 2026-11-06): official 0.1.0 → 0.1.1 → 0.1.2 updated through `beamlauncher.app/appcast.xml`, installed and relaunched.

- Verify the secrets backup (made 2026-11-04 with `scripts/backup-secrets.sh`, stored where `../beam-private` says): `generate_keys -p` must print the public key in `Info.plist`, and the `.p12` must open with its passphrase (`openssl pkcs12 -info -in developer-id.p12 -nokeys`, on a restored copy, then delete it). Keep the passphrase apart from the backup.

## Going open source (before launch, see 0006)
1. ~~Audit git history~~ (done 2026-10-29): no keys or secrets. History does contain the personal email that support@ forwards to (an old todo line), the Team ID (public in any signed app anyway) and a `getchanges.app` donate URL in `Support.swift` that should point at Beam's own checkout. ~~Publish from one clean squashed commit~~ (done 2026-11-10: new `Uvalb/beam` is one commit; old history is private `Uvalb/beam-history`).
2. ~~Check a fresh clone builds on another Mac~~ (done 2026-11-10, on a friend's Mac).
3. ~~Docs pass as a stranger~~ (done 2026-11-02): fixed stale architecture and testing notes, sorted the changelog, said in README and `CLAUDE.md` that the docs are written for AI agents and humans.
4. ~~Add `LICENSE`, README license and name notice, `CONTRIBUTING.md`, `SECURITY.md`~~ (done 2026-10-29).
5. ~~Issue templates~~ (done). Labels and the pinned FAQ (#1) done 2026-11-10. Left: add saved replies (drafts in the private repo notes), and turn on private vulnerability reporting once public (GitHub doesn't offer it on private repos).
6. ~~Turn off Discussions, Wiki and Projects~~ (done 2026-11-10).
7. Trademark: a quick check (notes in the private business repo) found "Beam" alone unlikely to register (crowded, an existing Class 9 BEAM mark). Rely on the README name and icon notice and the "Beam Launcher" brand; get a proper USPTO check before paying for a filing.
8. ~~Check the Test workflow runs once public~~ (done 2026-11-10: runs and passes on the public repo, no quota issue).
9. Make the repo public on launch day, together with Show HN (launch plan is in the private business repo).

## Later or ideas
- Check in the real app: closed saved groups (needs bookmarks bar shown) reopen and focus, and the Settings drag list reorders results (now on the Results tab; also check ⌥↑/↓, right-click Move Up/Down, and that the window resizes between tabs).
- Try the command-key actions by hand (⌘T, ⌘F, ⌘↵, Tab completion, ⌘ held list; 0020): the implementer could not drive the UI. Also check the terminal picker opens iTerm/Ghostty/etc. at the folder (only iTerm was installed when built; Kitty/Alacritty/WezTerm args untested). Possible follow-up: Tab completion for hosts.
- Product direction (bookmarks, other browsers, System Settings panes, Cmd+Enter URLs, Cmd+T / Cmd+F for paths) lives in `roadmap.md`.
- Non-English follow-ups, ranked, from the 2026-11-09 review: typing with a non-Latin keyboard layout (Hebrew, Russian) can't find English names; Beam's own UI isn't localizable yet; "Part of group" stripping in `WindowProvider` is English-only (affects other Chromium browsers); English-only hint keywords.
- Tests: `AppProvider` folder scanning against a temporary directory (needs a `roots` parameter), and the refresh coalescing in `SearchIndex.refresh` (needs an injectable queue).
- Remove or keep the experimental sandbox build (`make sandbox`) now that the App Store is ruled out (see 0001).
- Fix the sandbox build's unexplained menu bar icon and hotkey problems, only if the App Store comes back into play.

Signing and notarization: done 2026-11-04 (`make release`, see testing.md).

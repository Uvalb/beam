# Releasing

How a new version gets to users (0.1.3 and 0.1.4 were cut this way). Run it from `~/code/beam` on `main`. The website half lives in the private `../beam-private` repo. Never type credentials: the Developer ID cert, the Sparkle EdDSA key and the `beam-notary` profile are all in the login Keychain.

## Before you start
- `git fetch` and `git status -sb` in **both** repos: `main` must match `origin/main`. An unpushed local commit (once, a version bump) gets folded into whatever PR is based on it next.
- Feature branches start from `origin/main`, not local `main`, for the same reason.
- `make test` passes, and `xcrun notarytool history --keychain-profile beam-notary` works.

## 1. Version bump (a PR)
In `Resources/Info.plist`, raise `CFBundleShortVersionString` (0.1.4 → 0.1.5) **and** `CFBundleVersion` by one (5 → 6). Sparkle compares `CFBundleVersion` only, so forgetting it means no update. Add a "Release x.y.z (build n): …" line to `changelog.md`. Open a PR and wait until its CI run **for the latest commit** has finished green (`gh pr checks`; "unstable" just means still running). The user merges it.

## 2. Build
`make release`, in the background (a few minutes): Developer ID signing with the hardened runtime, notarization, stapling. It must end with `accepted, source=Notarized Developer ID` for both `build/Beam.app` and `build/Beam.dmg`.

## 3. Feed
`make appcast`. It writes `build/appcast/Beam-<ver>.dmg` and a signed `build/appcast/appcast.xml` pointing at `https://downloads.beamlauncher.app/Beam-<ver>.dmg`. It refuses if the dmg is older than Info.plist.

## 4. Upload the dmg (ask the user first: it's public)
From `~/code/beam-private/website`, under both names (the versioned one for Sparkle, `Beam.dmg` for the website's Download button):
```
npx wrangler r2 object put beam-downloads/Beam-<ver>.dmg --file ~/code/beam/build/appcast/Beam-<ver>.dmg --content-type application/x-apple-diskimage --remote
npx wrangler r2 object put beam-downloads/Beam.dmg --file ~/code/beam/build/appcast/Beam-<ver>.dmg --content-type application/x-apple-diskimage --remote
```
Check: `curl -sI https://downloads.beamlauncher.app/Beam-<ver>.dmg` gives 200 and the dmg's size. Never route update dmgs through `beamlauncher.app/download`, which counts downloads. Keep old versioned dmgs: they're how you get an official previous build to test the update.

## 5. Publish the feed
Copy `build/appcast/appcast.xml` to `beam-private/website/public/appcast.xml` and commit ("appcast: x.y.z (build n)"). The deploy ships the whole local site, so first check `website/public` has nothing unreleased (compare with live; differences in email links are only Cloudflare's email obfuscation). The **user** runs the deploy, from the website folder (`wrangler.toml` is there; elsewhere it fails with "Must specify a directory"):
```
cd ~/code/beam-private/website && npx wrangler pages deploy
```
Check: `curl -s https://beamlauncher.app/appcast.xml | grep sparkle:version` shows the new build.

## 6. Test the update
Needs an **official** build of the previous version: download `Beam-<previous>.dmg` from R2 and copy its Beam.app to /Applications (`codesign -dv` must show `TeamIdentifier=P9GCM9K6AH`). `make install` and `make run` builds are ad-hoc and have no updater (0010). Accessibility must be granted again after switching. The user clicks Check for Updates… and installs; then confirm `CFBundleVersion` in `/Applications/Beam.app`.

## 7. Push
Push both repos (with the user's OK) so nothing is left only on the local `main`.

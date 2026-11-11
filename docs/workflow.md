# Development and release workflow

One maintainer, PRs to `main`, releases cut by hand. The mechanical release steps are in [releasing.md](releasing.md); this page says *when* and *how carefully*. Why: [decision 0023](decisions/0023-release-process.md).

## Day to day (PRs)
- One branch per change, from `origin/main`. One PR, squash-merged (history is one commit per PR, `(#n)` in the subject).
- Docs travel with the code in the same PR (changelog line, todo, architecture, decision, gotcha: see CLAUDE.md).
- Before merging: `swift test`, `make run`, and the checks in [testing.md](testing.md) that the change touches. CI (`test.yml`) must be green for the latest commit.
- Direct commits to `main` are fine only for docs-only trivial fixes (typos, a todo line). Never for code, `Info.plist` or release files.
- Merging does not release. Users only get what a release ships.

## Versioning
- `CFBundleShortVersionString`: semver. Patch (0.1.5) for fixes, minor (0.2.0) for new features or provider kinds, major when behavior breaks. Pre-1.0 is still honest semver.
- `CFBundleVersion`: integer build number, **+1 on every build that leaves the machine**, RCs included. Sparkle compares only this. `release.sh` refuses a build number not above `build/last-version`.
- Version bumps ride in their own small PR ("Release x.y.z (build n)"), as in [releasing.md](releasing.md) step 1.

## Release candidates
Make an RC for any release that touches permissions, signing, Sparkle, window/Chrome focus, or a provider's data source. Skip it for a small, well-tested fix.

1. Branch `release/0.2.0` from `main`; set `CFBundleShortVersionString` to `0.2.0-rc1` and bump `CFBundleVersion`. No PR needed for the RC bump itself; keep it on the branch.
2. `make release` (signed, notarized). This is the only honest test build: `make run`/`make install` are ad-hoc, a different app identity to macOS, so permission prompts, Accessibility and "access data from other apps" behave differently ([gotchas](gotchas.md), 0022).
3. **Hand-install** `build/Beam.dmg` over the real installed release in /Applications (not a separate copy, not a second bundle id). Run the pre-release checklist below. Fixes go on the branch as `-rc2` with a new build number.
4. When happy: set the version to `0.2.0` (build number above the RC's), PR to `main`, then follow [releasing.md](releasing.md). Never publish an RC to R2, `Beam.dmg` or the appcast.

**No Sparkle beta channel.** `sparkle:channel` would need the app to opt in, a second feed entry and extra release steps, to serve testers who don't exist yet. Revisit when there are outside testers (new decision then). Sparkle's update path is covered by step 6 of releasing.md after the final build.

## Public releases
Follow [releasing.md](releasing.md) exactly (bump PR, `make release`, `make appcast`, R2 upload, appcast commit and deploy, update test). Then, which that page does not cover:
- `git tag v<version>` on the merged bump commit, `git push origin v<version>`.
- GitHub release for the tag: notes from the changelog lines, dmg attached (same file as R2).
- The `Release x.y.z (build n)` changelog line (already part of the bump PR).

## Patch releases
Cut one for: a crash, a provider that stopped working, or a permission/signing regression. Not for polish.
- If `main` has only released work: fix via normal PR, then release as above.
- If `main` has unreleased work: `git switch -c release/0.1.x v0.1.4`, cherry-pick the fix (also land it on `main` by PR), bump patch and build number, `make release`, run the checklist's upgrade and affected-provider items, then publish per releasing.md and tag from the branch. Build number must still exceed every build ever published.
- Fast path: skip the RC, but never skip `make release` verification, the upgrade test, or the checklist items the fix touches.

## Rollback
Sparkle cannot downgrade. If a release is bad: remove its `<item>` from `beam-private/website/public/appcast.xml` and redeploy so nobody else gets it, then ship a fix as a new patch with a higher build number (re-adding the previous good build's dmg under a new build number is a last resort). Point `Beam.dmg` on R2 back at the last good dmg. Never delete old versioned dmgs from R2: they are how you bisect and test updates.

## Pre-release checklist
- Clean-install behavior: remove Beam's grants (`tccutil reset All com.beam.launcher`), launch, check the Accessibility prompt and that nothing prompts for other apps' data before it should (0022).
- Upgrade from the previous official release by Sparkle (releasing.md step 6), then confirm `CFBundleVersion`.
- Providers: apps/windows (including other Spaces), Chrome tabs and tab groups, Claude sessions, Slack `@`/`#`, System Settings panes.
- `codesign -dv` shows team `P9GCM9K6AH`; Gatekeeper does not warn on a mounted dmg copy.

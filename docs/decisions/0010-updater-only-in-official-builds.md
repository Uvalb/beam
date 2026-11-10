# 0010: Only official builds start the updater

Date: 2026-11-05. Supplements 0009.

Every build has the official `SUFeedURL` and `SUPublicEDKey` in `Info.plist`. Starting Sparkle in every build meant a contributor's `make run` build or a renamed fork would offer to replace itself with official Beam.

Decision: `AppDelegate` creates `SPUStandardUpdaterController` only when the running code's team ID is Beam's (`CodeSigning.officialTeamID`). Ad-hoc dev builds, the sandbox build and forks signed with another team get no updater and no "Check for Updates…" item.

Considered: a `BeamRelease` Info.plist key written by `release.sh`. Rejected because a fork copying `release.sh` would get it too; the team ID can't be copied.

Cost: testing updates needs a `make release` build. Forks that want updates change the team ID constant, feed URL and key.

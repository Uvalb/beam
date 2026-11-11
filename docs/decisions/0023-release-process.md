# 0023: PR flow and hand-installed release candidates

Date: 2026-11-11

## Context
An older working practice was "merge to main and reinstall, no dev slots". Since then the repo went public with PRs (squash merges), Developer ID releases and Sparkle updates, and macOS re-asks for other apps' data after every update (0022). A dev ad-hoc build installed over a Developer ID build is a different app to TCC, so it cannot validate permission behavior.

## Decision
- Everything goes through a PR to `main`, squash-merged; docs-only trivial fixes may go straight to `main`.
- Risky releases get a release candidate (`x.y.z-rcN`, a `make release` build with its own higher build number) that is installed by hand over the real release and checked with the pre-release checklist. RCs are never uploaded or put in the appcast.
- No Sparkle beta channel (`sparkle:channel`): there are no outside testers, and it adds feed and release steps.
- Patch releases branch from the release tag when `main` has unreleased work.
- Full text: [workflow.md](../workflow.md), mechanics in [releasing.md](../releasing.md).

## Consequences
Supersedes the old "merge to main and reinstall, no dev slots" practice. RCs cost a notarization run each. If outside testers appear, add a beta channel in a new decision.

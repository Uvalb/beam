# 0007: Private APIs for windows on other Spaces

**Date:** 2026-10-26 · **Status:** accepted

## Context
`kAXWindowsAttribute` only returns an app's windows on the current Space, so a window on Desktop 2 never showed up. The website promises finding windows "across Spaces", and the fix had to work on macOS 13+ for a directly distributed app.

## Decision
Follow alt-tab-macos:
- **Listing:** build AX elements from remote tokens (`_AXUIElementCreateWithRemoteToken`, token = pid, 0, `"coco"`, element ID) for element IDs 0..<1000 per app, within a 0.1s budget per app, and keep those whose subrole is a standard window or dialog. Merge with `kAXWindows` and dedupe by `_AXUIElementGetWindow`. Apps run in parallel.
- **Focusing:** `_SLPSSetFrontProcessWithOptions` plus two synthetic `SLPSPostEventRecordTo` key-window events (SkyLight, loaded with `dlsym`), then AX raise. This switches to the window's Space. If the symbols are missing, it falls back to `NSRunningApplication.activate()`.

## Alternatives considered
- **`CGWindowListCopyWindowInfo` with `.optionAll`:** sees off-Space window IDs, but window titles need Screen Recording permission, there's no AX element to raise, and layer-0 lists are full of invisible helper windows.
- **CGS Space APIs (`CGSCopySpacesForWindows`, `CGSManagedDisplaySetCurrentSpace`):** switch Spaces without telling the Dock, which leaves the Dock and Mission Control out of sync. They still don't give titles.
- **Changing the website copy:** rejected by the user.

## Consequences
- Private APIs: fine for direct distribution (0001) and for the GPL source release (0006), impossible on the App Store. They can break in a macOS update. Failure means fewer windows listed, not a crash: missing symbols in `dlsym` fall back, and a missing AX symbol would fail at launch, so check after major OS updates.
- Window listing costs up to ~0.1s per app on each refresh, on a background queue. With many windows that budget doesn't reach every element: Chrome with ~20 windows needed 0.8–1.1s. So listing can miss some off-Space windows, and focusing a Chrome tab searches for up to 3s, stopping at the target window.
- Chrome tab groups: listing asks Chrome (AppleScript) how many windows it has and searches, for up to 3s in the background, until it has found that many windows with a tab strip.
- The sandbox build can't list windows anyway (see gotchas).

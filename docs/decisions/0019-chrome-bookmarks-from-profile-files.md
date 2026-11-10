# 0019: Chrome bookmarks from the profile files

Date: 2026-11-10.

Context: the roadmap asked for bookmarks as results. Chrome's AppleScript has no bookmarks, and scraping the bookmarks bar would miss everything not shown.

Decision: `BookmarkProvider` (`Bookmarks.swift`) reads each profile's `Bookmarks` JSON under `~/Library/Application Support/Google/Chrome/`, naming profiles from `Local State`. Same rules as 0014: read only, local, fails closed, parsed files cached by modification date.
- New `ItemKind.bookmark`, default order just after apps, reorderable and switchable off in Settings.
- Hundreds of bookmarks would flood results, so `rank` drops a bookmark unless its name or URL host matches strongly (substring or better); no fuzzy matches, and no path/query matching.
- Choosing one reuses an open tab with the same URL (ignoring `#fragment` and trailing slash) through the existing tab focus; otherwise Chrome's own executable with `--profile-directory=<dir> <url>` (`open -a … --args` drops the flag when Chrome is already running, so the URL lands in the last active profile), so it opens in the bookmark's own profile.
- Only http(s) bookmarks: a `javascript:` bookmarklet never runs from Beam.
- Not in the sandbox variant: the provider returns nothing when `APP_SANDBOX_CONTAINER_ID` is set.

Cost: Chrome's file format is undocumented; the reuse check needs Automation permission (without it the URL just opens). Other browsers are still open (roadmap).

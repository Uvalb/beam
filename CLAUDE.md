# Beam

Hotkey launcher for macOS (Swift, AppKit, macOS 13+): type to jump to an app, window, Chrome tab or Chrome tab group. Open source (GPL-3.0), one maintainer, distributed directly (not the Mac App Store). These notes are written for AI coding agents, and work just as well for human contributors.

## Orient here before reading code

- `docs/product.md`: what Beam is, principles, non-goals
- `docs/architecture.md`: every source file in a paragraph; read this instead of the codebase
- `docs/decisions/`: why things are the way they are; don't reopen a decision without new information
- `docs/todo.md`: what's next
- `docs/testing.md`: how to verify a change
- `docs/releasing.md`: how to cut a release; follow it step by step whenever a version is bumped, built or uploaded
- `docs/gotchas.md`: traps that already cost time
- `docs/decisions/` has gaps (0003–0005): those are business decisions kept in a separate private repo, along with the website (beamlauncher.app), marketing and metrics. If you have it locally it's at `../beam-private`.

## Build

`make run` builds `build/Beam.app` and launches it. `make install` copies it to /Applications. `make sandbox` / `make run-sandbox` builds the experimental App Sandbox variant.

## Keeping docs current

When you finish a task:
- update `docs/todo.md`, and add a line to `docs/changelog.md`
- update `docs/architecture.md` if you added, removed or reshaped a component
- add a numbered file to `docs/decisions/` if you made a choice someone might question. Never rewrite an old decision: add a new one that supersedes it.
- add anything that tripped you up to `docs/gotchas.md`

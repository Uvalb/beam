# 0021: Choice of terminal for ⌘T

Date: 2026-11-10. Supersedes the "Terminal.app only" part of 0020.

When more than one known terminal is installed, Settings shows a "Terminal" picker; otherwise nothing (Terminal.app is always there). Stored as the bundle ID in `terminalApp`; a choice that's been uninstalled falls back to Terminal.

Known terminals are a fixed list (`TerminalApp`), not "whatever handles shell scripts": each opens a folder differently. Terminal, iTerm2, Ghostty and Warp take the folder as a document through `NSWorkspace.open(_:withApplicationAt:)`. Kitty, Alacritty and WezTerm get a new instance with their working-directory argument. No AppleScript, so no Automation prompt. Adding another terminal is one case plus how it opens.

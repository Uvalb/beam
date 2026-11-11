# 0020: Command-key actions on typed text

Date: 2026-11-10. Resolves the open questions in the roadmap's "command-key actions".

**Trigger.** While ⌘ is held in the panel, the list is replaced by the actions that apply to the typed text (`ItemKind.action`, badge shows the key: ⌘T, ⌘F, ⌘↵). If none applies, the normal list stays. ⌘T, ⌘F and ⌘↵ also work without waiting for the list to refresh. The panel sees ⌘ through `flagsChanged` in `KeyPanel.sendEvent`.

**Clashes checked.** The panel is non-activating with its own `performKeyEquivalent` (only ⌘D before), and `SystemShortcut` (Shortcuts.swift) only inspects macOS's global hotkeys (Spotlight, Finder search) for the *summon* shortcut, so ⌘T/⌘F/⌘↵ inside the panel don't touch it. The text field has no Find, and Beam's menu bar menu is not in the key path. ⌘Tab is the system's, which is why path completion uses plain Tab.

**Paths.** A query is a path if it starts with `/` or `~/` (or is `~`). Autocomplete is Tab only (the roadmap's preferred option): the directory is read when Tab is pressed, never while typing, and ⌘ held does one `stat` of the path. Tab fills the shared prefix of the matching folders (case-insensitive, files and hidden folders skipped unless you type `.`), and further Tabs step through the choices. Pasted paths with quotes, `\ ` or a trailing `/` work. A file path opens its parent folder.

**Terminal.app only** for now. It opens through `NSWorkspace.open(_:withApplicationAt:)`, so there's no Automation prompt and no AppleScript. A default-terminal setting (iTerm, Ghostty) each need their own open mechanism; do it when someone asks. Finder uses `NSWorkspace.open(folder)`.

**Hosts.** ⌘↵ opens a new tab in Chrome (its current window; the default browser if Chrome isn't installed) via `NSWorkspace`, so no Automation prompt either. A single word gets `.com`; anything with a dot, a port or `localhost` is used as typed; `http` for localhost and IPs, `https` otherwise. Remembered hosts that start with the typed text are listed before the `.com` guess, so `youtube` can offer `youtube.co.il` once you've opened it. History is a `typedHosts` list in UserDefaults (newest first, 50 max), recorded only when you open a host with ⌘↵. **Chrome's own history is not read**: richer, but invasive, and it needs a copy of a locked database for a feature that works fine without it. Revisit only if the small history proves too thin.

**Not done.** Tab completion for hosts, a candidate list for path completion, and other terminals. Opening these actions does not count as a beam toward the support milestones.

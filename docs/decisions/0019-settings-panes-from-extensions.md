# 0019: System Settings panes are read from System Settings' extensions

Date: 2026-11-10.

**Decision.** `SettingsPaneProvider` builds the pane list at runtime from `/System/Library/ExtensionKit/Extensions/*.appex`. A pane is an extension whose Info.plist has `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.Settings.extension.ui`, a `SettingsExtensionAttributes` dict, and `allowsXAppleSystemPreferencesURLScheme = true`. It opens with `x-apple.systempreferences:<CFBundleIdentifier>`. The name is `InfoPlist.loctable`'s `CFBundleDisplayName` in the user's language, else the plain `CFBundleDisplayName`.

**Why not a static list.** The roadmap worried about per-version ids. Checked on macOS 26.6: 50 panes, all with the flag, bundle ids work as URLs (opened Wi-Fi and Privacy & Security by hand), and names like "Wi‑Fi" and "Privacy & Security" are already localized. A list in the code would rot with every release and miss panes that only exist on some Macs (Bluetooth-less, MDM, Family). Reading the plists needs no permission and takes ~80 ms, on the existing refresh queue.

**Details.**
- New `ItemKind.settingsPane`, shown as "Settings", default rank right after apps, switchable in Settings like any kind.
- "Wi‑Fi" uses U+2011; a plain-hyphen key is added so "wi-fi" matches.
- Not checked: macOS 13/14/15 (only 26 was available). The extension layout exists since 13 (Ventura's System Settings), so the same code should work; if a version has none, the provider returns nothing and the rest is unaffected.
- Not done: sub-panes (`?Privacy_Accessibility` and similar anchors). Those aren't discoverable from the plists.

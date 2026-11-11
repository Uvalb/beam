// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// System Settings panes ("Wi-Fi", "Displays", "Privacy & Security"), opened with
/// `x-apple.systempreferences:<bundle id>`. The list is read at runtime from System Settings' own
/// ExtensionKit extensions, so it follows whatever macOS version is running (decision 0019).
enum SettingsPaneProvider {
    static let extensionsDir = "/System/Library/ExtensionKit/Extensions"
    static let settingsExtensionPoint = "com.apple.Settings.extension.ui"
    static let settingsApp = "/System/Applications/System Settings.app"

    /// One pane's facts, as read from an extension's Info.plist.
    struct Pane: Equatable {
        let id: String
        let name: String
    }

    /// The pane for an extension's Info.plist, or nil when it isn't a Settings pane that opens by URL.
    /// `localizedName` is the name in the user's language, if the bundle has one.
    static func pane(info: [String: Any], localizedName: String?) -> Pane? {
        guard let attrs = info["EXAppExtensionAttributes"] as? [String: Any],
              attrs["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
              let settings = attrs["SettingsExtensionAttributes"] as? [String: Any],
              settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
              let id = info["CFBundleIdentifier"] as? String else { return nil }
        // Some extensions have no localized name; the plain one is often an internal name
        // ("WiFiSettings"), so it is the last resort.
        let raw = info["CFBundleDisplayName"] as? String
        guard let name = [localizedName, raw].compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        return Pane(id: id, name: name)
    }

    static func url(_ id: String) -> URL? { URL(string: "x-apple.systempreferences:" + id) }

    static func load() -> [SearchItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: extensionsDir) else { return [] }
        let icon = NSWorkspace.shared.icon(forFile: settingsApp)
        var items: [SearchItem] = []
        for entry in entries.sorted() where entry.hasSuffix(".appex") {
            guard let bundle = Bundle(path: extensionsDir + "/" + entry), let info = bundle.infoDictionary else { continue }
            // localizedString echoes the key when the table has no entry.
            let key = "CFBundleDisplayName"
            var localized: String? = bundle.localizedString(forKey: key, value: nil, table: "InfoPlist")
            if localized == key { localized = nil }
            guard let pane = pane(info: info, localizedName: localized), let url = url(pane.id) else { continue }
            // Apple writes "Wi‑Fi" with a non-breaking hyphen, which typing "wi-fi" wouldn't match.
            let plain = pane.name.replacingOccurrences(of: "\u{2011}", with: "-")
            items.append(SearchItem(
                kind: .settingsPane, title: pane.name, subtitle: "System Settings",
                keys: plain == pane.name ? [pane.name] : [pane.name, plain], id: "pane|" + pane.id,
                icon: icon, activate: { NSWorkspace.shared.open(url) }))
        }
        return items
    }
}

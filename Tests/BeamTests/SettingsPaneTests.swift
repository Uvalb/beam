// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

struct SettingsPaneTests {
    private func info(point: String = "com.apple.Settings.extension.ui", url: Bool? = true, name: String? = "Displays") -> [String: Any] {
        var settings: [String: Any] = [:]
        if let url { settings["allowsXAppleSystemPreferencesURLScheme"] = url }
        var d: [String: Any] = ["CFBundleIdentifier": "com.apple.Displays-Settings.extension",
                                "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": point, "SettingsExtensionAttributes": settings]]
        if let name { d["CFBundleDisplayName"] = name }
        return d
    }

    @Test func readsAPane() {
        #expect(SettingsPaneProvider.pane(info: info(), localizedName: nil) == .init(id: "com.apple.Displays-Settings.extension", name: "Displays"))
    }

    @Test func localizedNameWins() {
        #expect(SettingsPaneProvider.pane(info: info(name: "WiFiSettings"), localizedName: "Wi‑Fi")?.name == "Wi‑Fi")
    }

    @Test func skipsWhatIsNotAUrlPane() {
        #expect(SettingsPaneProvider.pane(info: info(point: "com.apple.screensaver"), localizedName: nil) == nil)
        #expect(SettingsPaneProvider.pane(info: info(url: nil), localizedName: nil) == nil)
        #expect(SettingsPaneProvider.pane(info: info(name: nil), localizedName: nil) == nil)
    }

    @Test func urlUsesBundleId() {
        #expect(SettingsPaneProvider.url("com.apple.wifi-settings-extension")?.absoluteString == "x-apple.systempreferences:com.apple.wifi-settings-extension")
    }

    @Test func listsPanesOnThisMac() {
        let titles = SettingsPaneProvider.load().map(\.title)
        #expect(titles.contains("Displays"))
        #expect(titles.contains("Sound"))
    }

    @Test func wifiMatchesWithAPlainHyphen() {
        let item = SearchItem(kind: .settingsPane, title: "Wi\u{2011}Fi", subtitle: "", keys: ["Wi\u{2011}Fi", "Wi-Fi"], icon: nil, activate: {})
        #expect(SearchIndex.rank([item], query: "wi-fi").count == 1)
    }
}

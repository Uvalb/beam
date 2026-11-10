// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ServiceManagement

/// Starts Beam at login via SMAppService. On by default once installed.
enum LaunchAtLogin {
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Beam: launch at login \(newValue ? "register" : "unregister") failed: \(error)")
            }
        }
    }

    /// Turn it on the first time Beam runs from /Applications (i.e. installed, not a dev build).
    /// Only applied once, so a user who turns it off stays off.
    static func applyDefaultIfInstalled() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: defaultAppliedKey),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        isEnabled = true
        d.set(true, forKey: defaultAppliedKey)
    }
}

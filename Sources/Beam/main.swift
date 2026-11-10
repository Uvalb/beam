// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import BeamCore

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

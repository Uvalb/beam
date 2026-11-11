// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import KeyboardShortcuts
import Sparkle

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    override public init() { super.init() }
    private var panel: SearchPanel!
    private let index = SearchIndex()
    private let settings = SettingsWindowController()
    private let about = AboutWindowController()
    private let supportWindow = SupportWindowController()
    private var statusItem: NSStatusItem!
    /// Rescans apps in the background when the app folders change (never on the hotkey).
    private var appWatcher: AppWatcher?
    /// Only official builds (signed with Beam's Developer ID) update themselves, so dev builds and
    /// forks never offer to replace themselves with official Beam. The sandbox build is ad-hoc too.
    private let updater: SPUStandardUpdaterController? =
        CodeSigning.teamID() == CodeSigning.officialTeamID
        ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil

    public func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        promptForAccessibility()
        LaunchAtLogin.applyDefaultIfInstalled()
        settings.onLicense = { [weak self] in self?.supportWindow.show() }
        panel = SearchPanel(index: index)
        index.refreshAll()
        appWatcher = AppWatcher(roots: AppProvider.roots) { [weak self] in self?.index.refreshApps() }

        KeyboardShortcuts.onKeyDown(for: .toggleBeam) { [weak self] in self?.panel.toggle() }
        setupStatusItem()

        // First launch: show Settings so the user can pick a shortcut (or take over ⌘Space).
        if !UserDefaults.standard.bool(forKey: "didShowSettingsOnce") {
            UserDefaults.standard.set(true, forKey: "didShowSettingsOnce")
            settings.show()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt on every open so the beam count is current.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open Beam Launcher", action: #selector(openBeam), keyEquivalent: "")
        open.setShortcut(for: .toggleBeam)
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: "About Beam Launcher", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        if let updater {
            let check = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            check.target = updater
            menu.addItem(check)
        }
        menu.addItem(.separator())
        let support = NSMenuItem(title: "Support Beam ♥", action: #selector(donate), keyEquivalent: "")
        if Support.count > 0 { support.toolTip = "\(Support.formatted(Support.count)) beams so far" }
        menu.addItem(support)
        if !Support.isSupporter {
            menu.addItem(NSMenuItem(title: "Enter License Key…", action: #selector(enterLicense), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Beam Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.target == nil && item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func donate() { Support.openDonatePage() }

    @objc private func enterLicense() { supportWindow.show() }

    /// The website's thank-you page links back with `beam://license?key=…`.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { if let key = Support.licenseKey(fromURL: url) { supportWindow.show(key: key) } }
    }

    @objc private func openBeam() { panel.show() }

    @objc private func openSettings() { settings.show() }

    /// About's credits: supporter status, then links to the website and the source.
    /// Generous paragraph spacing, since the standard panel packs everything tightly.
    private static func aboutCredits() -> NSAttributedString {
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 3
        para.paragraphSpacing = 10
        let base: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        func link(_ text: String, _ url: URL, color: NSColor? = nil) -> NSAttributedString {
            var a = base
            a[.link] = url
            if let color { a[.foregroundColor] = color }
            return NSAttributedString(string: text, attributes: a)
        }
        let s = NSMutableAttributedString()
        if Support.isSupporter {
            var lines = ["Supporter ♥ Thank you for keeping Beam alive."]
            if let l = Support.license {
                if !l.plan.isEmpty { lines.append(l.plan + (l.testMode ? " (test mode)" : "")) }
                lines.append((l.email.isEmpty ? "" : l.email + " · ") + "key ending \(l.keyEnding)")
            }
            s.append(NSAttributedString(string: lines.joined(separator: "\n") + "\n", attributes: base))
            s.append(link("Receipts and billing", Support.ordersURL, color: .tertiaryLabelColor))
        } else {
            s.append(NSAttributedString(string: "Free, with nothing locked.\n", attributes: base))
            s.append(link("Support Beam ♥", Support.supportURL))
        }
        s.append(NSAttributedString(string: "\n", attributes: base))
        s.append(link("beamlauncher.app", Support.websiteURL))
        s.append(NSAttributedString(string: "   ·   ", attributes: base))
        s.append(link("Source on GitHub", Support.repoURL))
        return s
    }

    @objc private func showAbout() { about.show(credits: Self.aboutCredits()) }

    private static func menuBarIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 16, height: 16)
            img.isTemplate = true
            img.accessibilityDescription = "Beam Launcher"
            return img
        }
        return NSImage(systemSymbolName: "light.beacon.max", accessibilityDescription: "Beam Launcher")
    }

    private func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

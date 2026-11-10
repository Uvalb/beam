// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import KeyboardShortcuts
import SwiftUI

/// State behind the Settings window. Polls the system shortcuts while the window is
/// open, so it notices when the user frees ⌘Space in System Settings.
@MainActor
final class ShortcutSettings: ObservableObject {
    @Published private(set) var current: KeyboardShortcuts.Shortcut?
    @Published private(set) var conflict: SystemShortcut?
    @Published private(set) var spotlightHoldsCommandSpace = true
    /// The user asked for ⌘Space and Beam is waiting for them to turn Spotlight's off.
    @Published private(set) var waitingForCommandSpace = false
    private var timer: Timer?

    var usesCommandSpace: Bool { current == .commandSpace }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        waitingForCommandSpace = false
    }

    func useCommandSpace() {
        if SystemShortcut.spotlightHoldsCommandSpace {
            waitingForCommandSpace = true
            SystemShortcut.openKeyboardSettings()
        } else {
            KeyboardShortcuts.setShortcut(.commandSpace, for: .toggleBeam)
        }
        refresh()
    }

    func cancelWaiting() { waitingForCommandSpace = false }

    func refresh() {
        spotlightHoldsCommandSpace = SystemShortcut.spotlightHoldsCommandSpace
        if waitingForCommandSpace && !spotlightHoldsCommandSpace {
            waitingForCommandSpace = false
            KeyboardShortcuts.setShortcut(.commandSpace, for: .toggleBeam)
        }
        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleBeam)
        let newConflict = shortcut.flatMap(SystemShortcut.holding)
        // Re-register once the system lets go of the keys, so Beam's hotkey takes effect.
        if conflict != nil && newConflict == nil, let shortcut {
            KeyboardShortcuts.setShortcut(nil, for: .toggleBeam)
            KeyboardShortcuts.setShortcut(shortcut, for: .toggleBeam)
        }
        current = shortcut
        conflict = newConflict
    }
}

struct SettingsView: View {
    @ObservedObject var model: ShortcutSettings
    var onLicense: () -> Void = {}
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var order = KindOrder.current
    @State private var disabled = KindOrder.disabled
    @State private var maxResults = MaxResults.current

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Beam Launcher", name: .toggleBeam) { _ in model.refresh() }
                status
            } footer: {
                Text("Spotlight stays available from its menu bar icon whichever shortcut you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text(Support.isSupporter ? "Thank you for supporting Beam ♥" : "Beam is free, and nothing is locked.")
                    Spacer()
                    if !Support.isSupporter { Button("Enter License Key…") { onLicense() } }
                    Button("Support Beam ♥") { Support.openDonatePage() }
                }
            }
            let blocked = ProviderHealth.Provider.allCases.filter { ProviderHealth.needsAccess($0) && !disabled.contains($0.itemKind)
                && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
            if !blocked.isEmpty {
                Section {
                    ForEach(blocked, id: \.self) { p in
                        HStack {
                            Label("\(p.resultsName): needs access", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open System Settings…") { NSWorkspace.shared.open(ProviderHealth.fullDiskAccessURL) }
                        }
                    }
                } footer: {
                    Text("macOS is blocking Beam from reading \(blocked.map(\.appName).joined(separator: " and ")), and won’t ask again. Turn on Beam Launcher under Full Disk Access, then quit and reopen Beam.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            let broken = ProviderHealth.confirmed()
            if !broken.isEmpty {
                Section {
                    ForEach(broken, id: \.self) { p in
                        HStack {
                            Label("\(p.resultsName): not reading since \(p.appName) \(ProviderHealth.state(p)?.sourceVersion ?? "")",
                                  systemImage: "exclamationmark.triangle")
                            Spacer()
                            Button("Report…") { ProviderHealth.showReport(p) }
                        }
                    }
                } footer: {
                    Text("Beam reads these apps’ own files, which can change in any update.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Open Beam Launcher at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        LaunchAtLogin.isEnabled = on
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            } footer: {
                if let notices = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
                    Button("Acknowledgements…") { NSWorkspace.shared.open(notices) }
                        .buttonStyle(.link)
                        .font(.footnote)
                }
            }
            Section {
                List {
                    ForEach(order, id: \.self) { kind in
                        Toggle(kind.settingsTitle, isOn: Binding(
                            get: { !disabled.contains(kind) },
                            set: { on in
                                if on { disabled.remove(kind) } else { disabled.insert(kind) }
                                KindOrder.disabled = disabled
                            }))
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1); KindOrder.current = order }
                }
                .frame(height: 200)
                Stepper("Show up to \(maxResults) results", value: $maxResults, in: MaxResults.range)
                    .onChange(of: maxResults) { MaxResults.current = $0 }
                Button("Restore Defaults") {
                    order = ItemKind.defaultOrder; disabled = []; maxResults = MaxResults.defaultValue
                    KindOrder.current = order; KindOrder.disabled = disabled
                }
                .disabled(order == ItemKind.defaultOrder && disabled.isEmpty && maxResults == MaxResults.defaultValue)
            } header: {
                Text("Results")
            } footer: {
                Text("Drag to reorder; untick to leave a kind out (it is then not loaded at all). Order applies to close matches; rough (fuzzy) matches still sort by how well they match. Results that don’t fit on screen scroll.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var status: some View {
        if let conflict = model.conflict {
            VStack(alignment: .leading, spacing: 8) {
                Label("macOS uses this shortcut for “\(conflict.title)”, so Beam Launcher won’t open with it. Turn that off in Keyboard Shortcuts, or pick another shortcut.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open Keyboard Settings…") { SystemShortcut.openKeyboardSettings() }
            }
        } else if model.waitingForCommandSpace {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Spotlight to release ⌘Space…").bold()
                }
                Text("In System Settings, click **Keyboard Shortcuts…**, choose **Spotlight**, and untick **Show Spotlight search**. Beam Launcher switches to ⌘Space as soon as you do.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Keyboard Settings…") { SystemShortcut.openKeyboardSettings() }
                    Button("Cancel") { model.cancelWaiting() }
                }
            }
        } else if model.usesCommandSpace {
            Label("Beam Launcher has replaced Spotlight on ⌘Space.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button("Use ⌘Space (replace Spotlight)") { model.useCommandSpace() }
                if !model.spotlightHoldsCommandSpace {
                    Text("Spotlight’s ⌘Space shortcut is turned off. If you want it back, turn on **Show Spotlight search** in Keyboard Shortcuts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Keyboard Settings…") { SystemShortcut.openKeyboardSettings() }
                }
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model = ShortcutSettings()
    var onLicense: () -> Void = {}
    private lazy var window: NSWindow = {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, onLicense: { [weak self] in self?.onLicense() })))
        w.title = "Beam Launcher Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        return w
    }()

    func show() {
        model.start()
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
    }
}

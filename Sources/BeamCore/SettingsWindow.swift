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

/// General tab: things set once (shortcut, login, terminal).
struct GeneralSettingsView: View {
    @ObservedObject var model: ShortcutSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var terminal = TerminalApp.current
    private let terminals = TerminalApp.installed

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Beam Launcher", name: .toggleBeam) { _ in model.refresh() }
                status
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Spotlight stays available from its menu bar icon whichever shortcut you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open Beam Launcher at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        LaunchAtLogin.isEnabled = on
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            } header: {
                Text("Startup")
            }
            if terminals.count > 1 {
                Section {
                    Picker("Open folders with ⌘T in", selection: $terminal) {
                        ForEach(terminals, id: \.self) { Text($0.name).tag($0) }
                    }
                    .onChange(of: terminal) { TerminalApp.current = $0 }
                } header: {
                    Text("Actions")
                }
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

/// Results tab: the ranking (numbered, with drag handles so reordering is discoverable;
/// right-click or ⌥↑/↓ move a row too), how many results show, and provider problems.
struct ResultsSettingsView: View {
    @State private var order = KindOrder.current
    @State private var disabled = KindOrder.disabled
    @State private var maxResults = MaxResults.current
    @State private var selection: ItemKind?

    private var countChoices: [Int] {
        Array(Set([5, 7, 9, 12, 15, 20, 30, maxResults])).filter { MaxResults.range.contains($0) }.sorted()
    }

    var body: some View {
        Form {
            problems
            Section {
                List(selection: $selection) {
                    ForEach(Array(order.enumerated()), id: \.element) { index, kind in
                        row(index: index, kind: kind)
                            .tag(kind)
                            .contextMenu {
                                Button("Move Up") { move(kind, by: -1) }.disabled(index == 0)
                                Button("Move Down") { move(kind, by: 1) }.disabled(index == order.count - 1)
                            }
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1); KindOrder.current = order }
                }
                .frame(height: CGFloat(order.count) * 28 + 8)
                .background(MoveKeys(up: { if let k = selection { move(k, by: -1) } },
                                     down: { if let k = selection { move(k, by: 1) } }))
                HStack {
                    Spacer()
                    Button("Reset Order") {
                        order = ItemKind.defaultOrder; disabled = []
                        KindOrder.current = order; KindOrder.disabled = disabled
                    }
                    .disabled(order == ItemKind.defaultOrder && disabled.isEmpty)
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Ranking")
                    Text("· drag to reorder, higher wins close matches").foregroundStyle(.secondary).fontWeight(.regular)
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help("Order applies to close matches; rough (fuzzy) matches still sort by how well they match. A switched-off kind isn’t loaded at all. Right-click a row or press ⌥↑/↓ to move it without dragging.")
                }
            }
            Section {
                Picker("Show up to", selection: $maxResults) {
                    ForEach(countChoices, id: \.self) { Text("\($0) results").tag($0) }
                }
                .onChange(of: maxResults) { MaxResults.current = $0 }
            } header: {
                Text("Display")
            } footer: {
                Text("Results that don’t fit on screen scroll.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(index: Int, kind: ItemKind) -> some View {
        let on = !disabled.contains(kind)
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
            Image(systemName: kind.settingsSymbol)
                .frame(width: 18)
                .foregroundStyle(on ? .secondary : .tertiary)
            Text(kind.settingsTitle).foregroundStyle(on ? .primary : .tertiary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { on },
                set: { new in
                    if new { disabled.remove(kind) } else { disabled.insert(kind) }
                    KindOrder.disabled = disabled
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func move(_ kind: ItemKind, by delta: Int) {
        guard let i = order.firstIndex(of: kind), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
        KindOrder.current = order
    }

    @ViewBuilder private var problems: some View {
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
    }
}

/// ⌥↑ / ⌥↓ while the Settings window is key move the selected ranking row.
private struct MoveKeys: NSViewRepresentable {
    var up: () -> Void
    var down: () -> Void
    final class Coordinator { var monitor: Any? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak v] e in
            guard let v, e.window == v.window, e.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) else { return e }
            switch e.keyCode {
            case 126: up(); return nil
            case 125: down(); return nil
            default: return e
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }
}

/// Support tab: supporter status, license, version and acknowledgements.
struct SupportSettingsView: View {
    var onLicense: () -> Void = {}

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "heart").foregroundStyle(.pink)
                    Text(Support.isSupporter ? "Thank you for supporting Beam" : "Beam is free, and nothing is locked.")
                    Spacer()
                    if Support.isSupporter {
                        Button("Manage License…") { onLicense() }
                    } else {
                        Button("Enter License Key…") { onLicense() }
                        Button("Support Beam ♥") { Support.openDonatePage() }
                    }
                }
            } footer: {
                HStack {
                    Text("Beam \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                    Spacer()
                    if let notices = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
                        Button("Acknowledgements") { NSWorkspace.shared.open(notices) }
                            .buttonStyle(.link)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension ItemKind {
    var settingsSymbol: String {
        switch self {
        case .app: return "square.grid.2x2"
        case .window: return "macwindow"
        case .tab: return "globe"
        case .tabGroup: return "folder"
        case .closedGroup: return "archivebox"
        case .claudeSession: return "sparkles"
        case .slack: return "number"
        case .action: return "bolt"
        case .settingsPane: return "gearshape"
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model = ShortcutSettings()
    var onLicense: () -> Void = {}
    private lazy var window: NSWindow = {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        @MainActor func add<V: View>(_ view: V, _ label: String, _ symbol: String) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        add(GeneralSettingsView(model: model), "General", "gearshape")
        add(ResultsSettingsView(), "Results", "list.number")
        add(SupportSettingsView(onLicense: { [weak self] in self?.onLicense() }), "Support", "heart")
        let w = NSWindow(contentViewController: tabs)
        w.title = "Beam Launcher Settings"
        w.styleMask = [.titled, .closable]
        w.toolbarStyle = .preference
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

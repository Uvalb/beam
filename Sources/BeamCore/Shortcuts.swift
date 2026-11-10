// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleBeam = Self("toggleBeam", default: .init(.space, modifiers: [.option, .command]))
}

extension KeyboardShortcuts.Shortcut {
    static let commandSpace = Self(.space, modifiers: .command)
}

/// macOS's own shortcuts that commonly sit on the keys people want for a launcher.
/// They live in the private com.apple.symbolichotkeys preferences; Beam only reads them
/// and sends the user to System Settings to change them.
enum SystemShortcut: Int, CaseIterable {
    case spotlight = 64       // ⌘Space by default
    case finderSearch = 65    // ⌥⌘Space by default

    var title: String {
        switch self {
        case .spotlight: return "Show Spotlight search"
        case .finderSearch: return "Show Finder search window"
        }
    }

    /// The system shortcut that is enabled and bound to `shortcut`, if any; it takes
    /// priority over Beam's.
    static func holding(_ shortcut: KeyboardShortcuts.Shortcut) -> SystemShortcut? {
        allCases.first { $0.binding == (shortcut.carbonKeyCode, modifierMask(shortcut.modifiers)) }
    }

    /// Whether Spotlight still owns ⌘Space.
    static var spotlightHoldsCommandSpace: Bool { holding(.commandSpace) == .spotlight }

    /// (key code, modifiers) while enabled; nil when disabled.
    private var binding: (Int, Int)? {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return Self.binding(from: all?[String(rawValue)] as? [String: Any], default: defaultBinding)
    }

    /// One com.apple.symbolichotkeys entry → (key code, relevant modifiers); nil when disabled.
    static func binding(from entry: [String: Any]?, default d: (Int, Int)) -> (Int, Int)? {
        guard let entry else { return d }
        guard (entry["enabled"] as? Bool) ?? true else { return nil }
        guard let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count >= 3 else { return d }
        return (params[1], params[2] & relevantModifiers)
    }

    private var defaultBinding: (Int, Int) {
        let space = 49
        switch self {
        case .spotlight: return (space, Self.modifierMask([.command]))
        case .finderSearch: return (space, Self.modifierMask([.command, .option]))
        }
    }

    static let relevantModifiers = Int(NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue)

    private static func modifierMask(_ flags: NSEvent.ModifierFlags) -> Int {
        Int(flags.rawValue) & relevantModifiers
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}

private func == (lhs: (Int, Int)?, rhs: (Int, Int)) -> Bool {
    guard let lhs else { return false }
    return lhs.0 == rhs.0 && lhs.1 == rhs.1
}

// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Actions on what you typed rather than things that exist (decision 0020): while ⌘ is held in the
/// panel, the list shows what ⌘T (Terminal here), ⌘F (Finder here) and ⌘↵ (new Chrome tab) would do.
/// Everything here is pure except `PathInput.completions`, `PathInput.directory`, `HostHistory`
/// and the `run…` functions; none of it runs on an ordinary query, only while ⌘ is down or on Tab.
enum PathInput {
    /// A query is a path when it starts with `/` or `~/` (or is `~`).
    static func isPath(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.hasPrefix("/") || q.hasPrefix("~/") || q == "~"
    }

    /// The absolute path for a typed path: `~` expanded, shell-style `\ ` unescaped, quotes and
    /// trailing `/` dropped (a pasted path from Terminal or Finder often has them).
    static func expand(_ query: String) -> String {
        var q = query.trimmingCharacters(in: .whitespaces)
        if q.count >= 2, let f = q.first, f == q.last, f == "'" || f == "\"" { q = String(q.dropFirst().dropLast()) }
        q = q.replacingOccurrences(of: "\\ ", with: " ")
        q = (q as NSString).expandingTildeInPath
        while q.count > 1, q.hasSuffix("/") { q.removeLast() }
        return q
    }

    /// The folder to open for a typed path: the path itself, or its parent if it's a file.
    /// nil when nothing exists there. One `stat`; only called while ⌘ is held.
    static func directory(_ query: String) -> URL? {
        guard isPath(query) else { return nil }
        let path = expand(query)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        let url = URL(fileURLWithPath: path)
        return isDir.boolValue ? url : url.deletingLastPathComponent()
    }

    /// Folders matching the last typed component, each in the form typed (`~/` kept), ending in `/`.
    /// Reads one directory; called only when Tab is pressed. Hidden folders only if the prefix starts with `.`.
    static func completions(for query: String) -> [String] {
        guard isPath(query) else { return [] }
        let typed = query.trimmingCharacters(in: .whitespaces)
        let slash = typed.lastIndex(of: "/") ?? typed.startIndex
        let head = String(typed[...slash])                       // "~/Doc" -> "~/", "/usr/lo" -> "/usr/"
        let prefix = String(typed[typed.index(after: slash)...])
        guard typed != "~" else { return ["~/"] }
        let dir = expand(head.isEmpty ? "/" : head)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        let showHidden = prefix.hasPrefix(".")
        let p = prefix.lowercased()
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .filter { n in
                guard showHidden || !n.hasPrefix("."), p.isEmpty || n.lowercased().hasPrefix(p) else { return false }
                var d: ObjCBool = false
                return FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(n), isDirectory: &d) && d.boolValue
            }
            .map { head + $0 + "/" }
    }

    /// The longest shared start of `names`, ignoring case (the first name's spelling wins).
    static func commonPrefix(_ names: [String]) -> String {
        guard var common = names.first else { return "" }
        for n in names.dropFirst() {
            while !n.lowercased().hasPrefix(common.lowercased()) { common.removeLast() }
        }
        return common
    }
}

/// Hosts the user has opened with ⌘↵, newest first, in UserDefaults. Chrome's own history is not read.
enum HostHistory {
    static let key = "typedHosts"
    static let limit = 50
    nonisolated(unsafe) static var d = UserDefaults.standard

    static var hosts: [String] { d.stringArray(forKey: key) ?? [] }

    static func record(_ host: String) {
        var h = hosts.filter { $0 != host }
        h.insert(host, at: 0)
        d.set(Array(h.prefix(limit)), forKey: key)
    }
}

enum URLInput {
    /// What to open for a typed token, best first: remembered hosts that start with it, then the
    /// token itself with `.com` added unless it already has a TLD, a port, or is localhost/an IP.
    /// A token that can't be a host (spaces, other characters, a path) gives none.
    static func candidates(_ query: String, history: [String]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, !PathInput.isPath(q), isHostLike(q) else { return [] }
        var out: [String] = []
        if !q.contains("/") && !q.contains(":") {
            out += history.filter { $0.hasPrefix(q) && !$0.contains("/") }
        }
        let literal = hasTLD(q) ? q : q + ".com"
        if !out.contains(literal) { out.append(literal) }
        return Array(out.prefix(4))
    }

    static func isHostLike(_ q: String) -> Bool {
        let hostPart = q.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? q
        guard !hostPart.isEmpty, !q.contains(" ") else { return false }
        return hostPart.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*(:\d{1,5})?$"#,
                              options: .regularExpression) != nil
    }

    private static func hasTLD(_ q: String) -> Bool {
        let host = String(q.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0])
        return host.contains(".") || host.contains(":") || host == "localhost"
    }

    /// http for local addresses, https for everything else.
    static func url(for host: String) -> URL? {
        let h = host.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let local = h.hasPrefix("localhost") || h.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?$"#, options: .regularExpression) != nil
        return URL(string: (local ? "http://" : "https://") + host)
    }
}

/// Terminals ⌘T can open (decision 0021). The first group takes a folder like a document;
/// the second needs a new instance with a working-directory argument.
enum TerminalApp: String, CaseIterable {
    case terminal = "com.apple.Terminal", iterm = "com.googlecode.iterm2", ghostty = "com.mitchellh.ghostty",
         warp = "dev.warp.Warp-Stable", kitty = "net.kovidgoyal.kitty", alacritty = "org.alacritty",
         wezterm = "com.github.wez.wezterm"

    static let key = "terminalApp"

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) }
    var name: String { appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "Terminal" }

    static var installed: [TerminalApp] { allCases.filter { $0.appURL != nil } }

    /// The user's choice if it's still installed, else Terminal.
    static var current: TerminalApp {
        get { UserDefaults.standard.string(forKey: key).flatMap(TerminalApp.init(rawValue:)).flatMap { $0.appURL != nil ? $0 : nil } ?? .terminal }
        set {
            if newValue == .terminal { UserDefaults.standard.removeObject(forKey: key) }
            else { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
        }
    }

    /// Command-line arguments that open a window at `dir`; nil when the app takes the folder as a document.
    func arguments(for dir: String) -> [String]? {
        switch self {
        case .terminal, .iterm, .ghostty, .warp: return nil
        case .kitty: return ["--single-instance", "--directory", dir]
        case .alacritty: return ["--working-directory", dir]
        case .wezterm: return ["start", "--cwd", dir]
        }
    }

    func open(at dir: URL) {
        guard let app = appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        if let args = arguments(for: dir.path) {
            config.arguments = args
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app, configuration: config)
        } else {
            NSWorkspace.shared.open([dir], withApplicationAt: app, configuration: config)
        }
    }
}

enum CommandActions {
    static let chromeID = "com.google.Chrome"
    static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    private static func appIcon(_ url: URL?) -> NSImage? {
        url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    static func terminalItem(_ query: String) -> SearchItem? {
        guard let dir = PathInput.directory(query) else { return nil }
        let term = TerminalApp.current
        return SearchItem(kind: .action, title: "Open \(term.name) here", subtitle: dir.path, keys: [], id: "action|terminal",
                          trailing: "⌘T", icon: appIcon(term.appURL), activate: { term.open(at: dir) })
    }

    static func finderItem(_ query: String) -> SearchItem? {
        guard let dir = PathInput.directory(query) else { return nil }
        return SearchItem(kind: .action, title: "Open in Finder", subtitle: dir.path, keys: [], id: "action|finder",
                          trailing: "⌘F", icon: appIcon(finderURL), activate: { openFinder(at: dir) })
    }

    static func urlItems(_ query: String) -> [SearchItem] {
        let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID)
        return URLInput.candidates(query, history: HostHistory.hosts).map { host in
            SearchItem(kind: .action, title: "Open \(host)", subtitle: "New tab in Chrome", keys: [], id: "action|url|\(host)",
                       trailing: "⌘↵", icon: appIcon(chrome), activate: { openURL(host) })
        }
    }

    /// The rows shown while ⌘ is held: all actions that apply to `query`; empty if none does.
    static func items(for query: String) -> [SearchItem] {
        if PathInput.isPath(query) { return [terminalItem(query), finderItem(query)].compactMap { $0 } }
        return urlItems(query)
    }

    /// The bar's hint: what ⌘ does for the typed text, nil when nothing applies. No filesystem access.
    static func hint(for query: String, held: Bool) -> String? {
        if PathInput.isPath(query) { let t = TerminalApp.current.name
            return held ? "⌘T \(t) · ⌘F Finder" : "Hold ⌘ for \(t), Finder" }
        guard !URLInput.candidates(query, history: []).isEmpty else { return nil }
        return held ? "⌘↵ New Chrome tab" : "Hold ⌘ to open as a site"
    }

    static func openFinder(at dir: URL) {
        NSWorkspace.shared.open(dir)
    }

    /// A new tab in Chrome (its current window), or the default browser if Chrome isn't installed.
    /// Remembers the host. No AppleScript, so no Automation prompt.
    static func openURL(_ host: String) {
        guard let url = URLInput.url(for: host) else { return }
        HostHistory.record(host)
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

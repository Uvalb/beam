// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

enum ItemKind: Int, CaseIterable {
    case app = 0, window = 1, tab = 2, tabGroup = 3, claudeSession = 4, slack = 5, closedGroup = 6
    /// A command-key action on the typed text (0020); never ranked, never in Settings.
    case action = 7

    /// Result order among strong matches unless the user changed it in Settings (see 0016).
    /// Stored Claude sessions and Slack conversations aren't open, so they rank after apps.
    static let defaultOrder: [ItemKind] = [.window, .tab, .tabGroup, .closedGroup, .app, .claudeSession, .slack]

    var badge: String {
        switch self {
        case .app: return "App"
        case .window: return "Window"
        case .tab: return "Chrome Tab"
        case .tabGroup: return "Tab Group"
        case .claudeSession: return "Claude Session"
        case .slack: return "Slack"
        case .closedGroup: return "Closed Group"
        case .action: return "Action"
        }
    }

    var settingsTitle: String {
        switch self {
        case .app: return "Apps"
        case .window: return "Windows"
        case .tab: return "Chrome tabs"
        case .tabGroup: return "Chrome tab groups"
        case .closedGroup: return "Closed saved tab groups"
        case .claudeSession: return "Claude sessions"
        case .slack: return "Slack channels and DMs"
        case .action: return "Actions"
        }
    }
}

/// The user's result kinds: their order and which are switched off. Kept in UserDefaults as raw
/// values; unknown or missing kinds are dropped or appended in default order, so a list stored
/// by another version still works. A switched-off kind is neither loaded nor shown.
enum KindOrder {
    static let key = "resultKindOrder"
    static let disabledKey = "resultKindsDisabled"
    /// Posted when kinds are switched on or off (they must be loaded or dropped); a reorder only
    /// affects ranking, which reads `current` on each search, so it posts nothing.
    static let changed = Notification.Name("beam.resultKindsChanged")

    static func normalize(_ raw: [Int]) -> [ItemKind] {
        var seen = Set<ItemKind>()
        var out = raw.compactMap(ItemKind.init(rawValue:)).filter { seen.insert($0).inserted }
        out += ItemKind.defaultOrder.filter { !seen.contains($0) }
        return out
    }

    static var current: [ItemKind] {
        get { normalize(UserDefaults.standard.array(forKey: key) as? [Int] ?? []) }
        set {
            if newValue == ItemKind.defaultOrder { UserDefaults.standard.removeObject(forKey: key) }
            else { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: key) }
        }
    }

    static var disabled: Set<ItemKind> {
        get { Set((UserDefaults.standard.array(forKey: disabledKey) as? [Int] ?? []).compactMap(ItemKind.init(rawValue:))) }
        set {
            guard newValue != disabled else { return }
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: disabledKey) }
            else { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: disabledKey) }
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static func isEnabled(_ kind: ItemKind) -> Bool { !disabled.contains(kind) }
}

/// How many results to list, set in Settings. 9 was the original fixed value (fits a small laptop screen).
enum MaxResults {
    static let key = "maxResults"
    static let defaultValue = 9
    static let range = 3...30

    static var current: Int {
        get { clamp(UserDefaults.standard.object(forKey: key) as? Int ?? defaultValue) }
        set {
            if newValue == defaultValue { UserDefaults.standard.removeObject(forKey: key) }
            else { UserDefaults.standard.set(clamp(newValue), forKey: key) }
        }
    }

    static func clamp(_ n: Int) -> Int { min(max(n, range.lowerBound), range.upperBound) }
}

/// Slack's own habit: "@" narrows the search to people, "#" to channels.
enum SearchScope: Character {
    case people = "@", channels = "#"

    /// The scope and the rest of the query, or no scope for a plain query.
    static func parse(_ query: String) -> (SearchScope?, String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let first = q.first, let scope = SearchScope(rawValue: first) else { return (nil, q) }
        return (scope, String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
    }
}

struct SearchItem {
    let kind: ItemKind
    let title: String
    let subtitle: String
    /// Strings the query is matched against; best score wins.
    let keys: [String]
    /// Weaker keys (e.g. a tab's URL): a strong match here ranks after apps.
    var secondaryKeys: [String] = []
    /// Stable identity across refreshes (e.g. Chrome's tab id); defaults to kind + title + subtitle.
    var id: String? = nil
    /// Added to the primary score, up to `Matcher.maxBoost` (e.g. a recently used Slack conversation).
    var boost = 0
    /// The prefix that narrows the search to this item, if any.
    var scope: SearchScope?
    /// Shown in the badge column instead of the kind's name (an action's key, such as ⌘T).
    var trailing: String? = nil
    let icon: NSImage?
    let activate: () -> Void

    var identity: String { id ?? "\(kind.rawValue)|\(title)|\(subtitle)" }
}

/// Holds cached apps / windows / Chrome tabs. Searches run against the cache so
/// typing is instant; the cache is refreshed in the background each time Beam opens.
final class SearchIndex {
    private(set) var apps: [SearchItem] = []
    private(set) var windows: [SearchItem] = []
    private(set) var tabs: [SearchItem] = []
    private(set) var tabGroups: [SearchItem] = []
    private(set) var sessions: [SearchItem] = []
    private(set) var slack: [SearchItem] = []
    private let queue = DispatchQueue(label: "beam.index", qos: .userInitiated, attributes: .concurrent)
    var onUpdate: (() -> Void)?

    init() {
        // Switching a kind on loads it at once; switching one off drops it.
        NotificationCenter.default.addObserver(forName: KindOrder.changed, object: nil, queue: .main) { [weak self] _ in
            self?.refreshApps()
            self?.refreshLive()
        }
    }

    func refreshAll() {
        refreshApps()
        refreshLive()
    }

    /// Windows and tabs change constantly; refresh them on every open.
    func refreshLive() {
        let on = { KindOrder.isEnabled($0) }
        refresh("windows", on(.window) ? WindowProvider.load : { [] }) { self.windows = $0 }
        refresh("tabs", on(.tab) ? ChromeProvider.load : { [] }) { self.tabs = $0 }
        let groups = on(.tabGroup), closed = on(.closedGroup)
        refresh("groups", groups || closed ? { ChromeGroupProvider.load(groups: groups, closed: closed) } : { [] }) { self.tabGroups = $0 }
        refresh("sessions", on(.claudeSession) ? ClaudeSessionProvider.load : { [] }) { self.sessions = $0 }
        refresh("slack", on(.slack) ? SlackProvider.load : { [] }) { self.slack = $0 }
    }

    func refreshApps() {
        refresh("apps", KindOrder.isEnabled(.app) ? AppProvider.load : { [] }) { self.apps = $0 }
    }

    // Main thread only. At most one run per provider: a refresh asked for while one is in
    // flight runs once more after it, so rapid toggling can't stack scans and results land in order.
    private var running: Set<String> = []
    private var rerun: Set<String> = []

    private func refresh(_ key: String, _ load: @escaping () -> [SearchItem], apply: @escaping ([SearchItem]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running.insert(key).inserted else { rerun.insert(key); return }
        queue.async {
            let items = load()
            DispatchQueue.main.async {
                apply(items)
                self.onUpdate?()
                self.running.remove(key)
                if self.rerun.remove(key) != nil { self.refresh(key, load, apply: apply) }
            }
        }
    }

    /// The row to select after the list was rebuilt: the previously selected item, by identity,
    /// if it is still listed (a background refresh mustn't move the selection), else the top row.
    static func keptRow(_ selected: String?, in items: [SearchItem]) -> Int {
        guard let selected, let i = items.firstIndex(where: { $0.identity == selected }) else { return 0 }
        return i
    }

    func search(_ query: String, limit: Int = 9) -> [SearchItem] {
        let off = KindOrder.disabled
        let all = apps + windows + tabs + tabGroups + sessions + slack
        return Self.search(off.isEmpty ? all : all.filter { !off.contains($0.kind) }, query: query, limit: limit, order: KindOrder.current)
    }

    /// Scoped items (Slack) show only behind their prefix, so they never crowd out apps and windows.
    /// A bare "@" or "#" lists that scope's most recently used items.
    static func search(_ items: [SearchItem], query: String, limit: Int = 9,
                       order: [ItemKind] = ItemKind.defaultOrder) -> [SearchItem] {
        let (scope, rest) = SearchScope.parse(query)
        // Scopes are Slack's, so a Slack notice (no access, stopped working) leads any scoped query:
        // otherwise "@name" just shows nothing, with no hint why.
        let notices = items.filter { ProviderHealth.isNotice($0) && $0.kind == .slack }
        // Without Slack (off, not installed) "@" and "#" are just characters: "#1234" finds a tab.
        let scoped = scope.map { s in !notices.isEmpty || items.contains { $0.scope == s } } ?? false
        guard let scope, scoped else {
            // A notice matches its app's name ("claude", "slack"), so it goes after the real
            // matches: Return on "cla" must still open Claude, not the report.
            let q = scope == nil ? rest : query
            let ranked = rank(items.filter { $0.scope == nil }, query: q, limit: limit, order: order)
            return ranked.filter { !ProviderHealth.isNotice($0) } + ranked.filter(ProviderHealth.isNotice)
        }
        let inScope = items.filter { $0.scope == scope }
        guard rest.isEmpty else { return Array((notices + rank(inScope, query: rest, limit: limit, order: order)).prefix(limit)) }
        let recent = inScope.filter { $0.boost > 0 }.sorted { $0.boost != $1.boost ? $0.boost > $1.boost : $0.title < $1.title }
        return Array((notices + recent).prefix(limit))
    }

    /// Pure ranking, separate from the cache so tests can feed it items.
    /// `order` ranks kinds among strong matches; fuzzy matches stay score-first.
    static func rank(_ items: [SearchItem], query: String, limit: Int = 9,
                     order: [ItemKind] = ItemKind.defaultOrder) -> [SearchItem] {
        let order = KindOrder.normalize(order.map(\.rawValue))
        func precedence(_ k: ItemKind) -> Int { order.firstIndex(of: k) ?? order.count }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        // (score, precedence, item); precedence order.count = matched only via a secondary key.
        var scored: [(Int, Int, SearchItem)] = []
        for item in items {
            let primary = item.keys.compactMap { Matcher.score(q, in: $0) }.max().map { $0 + min(item.boost, Matcher.maxBoost) }
            let secondary = item.secondaryKeys.compactMap { Matcher.score(q, in: $0) }.max()
            if let p = primary, Matcher.isStrong(p) {
                // Secondary key also matching (e.g. the URL) is a small tiebreak within the tier.
                let bonus = secondary.map { Matcher.isStrong($0) } == true ? 100 : 0
                scored.append((p + bonus, precedence(item.kind), item))
            } else if let s = secondary, Matcher.isStrong(s) {
                scored.append((s, order.count, item))
            } else if let best = [primary, secondary].compactMap({ $0 }).max() {
                scored.append((best, precedence(item.kind), item))
            }
        }
        // Real (non-fuzzy) matches rank by kind first, so an open window or tab beats an
        // unopened app, but an app beats a tab that only matched on its URL; within a kind,
        // and among fuzzy matches, the better score wins.
        scored.sort { a, b in
            let sa = Matcher.isStrong(a.0), sb = Matcher.isStrong(b.0)
            if sa != sb { return sa }
            if sa, a.1 != b.1 { return a.1 < b.1 }
            return a.0 != b.0 ? a.0 > b.0 : a.1 < b.1
        }
        return scored.prefix(limit).map { $0.2 }
    }
}

// MARK: - Apps

enum AppProvider {
    static let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                        "/Applications/Utilities", NSHomeDirectory() + "/Applications",
                        "/System/Library/CoreServices/Applications"]

    static func displayName(_ path: String, fallback: String) -> String {
        // Localized names only come back in the user's language because Info.plist sets
        // CFBundleAllowMixedLocalizations. German ones contain soft hyphens ("System\u{AD}einstellungen").
        let shown = FileManager.default.displayName(atPath: path).replacingOccurrences(of: "\u{AD}", with: "")
        let trimmed = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func load() -> [SearchItem] {
        let fm = FileManager.default
        var seen = Set<String>()
        var items: [SearchItem] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            // Vendors often install into a folder (e.g. /Applications/DaVinci Resolve/DaVinci Resolve.app),
            // so look one level into plain subfolders too.
            var paths: [String] = []
            for entry in entries {
                let path = root + "/" + entry
                if entry.hasSuffix(".app") { paths.append(path); continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                      let sub = try? fm.contentsOfDirectory(atPath: path) else { continue }
                paths += sub.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
            }
            for path in paths {
                let name = String((path as NSString).lastPathComponent.dropLast(4))
                guard seen.insert(name.lowercased()).inserted else { continue }
                let url = URL(fileURLWithPath: path)
                // The name Finder shows in the user's language ("Rechner" for Calculator);
                // the file name stays a key so the English name matches too.
                let shown = displayName(path, fallback: name)
                items.append(SearchItem(
                    kind: .app, title: shown, subtitle: path, keys: shown == name ? [name] : [shown, name],
                    icon: NSWorkspace.shared.icon(forFile: path),
                    activate: {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }))
            }
        }
        // Finder lives in CoreServices.
        let finder = "/System/Library/CoreServices/Finder.app"
        if !seen.contains("finder") {
            items.append(SearchItem(kind: .app, title: "Finder", subtitle: finder, keys: ["Finder"],
                                    icon: NSWorkspace.shared.icon(forFile: finder),
                                    activate: { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: finder), configuration: .init()) }))
        }
        return items
    }
}

// MARK: - Windows (Accessibility API)

enum WindowProvider {
    /// Shown when Accessibility access is missing, so windows don't vanish silently.
    private static let permissionHint = SearchItem(
        kind: .window, title: "Grant Accessibility access to search windows",
        subtitle: "System Settings → Privacy & Security → Accessibility",
        keys: ["window", "accessibility"],
        icon: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil),
        activate: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        })

    static func load() -> [SearchItem] {
        guard AXIsProcessTrusted() else { return [permissionHint] }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
                // Chrome windows are already covered, tab by tab, by ChromeProvider.
                && $0.bundleIdentifier != "com.google.Chrome"
        }
        // Enumerating windows on other Spaces costs up to ~0.1s per app, so do apps in parallel.
        var perApp = [[SearchItem]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            let found = windows(of: apps[i])
            lock.lock(); perApp[i] = found; lock.unlock()
        }
        return perApp.flatMap { $0 }
    }

    private static func windows(of app: NSRunningApplication) -> [SearchItem] {
        let appName = app.localizedName ?? ""
        let pid = app.processIdentifier
        var items: [SearchItem] = []
        for win in SpaceWindows.windows(of: pid) {
            let wid = SpaceWindows.windowID(win)
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &t)
            let title = stripChromeGroup((t as? String) ?? "")
            guard !title.isEmpty else { continue }
            items.append(SearchItem(
                kind: .window, title: title, subtitle: appName,
                keys: [title, appName, "\(appName) \(title)"], id: "win|\(pid)|\(wid)",
                icon: app.icon,
                activate: {
                    AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    // SkyLight switches to the window's Space; AX alone can't.
                    if !SpaceWindows.focus(pid: pid, windowID: wid) { app.activate() }
                    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                }))
        }
        return items
    }

    /// Chrome appends " - Part of group <name>" to window titles; only the tab's own
    /// title should match, so drop it.
    static func stripChromeGroup(_ title: String) -> String {
        title.replacingOccurrences(of: #" - Part of group .*?(?= - Google Chrome|$)"#,
                                   with: "", options: .regularExpression)
    }
}

// MARK: - Chrome tabs (AppleScript)

enum ChromeProvider {
    private static let bundleID = "com.google.Chrome"
    static let sep = "\u{1F}"   // unit separator
    static let rowSep = "\u{1E}" // record separator

    /// Shown when the user said no to Beam controlling Chrome (Automation), so tabs don't vanish silently.
    private static let automationHint = SearchItem(
        kind: .tab, title: "Allow Beam to control Google Chrome to search tabs",
        subtitle: "System Settings → Privacy & Security → Automation",
        keys: ["tabs", "automation", "permission"],
        icon: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil),
        activate: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        })

    static func load() -> [SearchItem] {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        // Chrome's tab `id` is stable for the tab's life, through reordering and dragging to
        // another window (tested 2026-11-09), unlike window id + index.
        let script = """
        set out to ""
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (id of t) & "\(sep)" & (title of t) & "\(sep)" & (URL of t) & "\(rowSep)"
                    end repeat
                end repeat
            end tell
        end if
        return out
        """
        let (desc, error) = AppleScript.runReporting(script)
        if error == AppleScript.notPermitted { return [automationHint] }
        guard let result = desc?.stringValue else { return [] }
        let icon = chrome.icon
        let rows = parseRows(result)
        let favicons = Favicons.icons(for: rows.map(\.url))
        return rows.map { r in
            SearchItem(
                kind: .tab, title: r.title.isEmpty ? r.url : r.title, subtitle: r.url,
                keys: [stripBadge(r.title.isEmpty ? r.url : r.title)], secondaryKeys: [urlKey(r.url)],
                id: "tab|\(r.id)", icon: favicons[r.url] ?? icon,
                activate: { focus(tabID: r.id, url: r.url, title: r.title) })
        }
    }

    /// `title` is Chrome's own (possibly empty: the item shows the URL then, but focus matches the real title).
    struct TabRow: Equatable { let id: Int, title: String, url: String }

    /// Splits the script's output into tabs, skipping malformed rows.
    static func parseRows(_ output: String) -> [TabRow] {
        output.components(separatedBy: rowSep).compactMap { row in
            let f = row.components(separatedBy: sep)
            guard f.count == 3, let id = Int(f[0]) else { return nil }
            return TabRow(id: id, title: f[1], url: f[2])
        }
    }

    /// Host and path only: query strings are long and would match almost anything.
    /// Drops a leading unread badge like "(11) " or "(99+) " so the real title can prefix-match.
    static func stripBadge(_ title: String) -> String {
        guard let r = title.range(of: #"^\(\d+\+?\)\s+"#, options: .regularExpression) else { return title }
        return String(title[r.upperBound...])
    }

    static func urlKey(_ url: String) -> String {
        guard let c = URLComponents(string: url), let host = c.host else { return url }
        return host + c.path
    }

    /// An AppleScript string literal.
    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Strictly in order: pick the tab, make its window Chrome's main window, then activate Chrome.
    /// `set index` alone only reorders the window; if Chrome activates afterwards (or concurrently)
    /// it brings its old main window back on top, so the target flashes and disappears.
    /// Finds the tab by id; failing that (Chrome restarted, so ids changed) by URL and title.
    /// If the tab is gone, does nothing rather than open some other tab.
    private static func focus(tabID: Int, url: String, title: String) {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let script = """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)"
                -- By id first, in every window; only then by URL and title.
                repeat with pass from 1 to 2
                    repeat with w in windows
                        set found to 0
                        if pass is 1 then
                            set ids to id of tabs of w
                            repeat with i from 1 to count of ids
                                if item i of ids is \(tabID) then
                                    set found to i
                                    exit repeat
                                end if
                            end repeat
                        else
                            set urls to URL of tabs of w
                            set titles to title of tabs of w
                            repeat with i from 1 to count of urls
                                if item i of urls is \(quoted(url)) and item i of titles is \(quoted(title)) then
                                    set found to i
                                    exit repeat
                                end if
                            end repeat
                        end if
                        if found is not 0 then
                            set active tab index of w to found
                            set index of w to 1
                            return "ok" & (title of active tab of w)
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return ""
        """
        DispatchQueue.global(qos: .userInteractive).async {
            let result = AppleScript.run(script)?.stringValue ?? ""
            guard result.hasPrefix("ok") else { return }   // tab is gone
            let title = String(result.dropFirst(2))
            if let win = axWindow(of: chrome, title: title) {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                // SkyLight switches to the window's Space; activate() alone stays on this one.
                if SpaceWindows.focus(pid: chrome.processIdentifier, windowID: SpaceWindows.windowID(win)) { return }
            }
            DispatchQueue.main.async { chrome.activate() }
        }
    }

    /// The window just moved to the front: AX lists windows front to back, so take the first
    /// whose title starts with the active tab's title, or else simply the frontmost.
    /// Windows on other Spaces come after the current Space's, via SpaceWindows.
    private static func axWindow(of chrome: NSRunningApplication, title: String) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        func matches(_ win: AXUIElement) -> Bool {
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &t)
            return !title.isEmpty && (t as? String)?.hasPrefix(title) == true
        }
        let axApp = AXUIElementCreateApplication(chrome.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        let current = (value as? [AXUIElement]) ?? []
        if let win = current.first(where: matches) { return win }
        // Not on this Space: search all of Chrome's elements, which with many windows takes a while.
        let other = SpaceWindows.allWindows(pid: chrome.processIdentifier, budget: 3, maxID: 1_000_000, until: matches)
        return other.last.flatMap { matches($0) ? $0 : nil } ?? current.first
    }
}

// MARK: - Chrome tab groups (Accessibility API)

/// Chrome's AppleScript dictionary has no tab groups, so read them from the tab strip.
/// Detection is structural, not by English text: a header is an AXTabGroup with no children
/// (DOM class `TabGroupHeader`, or `TabGroupHeaderView` with vertical tabs), and its member tabs are the AXTabButtons after it among the
/// same siblings (vertical tabs nest each group in its own container; the horizontal strip is flat).
/// Only the group's *name* has no language-neutral source: it is parsed from the header's
/// localized title ("group <name> - N Tabs, …" in English).
enum ChromeGroupProvider {
    private static let bundleID = "com.google.Chrome"
    private static let englishHeader = try! NSRegularExpression(pattern: #"^\s*group (.+?) - (\d+) Tabs?\b"#)
    /// Any language: "<words> <name> <dash> <count>". The count may be a word (Hebrew
    /// "כרטיסייה אחת", one tab), so its digits are optional.
    private static let genericHeader = try! NSRegularExpression(pattern: #"^\s*(.*?\S)\s+[-–—]\s+[^-–—]*?(\d*)[^-–—\d]*$"#)
    /// Many languages quote the name: German `Gruppe „Arbeit“ – 1 Tab`.
    private static let quotedName = try! NSRegularExpression(pattern: #"[„“”"«»‹›「『‚‘](.+)[“”"»«›‹」』‘’]"#)

    private static let groupIcon = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Tab group")

    struct Node { var isHeader: Bool; var isTab: Bool; var title: String }
    struct Header: Equatable { var name: String; var count: Int?; var localized: Bool }

    /// Parses a header title. `localized` means neither the English pattern nor a quoted name
    /// matched, so `name` may still carry Chrome's word for "group" (see `dropGroupWord`).
    static func parseHeader(_ raw: String) -> Header? {
        // The title goes on to list the member tabs: ", •  Tab one, •  Tab two".
        // Right-to-left titles start with invisible bidi marks (U+202B in Hebrew).
        var t = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            !(0x200E...0x200F).contains($0.value) && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value)
        }))
        if let r = t.range(of: #",\s*•"#, options: .regularExpression) { t = String(t[..<r.lowerBound]) }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        if let m = englishHeader.firstMatch(in: t, range: range),
           let n = Range(m.range(at: 1), in: t), let c = Range(m.range(at: 2), in: t) {
            return Header(name: String(t[n]), count: Int(t[c]), localized: false)
        }
        if let m = genericHeader.firstMatch(in: t, range: range),
           let n = Range(m.range(at: 1), in: t), let c = Range(m.range(at: 2), in: t) {
            let body = String(t[n])
            if let q = quotedName.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r = Range(q.range(at: 1), in: body) {
                return Header(name: String(body[r]), count: Int(t[c]), localized: false)
            }
            return Header(name: body, count: Int(t[c]), localized: true)
        }
        return Header(name: t, count: nil, localized: true)
    }

    /// Chrome's localized word for "group" (Hebrew "הקבוצה"), learned when two or more localized
    /// headers share their first word, and kept across launches. Until then names keep it,
    /// which still matches.
    private static var groupWord: String? = UserDefaults.standard.string(forKey: groupWordKey)
    private static let groupWordKey = "chromeGroupWord"
    private static let lock = NSLock()

    /// The word to strip now. A stored word that no current localized header starts with is
    /// stale (Chrome's language changed, or it was learned wrongly), so it is forgotten and relearned.
    static func learnGroupWord(_ names: [String], stored: String?) -> String? {
        var stored = stored
        if let w = stored, !names.isEmpty, !names.contains(where: { $0.split(separator: " ", maxSplits: 1).first.map(String.init) == w && $0.contains(" ") }) {
            stored = nil
        }
        return dropGroupWord(names, learned: stored).word
    }

    static func dropGroupWord(_ names: [String], learned: String?) -> (names: [String], word: String?) {
        let words = names.map { $0.split(separator: " ", maxSplits: 1).map(String.init) }
        var word = learned
        if Set(names).count >= 2, words.allSatisfy({ $0.count == 2 }), Set(words.map { $0[0] }).count == 1 {
            word = words[0][0]
        }
        guard let word else { return (names, nil) }
        return (words.map { $0.count == 2 && $0[0] == word ? $0[1] : $0.joined(separator: " ") }, word)
    }

    /// (header index, header, member indices) for each group header among one set of siblings.
    /// Members are the tabs after the header, up to the next header, while their titles contain
    /// the group's name (Chrome appends it), and no more than the header's count: in the flat
    /// strip, ungrouped tabs follow the group, and a collapsed group's tabs aren't listed at all.
    /// What member tabs' titles must contain: the name, minus a localized "group" word in front,
    /// which may be inflected differently in the tabs' "part of group …" text.
    static func memberKey(_ h: Header) -> String {
        guard h.localized, let sp = h.name.firstIndex(of: " ") else { return h.name }
        return String(h.name[h.name.index(after: sp)...])
    }

    static func layout(_ nodes: [Node], name: (Header) -> String) -> [(Int, String, [Int])] {
        var result: [(Int, String, [Int])] = []
        var i = 0
        while i < nodes.count {
            guard nodes[i].isHeader, let h = parseHeader(nodes[i].title) else { i += 1; continue }
            let n = name(h)
            var members: [Int] = []
            var j = i + 1
            while j < nodes.count, !nodes[j].isHeader {
                if nodes[j].isTab {
                    guard nodes[j].title.contains(n), members.count < (h.count ?? .max) else { break }
                    members.append(j)
                }
                j += 1
            }
            result.append((i, n, members))
            i += 1
        }
        return result
    }

    static func load(groups wantGroups: Bool = true, closed wantClosed: Bool = true) -> [SearchItem] {
        guard AXIsProcessTrusted(),
              let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        var items: [SearchItem] = []
        var closed: [String: SearchItem] = [:]
        // Chrome often has many windows, which the default short search doesn't reach, so
        // tell it how many to look for (in the background, so the extra time is fine).
        let count = AppleScript.run("""
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)" to return count windows
        end if
        return -1
        """)?.int32Value
        guard let count, count >= 0 else { return [] }
        let isBrowserWindow: (AXUIElement) -> Bool = { hasTabs($0) }
        let wins = SpaceWindows.windows(of: chrome.processIdentifier, expected: Int(count), counts: isBrowserWindow)
        if UserDefaults.standard.bool(forKey: TabStripDump.flag) { TabStripDump.write(wins, expected: Int(count)) }
        // Learn the localized "group" word across all windows' headers first.
        // Each window's tree is walked once here and reused for naming below.
        let scans = wantGroups ? wins.map { scan($0) } : wins.map { _ in [] }
        let localized = scans.joined().filter { $0.header.localized }.map { $0.header.name }
        lock.lock()
        let word = learnGroupWord(localized, stored: groupWord)
        if word != groupWord { groupWord = word; UserDefaults.standard.set(word, forKey: groupWordKey) }
        lock.unlock()
        for (win, scanned) in zip(wins, scans) {
            if wantClosed {
                for name in closedGroupNames(in: win) where closed[name] == nil {
                    closed[name] = SearchItem(
                        kind: .closedGroup, title: name, subtitle: "Closed · Google Chrome",
                        keys: [name], id: "closedgroup|\(name)", icon: groupIcon,
                        activate: { reopen(window: win, group: name, app: chrome) })
                }
            }
            guard wantGroups else { continue }
            for (name, _, tabs) in named(scanned, word: word) {
                items.append(SearchItem(
                    kind: .tabGroup, title: name, subtitle: "\(tabs.count == 0 ? "Collapsed" : "\(tabs.count) tabs") · Google Chrome",
                    keys: [name], id: "group|\(name)", icon: groupIcon,
                    activate: { focus(window: win, group: name, app: chrome) }))
            }
        }
        let open = Set(items.map(\.title))
        return items + closed.values.filter { !open.contains($0.title) }.sorted { $0.title < $1.title }
    }

    private static let savedPattern = try! NSRegularExpression(pattern: #"^\s*(.+?) group - (Closed|Opened)\s*$"#)

    /// (name, isClosed) from a saved-group button title like " Finances group - Closed". English Chrome only.
    static func savedGroup(fromTitle t: String) -> (name: String, closed: Bool)? {
        guard let m = savedPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let n = Range(m.range(at: 1), in: t), let s = Range(m.range(at: 2), in: t) else { return nil }
        return (String(t[n]), t[s] == "Closed")
    }

    /// Buttons of the bookmarks bar's "Saved Tab Groups" toolbar, as (name, closed, button).
    /// The bar must be visible. Web content is not searched (the tab walk skips toolbars, so this is its own walk).
    private static func savedButtons(in window: AXUIElement) -> [(String, Bool, AXUIElement)] {
        var level = [window]
        for _ in 0..<10 where !level.isEmpty {
            var next: [AXUIElement] = []
            for e in level {
                if role(e) == "AXWebArea" { continue }
                if title(e) == "Saved Tab Groups" {
                    return children(e).compactMap { b in
                        guard attr(b, kAXRoleDescriptionAttribute) as? String == "saved tab group button",
                              let g = savedGroup(fromTitle: title(b)) else { return nil }
                        return (g.name, g.closed, b)
                    }
                }
                next += children(e)
            }
            level = next
        }
        return []
    }

    private static func closedGroupNames(in window: AXUIElement) -> [String] {
        savedButtons(in: window).filter { $0.1 }.map { $0.0 }
    }

    /// Press the saved group's button to reopen it, then focus it like an open group.
    private static func reopen(window: AXUIElement, group: String, app: NSRunningApplication) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if !SpaceWindows.focus(pid: app.processIdentifier, windowID: SpaceWindows.windowID(window)) { app.activate() }
        DispatchQueue.global(qos: .userInteractive).async {
            guard let b = savedButtons(in: window).first(where: { $0.0 == group }) else { return }
            AXUIElementPerformAction(b.2, kAXPressAction as CFString)
            usleep(700_000)
            DispatchQueue.main.async { focus(window: window, group: group, app: app) }
        }
    }

    private static func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func role(_ e: AXUIElement) -> String { (attr(e, kAXRoleAttribute) as? String) ?? "" }
    private static func title(_ e: AXUIElement) -> String { (attr(e, kAXTitleAttribute) as? String) ?? "" }
    private static func isTab(_ e: AXUIElement) -> Bool { attr(e, kAXSubroleAttribute) as? String == "AXTabButton" }

    private static func isHeader(_ e: AXUIElement) -> Bool {
        guard role(e) == kAXTabGroupRole as String else { return false }
        if let classes = attr(e, "AXDOMClassList") as? [String] { return classes.contains { $0.hasPrefix("TabGroupHeader") } }
        return children(e).isEmpty   // the strip itself is an AXTabGroup too, but has children
    }

    /// Walks Chrome's own UI (not web content or toolbars), calling `visit` with each element's children.
    private static func walk(_ window: AXUIElement, _ visit: ([AXUIElement]) -> Bool) {
        var level = [window]
        for _ in 0..<24 where !level.isEmpty {
            var next: [AXUIElement] = []
            for e in level {
                let r = role(e)
                if r == "AXWebArea" || r == kAXToolbarRole as String { continue }
                let kids = children(e)
                if !visit(kids) { return }
                next += kids.filter { !isTab($0) }
            }
            level = next
        }
    }

    /// For debugging group detection: `defaults write com.beam.launcher BeamDumpChromeTabStrip -bool true`,
    /// then open Beam. Writes Chrome's UI tree (no web content) and what Beam made of it to
    /// ~/Library/Logs/Beam/chrome-tabstrip.txt. Holds tab and group titles, so it stays on this Mac.
    enum TabStripDump {
        static let flag = "BeamDumpChromeTabStrip"
        static var path: String { NSHomeDirectory() + "/Library/Logs/Beam/chrome-tabstrip.txt" }

        static func write(_ wins: [AXUIElement], expected: Int) {
            var out = "Beam tab strip dump \(Date())\nChrome windows (AppleScript): \(expected), found by AX: \(wins.count)\n"
            lock.lock(); let word = groupWord; lock.unlock()
            out += "Stored group word: \(word ?? "none")\n"
            for (n, win) in wins.enumerated() {
                out += "\n=== Window \(n + 1): \(title(win))\n"
                var level: [(AXUIElement, Int)] = [(win, 0)]
                while !level.isEmpty {
                    var next: [(AXUIElement, Int)] = []
                    for (e, depth) in level where depth < 24 {
                        let r = role(e)
                        if r == "AXWebArea" { out += "\(depth) AXWebArea (skipped)\n"; continue }
                        let kids = children(e)
                        let classes = (attr(e, "AXDOMClassList") as? [String])?.joined(separator: " ") ?? ""
                        let sub = attr(e, kAXSubroleAttribute) as? String ?? ""
                        let desc = attr(e, kAXRoleDescriptionAttribute) as? String ?? ""
                        let marks = (isHeader(e) ? " [HEADER]" : "") + (isTab(e) ? " [TAB]" : "")
                        let t = title(e)
                        if r != "AXGroup" || !t.isEmpty || !classes.isEmpty || !marks.isEmpty {
                            out += "\(depth) \(r) \(sub) «\(desc)» [\(classes)] kids=\(kids.count)\(marks) title=\(t.debugDescription)\n"
                        }
                        if isHeader(e) { out += "    parsed: \(String(describing: parseHeader(t)))\n" }
                        next += kids.map { ($0, depth + 1) }
                    }
                    level = next
                }
                out += "--- Groups Beam found in window \(n + 1):\n"
                for (name, _, tabs) in groups(in: win) { out += "  \(name.debugDescription): \(tabs.count) member tabs\n" }
                out += "--- Saved groups: \(savedButtons(in: win).map { "\($0.0) closed=\($0.1)" })\n"
            }
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? out.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func hasTabs(_ window: AXUIElement) -> Bool {
        var found = false
        walk(window) { kids in found = kids.contains(where: isTab); return !found }
        return found
    }

    /// Every header in the window with its parsed title and its member tabs (names not yet
    /// stripped of the localized "group" word).
    private static func scan(_ window: AXUIElement) -> [(header: Header, element: AXUIElement, tabs: [AXUIElement])] {
        var result: [(header: Header, element: AXUIElement, tabs: [AXUIElement])] = []
        walk(window) { kids in
            let nodes = kids.map { k -> Node in
                let h = isHeader(k), t = isTab(k)
                return Node(isHeader: h, isTab: t, title: h || t ? title(k) : "")
            }
            guard nodes.contains(where: { $0.isHeader }) else { return true }
            for (hi, _, members) in layout(nodes, name: memberKey) {
                guard let h = parseHeader(nodes[hi].title) else { continue }
                result.append((h, kids[hi], members.map { kids[$0] }))
            }
            return true
        }
        return result
    }

    /// (name, header, member tabs) per group; collapsed groups have no member tabs.
    private static func groups(in window: AXUIElement) -> [(String, AXUIElement, [AXUIElement])] {
        lock.lock(); let word = groupWord; lock.unlock()
        return named(scan(window), word: word)
    }

    private static func named(_ scanned: [(header: Header, element: AXUIElement, tabs: [AXUIElement])],
                              word: String?) -> [(String, AXUIElement, [AXUIElement])] {
        scanned.map { g in
            let name = g.header.localized ? dropGroupWord([g.header.name], learned: word).names[0] : g.header.name
            return (name, g.element, g.tabs)
        }
    }

    private static func focus(window: AXUIElement, group: String, app: NSRunningApplication) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        if !SpaceWindows.focus(pid: app.processIdentifier, windowID: SpaceWindows.windowID(window)) { app.activate() }
        DispatchQueue.global(qos: .userInteractive).async {
            func find() -> (AXUIElement, [AXUIElement])? {
                guard let g = groups(in: window).first(where: { $0.0 == group }) else { return nil }
                return (g.1, g.2)
            }
            guard let (header, tabs) = find() else { return }
            // Bring the window forward again now that Beam's panel is gone, as the tab path does:
            // the raise above runs while the panel is still closing, and macOS can drop it.
            func bringForward() {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                if !SpaceWindows.focus(pid: app.processIdentifier, windowID: SpaceWindows.windowID(window)) {
                    DispatchQueue.main.async { app.activate() }
                }
            }
            if let first = tabs.first {
                AXUIElementPerformAction(first, kAXPressAction as CFString)
                bringForward()
                return
            }
            // Collapsed: the header has no press action, so click it to expand, then select its first tab.
            // The click only lands if the window is on top, so bring it forward first.
            bringForward()
            usleep(250_000)
            click(header, in: window)
            usleep(300_000)
            if let first = find()?.1.first { AXUIElementPerformAction(first, kAXPressAction as CFString) }
        }
    }

    /// Whether the point is inside `window` (same app, same window), i.e. nothing else covers it.
    /// Chrome's tab strip doesn't hit-test to the group header itself, so compare windows, not elements.
    private static func isHit(_ window: AXUIElement, at pt: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(pt.x), Float(pt.y), &hit) == .success,
              let hit else { return false }
        var hitPid: pid_t = 0, winPid: pid_t = 0
        AXUIElementGetPid(hit, &hitPid); AXUIElementGetPid(window, &winPid)
        guard hitPid == winPid else { return false }
        guard let w = attr(hit, kAXWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return true }
        return CFEqual(w, window)
    }

    private static func click(_ e: AXUIElement, in window: AXUIElement) {
        var pos = CGPoint.zero, size = CGSize.zero
        guard let p = attr(e, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attr(e, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID(),
              AXValueGetValue(p as! AXValue, .cgPoint, &pos),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return }
        let pt = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        // A synthetic click lands on whatever is on top: only click if the header itself is there
        // (another window may cover it).
        guard isHit(window, at: pt) else { return }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
}


// MARK: - AppleScript

/// NSAppleScript isn't thread-safe, so every script runs on this one serial queue.
/// Call from a background thread, never from the queue itself. Scripts that talk to an app
/// must wrap their `tell` in `if application id "…" is running`: a plain `tell` launches it.
enum AppleScript {
    private static let queue = DispatchQueue(label: "beam.applescript", qos: .userInitiated)

    /// errAEEventNotPermitted: the user denied Beam Automation access to the app.
    static let notPermitted = -1743

    static func run(_ source: String) -> NSAppleEventDescriptor? { runReporting(source).0 }

    /// The result, or nil and the AppleScript error number.
    static func runReporting(_ source: String) -> (NSAppleEventDescriptor?, Int?) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return queue.sync {
            var err: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
            return (result, (err?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
        }
    }
}

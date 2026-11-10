// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Chrome's bookmarks, read from each profile's own `Bookmarks` JSON (see decision 0019).
/// Read only, local only, fails closed; not available in the App Sandbox variant.
enum BookmarkProvider {
    private static let bundleID = "com.google.Chrome"
    private static var chromeRoot: String { realHome() + "/Library/Application Support/Google/Chrome" }

    struct Bookmark: Equatable { let name: String, url: String }

    /// Walks Chrome's tree (`roots` → folders → `url` nodes). Only http(s) links: a bookmarklet
    /// (`javascript:`) must never run from here.
    static func parse(_ data: Data) -> [Bookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }
        var out: [Bookmark] = []
        func walk(_ node: [String: Any], depth: Int) {
            guard depth < 64 else { return }
            if node["type"] as? String == "url", let url = node["url"] as? String,
               url.hasPrefix("http://") || url.hasPrefix("https://") {
                out.append(Bookmark(name: node["name"] as? String ?? "", url: url))
            }
            for child in node["children"] as? [[String: Any]] ?? [] { walk(child, depth: depth + 1) }
        }
        for key in roots.keys.sorted() { if let node = roots[key] as? [String: Any] { walk(node, depth: 0) } }
        return out
    }

    /// Profile folder name → the name the user gave it, from Chrome's `Local State`.
    static func profileNames(_ data: Data) -> [String: String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }

    private static var cached: [String: (Date, [Bookmark])] = [:]

    static func load() -> [SearchItem] {
        // The sandbox can't read Chrome's folder, and its home is the container.
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else { return [] }
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: chromeRoot) else { return [] }
        let names = (try? Data(contentsOf: URL(fileURLWithPath: chromeRoot + "/Local State"))).map(profileNames) ?? [:]
        let profiles = dirs.filter { fm.fileExists(atPath: "\(chromeRoot)/\($0)/Bookmarks") }.sorted()
        var seen = Set<String>(), live = Set<String>()
        var items: [SearchItem] = []
        let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        for dir in profiles {
            let path = "\(chromeRoot)/\(dir)/Bookmarks"
            live.insert(path)
            let mod = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
            var marks: [Bookmark]
            if let mod, let hit = cached[path], hit.0 == mod { marks = hit.1 }
            else {
                marks = (try? Data(contentsOf: URL(fileURLWithPath: path))).map(parse) ?? []
                if let mod { cached[path] = (mod, marks) }
            }
            let profile = names[dir] ?? dir
            for m in marks {
                // The same page bookmarked in several profiles is listed once per profile (it opens there).
                guard seen.insert("\(dir)|\(m.url)").inserted else { continue }
                let key = ChromeProvider.urlKey(m.url)
                let host = URLComponents(string: m.url)?.host ?? key
                let title = m.name.isEmpty ? m.url : m.name
                items.append(SearchItem(
                    kind: .bookmark, title: title,
                    subtitle: profiles.count > 1 ? "\(profile) · \(key)" : key,
                    keys: [title, host], id: "bm|\(dir)|\(m.url)", icon: icon,
                    activate: { open(url: m.url, profileDir: dir) }))
            }
        }
        cached = cached.filter { live.contains($0.key) }
        return items
    }

    /// Reuses an open Chrome tab with this URL (any window), else opens it in the bookmark's profile.
    static func open(url: String, profileDir: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            if ChromeProvider.focusTab(withURL: url) { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Google Chrome", url, "--args", "--profile-directory=\(profileDir)"]
            try? p.run()
        }
    }

    private static func realHome() -> String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Claude desktop keeps one JSON file per Claude Code session; the `claude://` URL scheme
/// opens a session by id, so no automation permission is needed. Both are Claude's own
/// undocumented internals (see decision 0014): anything unexpected yields no results.
enum ClaudeSessionProvider {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let store = NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions"
    private static let scratchFolderMarker = "/scratch-workspaces/"
    private static let noFolder = "No folder"
    private static let worktreeMarker = "/.claude/worktrees/"

    struct Session: Equatable {
        let id: String
        let title: String
        /// Project folder name; for a worktree session, the parent repository's.
        let folder: String
        let worktree: String?
        let lastFocused: Double

        var subtitle: String { worktree.map { "\(folder) › \($0)" } ?? folder }
        /// An untitled session is titled after its folder; repeating it here would only add the
        /// secondary-key bonus and lift the session above an equally matched app.
        var folderKeys: [String] {
            ((folder == noFolder ? [] : [folder]) + (worktree.map { [$0] } ?? [])).filter { $0 != title }
        }
    }

    private struct Record: Decodable {
        let sessionId: String
        let title: String?
        let cwd: String?
        let originCwd: String?
        let worktreeName: String?
        let isArchived: Bool?
        let lastFocusedAt: Double?
        let lastActivityAt: Double?
    }

    static func load() -> [SearchItem] {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return [] }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let (sessions, health) = scan(store)
        let notice = ProviderHealth.record(.claudeSessions, health, appURL: appURL)
        return sessions.map { s in
            SearchItem(kind: .claudeSession, title: s.title, subtitle: s.subtitle, keys: [s.title],
                       secondaryKeys: s.folderKeys, icon: icon, activate: { open(s.id) })
        } + (notice.map { [$0] } ?? [])
    }

    /// How a store file read: a live or archived session, or not one we understand.
    enum FileStatus { case decoded, malformed, missingID }

    /// Parsed files by path, kept while the file's modification date is unchanged, so opening the
    /// panel only decodes sessions that changed (a store holds hundreds of files, tens of MB).
    /// `nil` caches a file that isn't a live session (archived, malformed) so it isn't re-read either.
    private static var cache: [String: (modified: Date, session: Session?, status: FileStatus)] = [:]
    private static let cacheLock = NSLock()

    /// Most recently used first, so equal matches show the session you were just in.
    static func sessions(in root: String) -> [Session] { scan(root).sessions }

    /// The sessions plus how healthy the read was: files there but none understood means Claude
    /// changed its format (decision 0015).
    static func scan(_ root: String) -> (sessions: [Session], health: ProviderHealth.Observation) {
        let rootURL = URL(fileURLWithPath: root)
        guard let files = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                               options: [.skipsHiddenFiles]) else { return ([], .init(outcome: .noData)) }
        cacheLock.lock(); defer { cacheLock.unlock() }
        var seen: [String: (modified: Date, session: Session?, status: FileStatus)] = [:]
        var anyEntry = false
        for case let url as URL in files {
            // Only real files count: an empty folder or .DS_Store isn't a changed layout.
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            anyEntry = true
            guard url.pathExtension == "json" else { continue }
            let path = url.path
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let hit = cache[path], hit.modified == modified {
                seen[path] = hit
            } else {
                let (session, status) = FileManager.default.contents(atPath: path).map(read) ?? (nil, .malformed)
                seen[path] = (modified, session, status)
            }
        }
        cache = seen  // drops deleted files
        let sessions = seen.values.compactMap(\.session).sorted { $0.lastFocused > $1.lastFocused }
        return (sessions, health(statuses: seen.values.map(\.status), anyEntry: anyEntry))
    }

    static func health(statuses: [FileStatus], anyEntry: Bool) -> ProviderHealth.Observation {
        let decoded = statuses.filter { $0 == .decoded }.count
        if statuses.isEmpty { return .init(outcome: anyEntry ? .broken(.layoutChanged) : .noData) }
        if decoded > 0 { return .init(outcome: .ok, filesSeen: statuses.count, parsed: decoded) }
        let kind: ProviderHealth.Kind = statuses.contains(.missingID) ? .missingField : .decodeFailed
        return .init(outcome: .broken(kind), filesSeen: statuses.count, parsed: 0)
    }

    static func read(_ data: Data) -> (Session?, FileStatus) {
        if let s = parse(data) { return (s, .decoded) }
        if (try? JSONDecoder().decode(Record.self, from: data)) != nil { return (nil, .decoded) }  // archived
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (nil, object != nil && object?["sessionId"] == nil ? .missingID : .malformed)
    }

    /// Archived sessions are hidden in Claude's sidebar too, so they are skipped like closed tabs.
    static func parse(_ data: Data) -> Session? {
        guard let r = try? JSONDecoder().decode(Record.self, from: data), r.isArchived != true else { return nil }
        let (folder, worktree) = folderNames(r)
        let title = r.title.flatMap { $0.isEmpty ? nil : $0 } ?? folder
        return Session(id: r.sessionId, title: title, folder: folder, worktree: worktree, lastFocused: r.lastFocusedAt ?? r.lastActivityAt ?? 0)
    }

    /// Mirrors the sidebar: sessions without a project folder show "No folder". A worktree session
    /// keeps the repo name so it matches like the others. Claude's own `originCwd`/`worktreeName`
    /// win when set; many records leave `worktreeName` null, so the `<repo>/.claude/worktrees/<name>`
    /// path is the fallback.
    private static func folderNames(_ r: Record) -> (folder: String, worktree: String?) {
        guard let cwd = r.cwd, !cwd.isEmpty, !cwd.contains(scratchFolderMarker) else { return (noFolder, nil) }
        if let worktree = r.worktreeName, !worktree.isEmpty, let origin = r.originCwd, !origin.isEmpty, origin != cwd {
            let repo = (origin as NSString).lastPathComponent
            if !repo.isEmpty { return (repo, worktree) }
        }
        if let range = cwd.range(of: worktreeMarker) {
            let repo = (String(cwd[..<range.lowerBound]) as NSString).lastPathComponent
            let worktree = cwd[range.upperBound...].split(separator: "/").first.map(String.init)
            if !repo.isEmpty, let worktree, !worktree.isEmpty { return (repo, worktree) }
        }
        return ((cwd as NSString).lastPathComponent, nil)
    }

    static func url(for id: String) -> URL? {
        var c = URLComponents()
        c.scheme = "claude"
        c.host = "code"
        c.path = "/continue"
        c.queryItems = [URLQueryItem(name: "session", value: id)]
        return c.url
    }

    private static func open(_ id: String) {
        guard let url = url(for: id) else { return }
        NSWorkspace.shared.open(url)
    }
}

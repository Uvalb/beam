// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SQLite3

/// Looks up tab favicons in Chrome's own favicon cache (the `Favicons` SQLite DB in
/// each profile). Chrome holds the live DB locked and keeps writing it, so we read a
/// snapshot: a copy (an APFS clone, so cheap) of the DB and its WAL, refreshed when they change.
enum Favicons {
    /// Page URL → icon, pruned to the URLs of the latest load so it can't grow forever.
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()
    private static var snapshots: [String: (stamp: String, copy: String)] = [:]

    /// Recomputed each time so profiles added while Beam runs are seen.
    private static var profileDBs: [String] {
        let root = NSHomeDirectory() + "/Library/Application Support/Google/Chrome"
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return dirs.filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .map { "\(root)/\($0)/Favicons" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Icons for the given page URLs; misses are omitted.
    static func icons(for urls: [String]) -> [String: NSImage] {
        lock.lock(); defer { lock.unlock() }
        var found: [String: NSImage] = [:]
        var missing = Set<String>()
        for u in urls {
            if let img = cache[u] { found[u] = img } else { missing.insert(u) }
        }
        cache = found
        guard !missing.isEmpty else { return found }
        for path in profileDBs where !missing.isEmpty {
            guard let snap = snapshot(path), let db = open(snap) else { continue }
            defer { sqlite3_close(db) }
            for u in missing {
                guard let img = lookup(db, url: u) else { continue }
                cache[u] = img
                found[u] = img
                missing.remove(u)
            }
        }
        return found
    }

    /// A private copy of `path` (+ `-wal`), re-copied only when either file's size or date changes.
    private static func snapshot(_ path: String) -> String? {
        let fm = FileManager.default
        let stamp = [path, path + "-wal"].map { p -> String in
            let a = try? fm.attributesOfItem(atPath: p)
            return "\((a?[.size] as? Int) ?? -1)@\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "|")
        if let s = snapshots[path], s.stamp == stamp { return s.copy }
        let dir = fm.temporaryDirectory.appendingPathComponent("beam-favicons/" + URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent).path
        let copy = dir + "/Favicons"
        try? fm.removeItem(atPath: dir)
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try fm.copyItem(atPath: path, toPath: copy)
            if fm.fileExists(atPath: path + "-wal") { try fm.copyItem(atPath: path + "-wal", toPath: copy + "-wal") }
        } catch { snapshots[path] = nil; return nil }
        snapshots[path] = (stamp, copy)
        return copy
    }

    private static func open(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        let uri = "file:\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)"
        // Read-write on our own copy so SQLite can replay the copied WAL.
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        return db
    }

    /// Chrome maps every URL in a redirect chain to the final page's icon, so a page
    /// (especially a sign-in page) can carry another site's favicon. Prefer icons served
    /// from the page's own origin: exact page, then any page on the origin; only then
    /// the exact page's foreign icon. Never borrow a foreign icon from a sibling page.
    private static func lookup(_ db: OpaquePointer, url: String) -> NSImage? {
        let base = """
        SELECT b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id
        JOIN favicons f ON f.id = m.icon_id
        WHERE %@ AND length(b.image_data) > 0
        ORDER BY (b.width <= 64) DESC, b.width DESC LIMIT 1
        """
        let exact = "m.page_url = ?1"
        guard let c = URLComponents(string: url), let scheme = c.scheme, let host = c.host else {
            return query(db, String(format: base, exact), [url])
        }
        let origin = "\(scheme)://\(host)/"
        let end = origin + "\u{FFFF}"
        // Range scans: [origin, origin + U+FFFF).
        let ownIcon = "f.url >= ?2 AND f.url < ?3"
        return query(db, String(format: base, "\(exact) AND \(ownIcon)"), [url, origin, end])
            ?? query(db, String(format: base, "m.page_url >= ?2 AND m.page_url < ?3 AND \(ownIcon)"), [url, origin, end])
            ?? query(db, String(format: base, exact), [url])
    }

    private static func query(_ db: OpaquePointer, _ sql: String, _ args: [String]) -> NSImage? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, transient) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) else { return nil }
        let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 0)))
        // Web-originated bytes, decoded in a process with Accessibility rights: keep it to
        // small bitmaps (favicons are a few KB; PNG/ICO/JPEG/GIF/BMP via NSBitmapImageRep).
        guard data.count <= 256 * 1024, let rep = NSBitmapImageRep(data: data),
              rep.pixelsWide <= 512, rep.pixelsHigh <= 512 else { return nil }
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        img.addRepresentation(rep)
        return img
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CryptoKit

// MARK: - Slack channels, people and group DMs

/// Slack desktop persists its client state (channels, members, ...) as one large IndexedDB value,
/// which Chromium stores as a standalone blob file. Reading that file directly avoids parsing LevelDB.
/// Messages are decoded with the rest but never used or shown.
enum SlackProvider {
    static let bundleID = "com.tinyspeck.slackmacgap"
    private static var blobRoot: String { SlackPaths.root + "/IndexedDB/https_app.slack.com_0.indexeddb.blob" }

    struct Entry: Equatable, Codable {
        enum Kind: Equatable, Codable { case channel, person, groupDM }
        let kind: Kind
        let title: String
        let subtitle: String
        let keys: [String]
        let url: String
        /// 0...1, from Slack's own conversation priority or how recent the last message is.
        var recency: Double = 0
        /// You're in it: a channel or group DM, or a person you have a DM with.
        var isConversation = false
        /// A person's photo URLs, preferred size first.
        var imageURLs: [String] = []
    }

    /// 48 px suits a result row and is the size Slack caches most; the rest are fallbacks.
    private static let imageSizes = ["image_48", "image_72", "image_32", "image_192", "image_512", "image_24"]

    /// A last message older than this adds nothing.
    private static let recencyWindow: TimeInterval = 90 * 24 * 60 * 60
    /// Beats any name-length tiebreak, so someone you've talked to, however long ago, ranks above a stranger.
    private static let conversationBoost = Matcher.maxLengthPenalty

    static func boost(for e: Entry) -> Int {
        guard e.isConversation else { return 0 }
        return conversationBoost + Int(e.recency * Double(Matcher.maxBoost - conversationBoost))
    }

    /// Decoding takes a few hundred ms, and the panel refreshes on every open; reuse it until the blob changes.
    private static var cache: (path: String, modified: Date, entries: [Entry])?
    /// Blobs that aren't Slack's state, so they aren't decoded again on every open.
    private static var misses: [String: (modified: Date, kind: ProviderHealth.Kind)] = [:]

    /// Reading Slack's data triggers macOS's "access data from other apps" prompt for the App Store build.
    static var needsConsent: Bool { SlackPaths.root == SlackPaths.appStore }

    /// `live: false` touches nothing of Slack's: it lists Beam's saved copy of the last read,
    /// with Slack's icon instead of photos (those are in Slack's data too) and no health check.
    static func load(live: Bool = true) -> [SearchItem] {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return [] }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        guard live else { return items(SavedEntries.read() ?? [], icon: { _ in icon }) }
        let (current, health) = currentEntries()
        let notice = ProviderHealth.record(.slack, health, appURL: appURL)
        if health.outcome == .ok, needsConsent { SavedEntries.write(current) }
        return items(current, icon: { SlackAvatars.image(for: $0.imageURLs) ?? icon }) + (notice.map { [$0] } ?? [])
    }

    private static func items(_ entries: [Entry], icon: (Entry) -> NSImage) -> [SearchItem] {
        entries.map { e in
            SearchItem(kind: .slack, title: e.title, subtitle: e.subtitle, keys: e.keys,
                       boost: boost(for: e), scope: e.kind == .channel ? .channels : .people,
                       icon: icon(e), activate: { URL(string: e.url).map { _ = NSWorkspace.shared.open($0) } })
        }
    }

    /// Beam's own copy of the last good read, in Beam's Application Support folder.
    enum SavedEntries {
        private static let lock = NSLock()
        static var path: String { NSHomeDirectory() + "/Library/Application Support/Beam/slack-entries.json" }
        private static var lastWritten: [Entry]?

        static func read() -> [Entry]? {
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return try? JSONDecoder().decode([Entry].self, from: data)
        }

        static func write(_ entries: [Entry]) {
            lock.lock(); defer { lock.unlock() }
            guard entries != lastWritten, let data = try? JSONEncoder().encode(entries) else { return }
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil { lastWritten = entries }
        }
    }

    /// The live entries plus how healthy the read was. Other IndexedDB blobs fail too, so only
    /// "blobs there, none of them Slack's state" counts as broken (decision 0015).
    private static func currentEntries() -> ([Entry], ProviderHealth.Observation) {
        if isAccessDenied(blobRoot) { return ([], .init(outcome: .noAccess)) }
        let blobs = blobsNewestFirst()
        var failures: [ProviderHealth.Kind] = []
        for (path, modified) in blobs {
            if let cache, cache.path == path, cache.modified == modified {
                return (cache.entries, .init(outcome: .ok, filesSeen: blobs.count, parsed: 1))
            }
            if let miss = misses[path], miss.modified == modified { failures.append(miss.kind); continue }
            let bytes: [UInt8]
            do { bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path))) } catch {
                // macOS may allow listing the container but refuse the read.
                if isPermissionError(error as NSError) { return ([], .init(outcome: .noAccess)) }
                // Likely mid-rewrite by Chromium: not cached as a miss, not counted as a failure.
                continue
            }
            guard let state = try? SlackCache.decode(bytes) else {
                let kind = SlackCache.failureKind(bytes)
                misses[path] = (modified, kind); failures.append(kind); continue
            }
            guard let entries = entries(from: state) else {
                misses[path] = (modified, .missingKey); failures.append(.missingKey); continue
            }
            cache = (path, modified, entries)
            SlackAvatars.forgetMisses()
            return (entries, .init(outcome: .ok, filesSeen: blobs.count, parsed: 1))
        }
        return ([], health(failures: failures))
    }

    /// The furthest any blob got: a blob that decodes but lacks Slack's keys says more than one that
    /// didn't decompress.
    static func health(failures: [ProviderHealth.Kind]) -> ProviderHealth.Observation {
        let order: [ProviderHealth.Kind] = [.missingKey, .v8, .envelope, .snappy]
        guard let kind = order.first(where: failures.contains) else { return .init(outcome: .noData) }
        return .init(outcome: .broken(kind), filesSeen: failures.count, parsed: 0)
    }

    /// The App Store Slack's container is behind macOS's "access data from other apps" consent;
    /// a denial reads as `Operation not permitted`, which would otherwise look like no data.
    static func isAccessDenied(_ path: String) -> Bool {
        do { _ = try FileManager.default.contentsOfDirectory(atPath: path); return false } catch {
            return isPermissionError(error as NSError)
        }
    }

    static func isPermissionError(_ e: NSError) -> Bool {
        if e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError { return true }
        if e.domain == NSPOSIXErrorDomain && (e.code == Int(EPERM) || e.code == Int(EACCES)) { return true }
        return (e.userInfo[NSUnderlyingErrorKey] as? NSError).map(isPermissionError) ?? false
    }

    /// Chromium may leave an older blob behind until it compacts; the newest one is the live state.
    private static func blobsNewestFirst() -> [(String, Date)] {
        guard let files = FileManager.default.enumerator(atPath: blobRoot) else { return [] }
        var result: [(String, Date)] = []
        for case let rel as String in files {
            let path = blobRoot + "/" + rel
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let modified = attrs[.modificationDate] as? Date else { continue }
            result.append((path, modified))
        }
        return result.sorted { $0.1 > $1.1 }
    }

    /// Nil when the value isn't Slack's client state (another IndexedDB blob).
    static func entries(from state: JSValue, now: Date = Date()) -> [Entry]? {
        guard let channels = state["channels"].object, let members = state["members"].object,
              let teamID = state["selfTeamIds"]["teamId"].string else { return nil }
        let selfID = state["bootData"]["user_id"].string
        let workspace = state["teams"][teamID]["name"].string ?? "Slack"

        func realName(_ m: JSValue) -> String? {
            [m["profile"]["real_name"].string, m["real_name"].string, m["name"].string]
                .compactMap { $0 }.first { !$0.isEmpty }
        }
        func isPerson(_ m: JSValue) -> Bool {
            let isGone = m["deleted"].bool == true
            let isAutomated = m["is_bot"].bool == true || m["is_slackbot"].bool == true
            return !isGone && !isAutomated
        }

        let priority = state["channelsPriority"].object ?? [:]
        let latest = state["channelLatests"].object ?? [:]
        func recency(_ id: String) -> Double {
            let slackPriority = priority[id].flatMap { if case .number(let n) = $0 { return n }; return nil } ?? 0
            let age = latest[id]?.string.flatMap(Double.init).map { now.timeIntervalSince1970 - $0 }
            let freshness = age.map { max(0, 1 - $0 / recencyWindow) } ?? 0
            return min(1, max(slackPriority, freshness))
        }

        var dmByUser: [String: (id: String, team: String)] = [:]
        var result: [Entry] = []
        for (id, c) in channels {
            guard c["is_archived"].bool != true else { continue }
            let team = c["context_team_id"].string ?? teamID
            if c["is_im"].bool == true, let user = c["user"].string {
                dmByUser[user] = (id, team)
            } else if c["is_mpim"].bool == true, let ids = c["members"].object?.values.compactMap(\.string) {
                let names = ids.filter { $0 != selfID }.compactMap { members[$0].flatMap(realName) }.sorted()
                guard !names.isEmpty else { continue }
                let title = names.joined(separator: ", ")
                result.append(Entry(kind: .groupDM, title: title, subtitle: "Group DM", keys: [title],
                                    url: channelURL(team: team, id: id), recency: recency(id), isConversation: true))
            } else if c["is_channel"].bool == true, c["is_member"].bool == true, let name = c["name"].string {
                result.append(Entry(kind: .channel, title: "#" + name, subtitle: workspace, keys: [name],
                                    url: channelURL(team: team, id: id), recency: recency(id), isConversation: true))
            }
        }
        for (id, m) in members where id != selfID && isPerson(m) {
            guard let name = realName(m) else { continue }
            let display = m["profile"]["display_name"].string ?? ""
            let jobTitle = m["profile"]["title"].string ?? ""
            let team = m["team_id"].string ?? teamID
            // A person you already talk to opens the DM; otherwise their profile, where Message is one click.
            let url = dmByUser[id].map { channelURL(team: $0.team, id: $0.id) } ?? "slack://user?team=\(team)&id=\(id)"
            result.append(Entry(kind: .person, title: name, subtitle: jobTitle.isEmpty ? workspace : jobTitle,
                                keys: [name] + (display.isEmpty || display == name ? [] : [display]), url: url,
                                recency: dmByUser[id].map { recency($0.id) } ?? 0, isConversation: dmByUser[id] != nil,
                                imageURLs: imageSizes.compactMap { m["profile"][$0].string }))
        }
        return result
    }

    private static func channelURL(team: String, id: String) -> String { "slack://channel?team=\(team)&id=\(id)" }
}

// MARK: - Profile photos from Slack's HTTP cache

/// Slack's own Chromium disk cache ("simple cache" format) already holds the photos it showed.
/// Each entry's file name derives from its URL, so a photo is one file read; nothing is downloaded.
enum SlackAvatars {
    private static var cacheDir: String { SlackPaths.root + "/Cache/Cache_Data" }
    /// Chromium prefixes cache keys with this for subresources Slack's window loaded.
    static let keyPrefix = "1/0/"
    private static let entryMagic: UInt64 = 0xFCFB_6D1B_A772_5C30
    private static let eofMagic: UInt64 = 0xF4FA_6F45_970D_41D8
    private static let keyLengthOffset = 12
    /// Magic, version, key length and key hash, padded to 8 bytes.
    private static let headerLength = 24
    private static let entryHashBytes = 8
    private static let streamFileSuffix = "_0"

    /// Photos rarely change and the panel refreshes on every open; a URL changes when the photo does.
    private static var loaded: [String: NSImage] = [:]
    /// People whose photo wasn't cached, keyed by their first URL; retried once Slack's state changes.
    private static var missing: Set<String> = []

    static func forgetMisses() { missing.removeAll() }

    static func image(for urls: [String]) -> NSImage? {
        guard let first = urls.first, !missing.contains(first) else { return nil }
        for url in urls {
            if let image = loaded[url] { return image }
            guard let entry = FileManager.default.contents(atPath: cacheDir + "/" + fileName(forKey: keyPrefix + url)),
                  let body = body(ofEntry: [UInt8](entry), key: keyPrefix + url),
                  let image = NSImage(data: Data(body)), let pixels = image.representations.first else { continue }
            // Photos with high-DPI metadata would otherwise be a few points wide; the row only scales down.
            image.size = NSSize(width: pixels.pixelsWide, height: pixels.pixelsHigh)
            loaded[url] = image
            return image
        }
        missing.insert(first)
        return nil
    }

    /// The first 8 bytes of the key's SHA-1, read as a little-endian integer, in hex.
    static func fileName(forKey key: String) -> String {
        let hash = Insecure.SHA1.hash(data: Data(key.utf8)).prefix(entryHashBytes)
        let value = hash.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return String(format: "%016llx", value) + streamFileSuffix
    }

    /// The response body: it follows the key and ends where the stream's EOF record starts.
    static func body(ofEntry b: [UInt8], key: String) -> ArraySlice<UInt8>? {
        let keyBytes = Array(key.utf8)
        guard b.count >= headerLength, uint64(b, at: 0) == entryMagic,
              Int(uint32(b, at: keyLengthOffset)) == keyBytes.count,
              b.count >= headerLength + keyBytes.count,
              Array(b[headerLength..<headerLength + keyBytes.count]) == keyBytes else { return nil }
        let start = headerLength + keyBytes.count
        guard let end = (start..<max(start, b.count - 7)).first(where: { uint64(b, at: $0) == eofMagic }), end > start else { return nil }
        return b[start..<end]
    }

    private static func uint64(_ b: [UInt8], at i: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(b[i + $1]) << (8 * $1) }
    }

    private static func uint32(_ b: [UInt8], at i: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[i + $1]) << (8 * $1) }
    }
}

// MARK: - Decoding Chromium's IndexedDB values

/// The subset of JavaScript values Slack's state uses. Integer-keyed entries (sparse arrays) get string keys.
indirect enum JSValue: Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSValue]), object([String: JSValue])

    subscript(key: String) -> JSValue { object?[key] ?? .null }
    var object: [String: JSValue]? { if case .object(let o) = self { return o }; return nil }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
}

enum SlackCache {
    struct Malformed: Error {}

    // Chromium's IndexedDB value wrapper: version tag, then "compressed with Snappy".
    private static let wrapperVersionTag: UInt8 = 0xFF
    private static let wrapperVersion: UInt8 = 0x11
    private static let snappyCompressed: UInt8 = 0x02
    private static let versionTag: UInt8 = 0xFF
    private static let blinkTrailerTag: UInt8 = 0xFE
    /// Trailer tag, then a UInt64 offset and a UInt32 size.
    private static let blinkTrailerLength = 13
    /// Slack's state is a few MB; a corrupt length must not turn into a huge allocation.
    private static let maxDecompressedBytes = 512 << 20

    static func decode(_ bytes: [UInt8]) throws -> JSValue {
        let isCompressed = bytes.count > 3 && bytes[0] == wrapperVersionTag && bytes[1] == wrapperVersion && bytes[2] == snappyCompressed
        let raw = isCompressed ? try snappy(Array(bytes[3...])) : bytes
        var r = Reader(bytes: raw)
        // Blink's envelope: its own version, an optional trailer, then V8's serialized value.
        guard try r.byte() == versionTag else { throw Malformed() }
        _ = try r.varint()
        if r.peek() == blinkTrailerTag { r.pos += blinkTrailerLength }
        var v8 = V8Deserializer(r: r)
        return try v8.value()
    }

    /// Which layer a blob that failed `decode` broke in, for a health report.
    static func failureKind(_ bytes: [UInt8]) -> ProviderHealth.Kind {
        let isCompressed = bytes.count > 3 && bytes[0] == wrapperVersionTag && bytes[1] == wrapperVersion && bytes[2] == snappyCompressed
        guard let raw = isCompressed ? try? snappy(Array(bytes[3...])) : bytes else { return .snappy }
        var r = Reader(bytes: raw)
        guard (try? r.byte()) == versionTag, (try? r.varint()) != nil else { return .envelope }
        return .v8
    }

    /// Raw Snappy block format (no framing).
    static func snappy(_ b: [UInt8]) throws -> [UInt8] {
        var r = Reader(bytes: b)
        let length = try r.varint()
        guard length <= maxDecompressedBytes else { throw Malformed() }
        var out: [UInt8] = []
        out.reserveCapacity(length)
        while r.pos < b.count {
            let tag = try r.byte()
            let lowBits = Int(tag & 3), high = Int(tag >> 2)
            if lowBits == 0 {
                var n = high
                let lengthBytesFollow = n >= 60
                if lengthBytesFollow { n = try r.littleEndian(n - 59) }
                n += 1
                guard r.pos + n <= b.count else { throw Malformed() }
                out += b[r.pos..<r.pos + n]
                r.pos += n
                continue
            }
            let n: Int, offset: Int
            switch lowBits {
            case 1: n = (high & 7) + 4; offset = (high >> 3) << 8 | Int(try r.byte())
            case 2: n = high + 1; offset = try r.littleEndian(2)
            default: n = high + 1; offset = try r.littleEndian(4)
            }
            guard offset > 0, offset <= out.count else { throw Malformed() }
            // Byte by byte: a copy may overlap the bytes it is producing.
            for _ in 0..<n { out.append(out[out.count - offset]) }
        }
        guard out.count == length else { throw Malformed() }
        return out
    }

    struct Reader {
        let bytes: [UInt8]
        var pos = 0

        func peek() -> UInt8? { pos < bytes.count ? bytes[pos] : nil }

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw Malformed() }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func varint() throws -> Int {
            var result = 0, shift = 0
            while true {
                let b = try byte()
                result |= Int(b & 0x7F) << shift
                if b < 0x80 {
                    guard result >= 0 else { throw Malformed() }
                    return result
                }
                shift += 7
                guard shift < 64 else { throw Malformed() }
            }
        }

        mutating func littleEndian(_ count: Int) throws -> Int {
            var result = 0
            for i in 0..<count { result |= Int(try byte()) << (8 * i) }
            return result
        }

        mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, n <= bytes.count - pos else { throw Malformed() }
            defer { pos += n }
            return bytes[pos..<pos + n]
        }
    }

    /// V8's ValueSerializer format, for the tags plain JSON-like state uses.
    private struct V8Deserializer {
        var r: Reader
        /// Objects by id, for back-references. A reference to one still being read resolves to null.
        var objects: [JSValue] = []
        private var depth = 0
        /// Slack's state nests about 20 levels; corrupt input must not recurse until the stack overflows.
        private let maxDepth = 64
        private let paddingTag: UInt8 = 0x00

        init(r: Reader) { self.r = r }

        private mutating func register() -> Int { objects.append(.null); return objects.count - 1 }

        private mutating func double() throws -> Double {
            Double(bitPattern: try r.take(8).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        }

        private mutating func key() throws -> String {
            switch try value() {
            case .string(let s): return s
            case .number(let n) where n.isFinite && n == n.rounded() && abs(n) < 1e15: return String(Int(n))
            default: throw Malformed()
            }
        }

        mutating func value() throws -> JSValue {
            depth += 1
            defer { depth -= 1 }
            guard depth <= maxDepth else { throw Malformed() }
            var tagByte = try r.byte()
            while tagByte == paddingTag || tagByte == versionTag {
                if tagByte == versionTag { _ = try r.varint() }
                tagByte = try r.byte()
            }
            let tag = Character(Unicode.Scalar(tagByte))
            switch tag {
            case "_", "0", "-": return .null  // undefined, null, the hole
            case "T": return .bool(true)
            case "F": return .bool(false)
            case "I": let v = try r.varint(); return .number(Double((v >> 1) ^ -(v & 1)))
            case "U": return .number(Double(try r.varint()))
            case "N": return .number(try double())
            case "\"": return .string(String(decoding: try r.take(r.varint()).map { UInt16($0) }, as: UTF16.self))
            case "c":
                let b = try r.take(r.varint())
                let units = stride(from: b.startIndex, to: b.endIndex - 1, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }
                return .string(String(decoding: units, as: UTF16.self))
            case "S": return .string(String(decoding: try r.take(r.varint()), as: UTF8.self))
            case "^":
                let id = try r.varint()
                guard id < objects.count else { throw Malformed() }
                return objects[id]
            case "D": let id = register(); objects[id] = .number(try double()); return objects[id]
            case "o", ";", "a":
                let id = register()
                if tag == "a" { _ = try r.varint() }
                let end: UInt8 = tag == "o" ? 0x7B : tag == ";" ? 0x3A : 0x40  // "{", ":", "@"
                var o: [String: JSValue] = [:]
                while r.peek() != end { let k = try key(); o[k] = try value() }
                r.pos += 1
                _ = try r.varint()
                if tag == "a" { _ = try r.varint() }
                objects[id] = .object(o)
                return objects[id]
            case "A":
                let id = register()
                let n = try r.varint()
                // Every element takes at least one byte, so a longer array is corrupt.
                guard n <= r.bytes.count - r.pos else { throw Malformed() }
                var a: [JSValue] = []
                a.reserveCapacity(n)
                for _ in 0..<n { a.append(try value()) }
                while r.peek() != 0x24 { _ = try key(); _ = try value() }  // "$"; extra named properties
                r.pos += 1
                _ = try r.varint(); _ = try r.varint()
                objects[id] = .array(a)
                return objects[id]
            case "'":
                let id = register()
                var a: [JSValue] = []
                while r.peek() != 0x2C { a.append(try value()) }  // ","
                r.pos += 1
                _ = try r.varint()
                objects[id] = .array(a)
                return objects[id]
            default:
                throw Malformed()
            }
        }
    }
}

/// Where Slack keeps its data: the direct download in Application Support, the Mac App Store build
/// in its container. The direct path is checked first so its users never see macOS's
/// "access data from other apps" prompt, which reading the container triggers.
enum SlackPaths {
    static let direct = NSHomeDirectory() + "/Library/Application Support/Slack"
    static let appStore = NSHomeDirectory() + "/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack"

    static var root: String { pick(directExists: FileManager.default.fileExists(atPath: direct)) }

    static func pick(directExists: Bool) -> String { directExists ? direct : appStore }
}

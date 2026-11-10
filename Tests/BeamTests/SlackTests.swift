// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }
/// Blink envelope (version 21, empty trailer) around V8 data (version 15).
private func envelope(_ v8: [UInt8]) -> [UInt8] { [0xFF, 0x15, 0xFE] + Array(repeating: 0, count: 12) + [0xFF, 0x0F] + v8 }

private let maxLengthVarint: [UInt8] = Array(repeating: 0xFF, count: 8) + [0x7F]
private let negativeVarint: [UInt8] = Array(repeating: 0x80, count: 9) + [0x01]
private let corruptInputs: [(String, [UInt8])] = [
    ("negative array length", ascii("A") + negativeVarint),
    ("huge array length", ascii("A") + [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x40]),
    ("string length near Int.max", ascii("\"") + maxLengthVarint),
    ("back-reference out of range", ascii("^") + negativeVarint),
    ("nesting past the limit", Array(repeating: UInt8(ascii: "o"), count: 1_000)),
]

private func person(_ name: String, display: String = "", title: String = "", extra: [String: JSValue] = [:]) -> JSValue {
    .object(["profile": .object(["real_name": .string(name), "display_name": .string(display), "title": .string(title)]),
             "team_id": .string("T1")].merging(extra) { $1 })
}

private func state(channels: [String: JSValue], members: [String: JSValue]) -> JSValue {
    .object([
        "selfTeamIds": .object(["teamId": .string("T1")]),
        "bootData": .object(["user_id": .string("U0")]),
        "teams": .object(["T1": .object(["name": .string("Acme")])]),
        "channels": .object(channels),
        "members": .object(members),
    ])
}

struct SlackDecodeTests {
    @Test func snappyLiteralAndOverlappingCopy() throws {
        // Length 8; literal "ab"; copy (1-byte offset) of 6 bytes from offset 2.
        let compressed: [UInt8] = [8, 1 << 2, 0x61, 0x62, 0b0000_1001, 2]
        #expect(try SlackCache.snappy(compressed) == ascii("abababab"))
    }

    @Test func snappyRejectsBadOffset() {
        #expect(throws: SlackCache.Malformed.self) { try SlackCache.snappy([4, 0b0000_0001, 9]) }
    }

    @Test func decodesObjectWithStringsBoolsAndNumbers() throws {
        let v8 = ascii("o\"\u{1}aT\"\u{1}bI\u{3}\"\u{1}c\"\u{2}hi{\u{3}")
        #expect(try SlackCache.decode(envelope(v8)) == .object(["a": .bool(true), "b": .number(-2), "c": .string("hi")]))
    }

    @Test func decodesSparseArrayWithIntegerKeysAndBackReference() throws {
        // { m: [ , "U1"] as sparse, r: ^1 }: object 0 is the outer object, 1 the sparse array.
        let v8 = ascii("o\"\u{1}ma\u{2}I\u{2}\"\u{2}U1@\u{1}\u{2}\"\u{1}r^\u{1}{\u{2}")
        let sparse = JSValue.object(["1": .string("U1")])
        #expect(try SlackCache.decode(envelope(v8)) == .object(["m": sparse, "r": sparse]))
    }

    @Test func decodesSnappyWrappedValue() throws {
        let raw = envelope(ascii("o\"\u{1}aF{\u{1}"))
        let literal: [UInt8] = [UInt8(raw.count), UInt8(raw.count - 1) << 2] + raw
        #expect(try SlackCache.decode([0xFF, 0x11, 0x02] + literal) == .object(["a": .bool(false)]))
    }

    @Test(arguments: corruptInputs)
    func corruptInputThrowsInsteadOfTrapping(_ name: String, _ v8: [UInt8]) {
        #expect(throws: SlackCache.Malformed.self, "\(name)") { try SlackCache.decode(envelope(v8)) }
    }

    @Test func longPaddingRunDecodes() throws {
        #expect(try SlackCache.decode(envelope(Array(repeating: 0, count: 100_000) + ascii("T"))) == .bool(true))
    }

    @Test func rejectsUnknownTag() {
        #expect(throws: SlackCache.Malformed.self) { try SlackCache.decode(envelope(ascii("?"))) }
    }
}

struct SlackEntryTests {
    @Test func notSlackStateIsNil() {
        #expect(SlackProvider.entries(from: .object(["foo": .null])) == nil)
    }

    @Test func channelsYouAreInAndNotArchived() throws {
        let s = state(channels: [
            "C1": .object(["is_channel": .bool(true), "is_member": .bool(true), "name": .string("general")]),
            "C2": .object(["is_channel": .bool(true), "is_member": .bool(false), "name": .string("random")]),
            "C3": .object(["is_channel": .bool(true), "is_member": .bool(true), "is_archived": .bool(true), "name": .string("old")]),
        ], members: [:])
        let entries = try #require(SlackProvider.entries(from: s))
        #expect(entries == [.init(kind: .channel, title: "#general", subtitle: "Acme", keys: ["general"],
                                  url: "slack://channel?team=T1&id=C1", isConversation: true)])
    }

    @Test func personOpensDMWhenOneExistsElseProfile() throws {
        let s = state(channels: [
            "D1": .object(["is_im": .bool(true), "user": .string("U1")]),
        ], members: [
            "U1": person("Dana Levi", display: "dana", title: "Engineer"),
            "U2": person("Noa Cohen", display: "Noa Cohen"),
        ])
        let entries = try #require(SlackProvider.entries(from: s)).sorted { $0.title < $1.title }
        #expect(entries == [
            .init(kind: .person, title: "Dana Levi", subtitle: "Engineer", keys: ["Dana Levi", "dana"], url: "slack://channel?team=T1&id=D1", isConversation: true),
            .init(kind: .person, title: "Noa Cohen", subtitle: "Acme", keys: ["Noa Cohen"], url: "slack://user?team=T1&id=U2"),
        ])
    }

    @Test func dmLinkUsesTheDMsTeamNotThePersons() throws {
        let s = state(channels: [
            "D1": .object(["is_im": .bool(true), "user": .string("U1"), "context_team_id": .string("T1")]),
        ], members: ["U1": person("External Dana", extra: ["team_id": .string("T9")])])
        #expect(try #require(SlackProvider.entries(from: s)).first?.url == "slack://channel?team=T1&id=D1")
    }

    @Test func skipsSelfBotsAndDeactivatedPeople() throws {
        let s = state(channels: [:], members: [
            "U0": person("Me"),
            "B1": person("Deploy Bot", extra: ["is_bot": .bool(true)]),
            "U3": person("Gone", extra: ["deleted": .bool(true)]),
            "USLACKBOT": person("Slackbot", extra: ["is_slackbot": .bool(true)]),
        ])
        #expect(try #require(SlackProvider.entries(from: s)).isEmpty)
    }

    @Test func groupDMIsTitledByOthersSorted() throws {
        let s = state(channels: [
            "G1": .object(["is_mpim": .bool(true), "members": .object(["0": .string("U0"), "1": .string("U2"), "2": .string("U1")])]),
        ], members: ["U0": person("Me"), "U1": person("Dana"), "U2": person("Noa")])
        let group = try #require(SlackProvider.entries(from: s)?.first { $0.kind == .groupDM })
        #expect(group == .init(kind: .groupDM, title: "Dana, Noa", subtitle: "Group DM", keys: ["Dana, Noa"],
                               url: "slack://channel?team=T1&id=G1", isConversation: true))
    }

    @Test func photoURLsPrefer48pxAndSkipMissingSizes() throws {
        let profile: JSValue = .object(["real_name": .string("Dana"), "image_72": .string("u72"), "image_48": .string("u48"), "image_512": .string("u512")])
        let s = state(channels: [:], members: ["U1": .object(["profile": profile])])
        #expect(try #require(SlackProvider.entries(from: s)).first?.imageURLs == ["u48", "u72", "u512"])
    }

    @Test func anyoneYouTalkedToOutranksAStranger() {
        let stale = SlackProvider.Entry(kind: .person, title: "Tal Yehoshafat", subtitle: "", keys: ["Tal Yehoshafat"], url: "", isConversation: true)
        let stranger = SlackProvider.Entry(kind: .person, title: "Tal Laks", subtitle: "", keys: ["Tal Laks"], url: "", recency: 1)
        let items = [stranger, stale].map {
            SearchItem(kind: .slack, title: $0.title, subtitle: "", keys: $0.keys, boost: SlackProvider.boost(for: $0), icon: nil, activate: {})
        }
        #expect(SearchIndex.rank(items, query: "tal").map(\.title) == ["Tal Yehoshafat", "Tal Laks"])
    }

    @Test func boostNeverExceedsTheTierCap() {
        let hottest = SlackProvider.Entry(kind: .channel, title: "", subtitle: "", keys: [], url: "", recency: 1, isConversation: true)
        #expect(SlackProvider.boost(for: hottest) <= Matcher.maxBoost)
    }

    @Test func recencyFromSlackPriorityOrLastMessage() throws {
        let now = Date(timeIntervalSince1970: 200 * 86_400)
        var s = state(channels: [
            "C1": .object(["is_channel": .bool(true), "is_member": .bool(true), "name": .string("general")]),
            "C2": .object(["is_channel": .bool(true), "is_member": .bool(true), "name": .string("old")]),
            "D1": .object(["is_im": .bool(true), "user": .string("U1")]),
        ], members: ["U1": person("Dana")])
        guard case .object(var o) = s else { return }
        o["channelsPriority"] = .object(["C1": .number(0.8)])
        // D1's last message is 45 of 90 days old; C2's is older than the window.
        o["channelLatests"] = .object(["D1": .string(String(155 * 86_400) + ".000100"), "C2": .string("1.0")])
        s = .object(o)
        let recency = Dictionary(uniqueKeysWithValues: try #require(SlackProvider.entries(from: s, now: now)).map { ($0.title, $0.recency) })
        #expect(recency["#general"] == 0.8)
        #expect(abs((recency["Dana"] ?? 0) - 0.5) < 0.001)
        #expect(recency["#old"] == 0)
    }
}

private func le(_ v: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }

struct SlackAvatarTests {
    private let key = SlackAvatars.keyPrefix + "https://ca.slack-edge.com/T1-U1-abc-48"

    private func entry(key: String, body: [UInt8]) -> [UInt8] {
        let k = Array(key.utf8)
        return le(0xFCFB_6D1B_A772_5C30, 8) + le(5, 4) + le(UInt64(k.count), 4) + le(0, 8) + k + body
            + le(0xF4FA_6F45_970D_41D8, 8) + [0, 0, 0, 0]
    }

    @Test func fileNameIsLittleEndianSHA1Prefix() {
        #expect(SlackAvatars.fileName(forKey: key) == "106ce475cd1c2ff4_0")
    }

    @Test func bodyIsBetweenKeyAndEOFRecord() {
        #expect(SlackAvatars.body(ofEntry: entry(key: key, body: [1, 2, 3]), key: key).map(Array.init) == [1, 2, 3])
    }

    @Test func rejectsEntryForAnotherKey() {
        #expect(SlackAvatars.body(ofEntry: entry(key: key + "x", body: [1]), key: key) == nil)
    }

    @Test func rejectsTruncatedEntry() {
        #expect(SlackAvatars.body(ofEntry: Array(entry(key: key, body: [1]).prefix(10)), key: key) == nil)
    }
}

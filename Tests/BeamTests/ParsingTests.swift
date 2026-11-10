// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

struct ChromeParsingTests {
    @Test(arguments: [
        ("Inbox - Part of group Work - Google Chrome", "Inbox - Google Chrome"),
        ("Inbox - Part of group Work", "Inbox"),
        ("Inbox - Part of group Q3 - Plan - Google Chrome", "Inbox - Google Chrome"),
        ("Inbox - Google Chrome", "Inbox - Google Chrome"),
        ("Notes", "Notes"),
        // Non-English Chrome localizes "Part of group", so titles pass through unchanged.
        ("Inbox - Teil der Gruppe Arbeit - Google Chrome", "Inbox - Teil der Gruppe Arbeit - Google Chrome"),
    ])
    func stripGroup(_ input: String, _ expected: String) {
        #expect(WindowProvider.stripChromeGroup(input) == expected)
    }

    @Test(arguments: [
        ("https://github.com/pulls?q=is%3Aopen#top", "github.com/pulls"),
        ("https://example.com", "example.com"),
        ("chrome://settings/", "settings/"),
        ("file:///Users/me/a.html", "/Users/me/a.html"), // empty host: path only
        ("about:blank", "about:blank"),
    ])
    func urlKey(_ input: String, _ expected: String) {
        #expect(ChromeProvider.urlKey(input) == expected)
    }

    @Test func rows() {
        let s = ChromeProvider.sep, r = ChromeProvider.rowSep
        let out = "11\(s)Inbox\(s)https://mail.com\(r)"
            + "12\(s)\(s)https://blank.com\(r)"
            + "x\(s)Bad\(s)u\(r)"              // non-numeric tab id
            + "13\(s)Short\(r)"                // too few fields
            + "14\(s)Last\(s)https://z.com"    // no trailing separator
        #expect(ChromeProvider.parseRows(out) == [
            .init(id: 11, title: "Inbox", url: "https://mail.com"),
            .init(id: 12, title: "", url: "https://blank.com"),
            .init(id: 14, title: "Last", url: "https://z.com"),
        ])
        #expect(ChromeProvider.parseRows("").isEmpty)
    }

    @Test(arguments: [
        ("group Work - 3 Tabs, expanded", "Work"),
        ("group Work - 1 Tab", "Work"),
        ("group Q3 - Plan - 2 Tabs, collapsed", "Q3 - Plan"),
        ("  group Side project - 10 Tabs", "Side project"),
        // Any language now (0011): unquoted names keep Chrome's word for "group" until it's learned.
        ("Gruppe Arbeit - 3 Tabs", "Gruppe Arbeit"),
    ])
    func groupHeader(_ title: String, _ name: String) {
        #expect(ChromeGroupProvider.parseHeader(title)?.name == name)
    }
}

struct MatcherOccurrenceTests {
    @Test func laterWordStartCounts() {
        #expect(Matcher.score("code", in: "xcode code") == Matcher.wordPrefix - 10)
        #expect(Matcher.score("code", in: "xcode") == Matcher.substring - 5)
    }
}

struct PanelTests {
    @Test(arguments: [(0, 1, 3, 1), (2, 1, 3, 0), (0, -1, 3, 2), (-1, 1, 3, 1), (-1, -1, 3, 2), (0, 1, 1, 0)])
    func wrap(_ row: Int, _ delta: Int, _ count: Int, _ expected: Int) {
        #expect(SearchPanel.wrap(row, by: delta, count: count) == expected)
    }
}

struct ShortcutTests {
    private let def = (49, 256)
    private func b(_ e: [String: Any]?) -> [Int]? {
        SystemShortcut.binding(from: e, default: def).map { [$0.0, $0.1] }
    }

    @Test func missingEntryUsesDefault() { #expect(b(nil) == [49, 256]) }
    @Test func disabled() { #expect(b(["enabled": false]) == nil) }
    @Test func noParametersUsesDefault() { #expect(b(["enabled": true, "value": [:] as [String: Any]]) == [49, 256]) }
    @Test func masksIrrelevantModifiers() {
        let fn = 1 << 23 // .function
        #expect(b(["enabled": true, "value": ["parameters": [32, 49, 1_048_576 | fn]]]) == [49, 1_048_576])
    }
}

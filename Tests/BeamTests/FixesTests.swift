// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
@testable import BeamCore

private func item(_ kind: ItemKind, _ title: String, id: String? = nil) -> SearchItem {
    SearchItem(kind: kind, title: title, subtitle: "", keys: [title], id: id, icon: nil, activate: {})
}

struct SelectionTests {
    @Test func keepsSelectedItemWhenItMoves() {
        let after = [item(.tab, "New", id: "tab|9"), item(.tab, "Docs", id: "tab|1"), item(.app, "Notes")]
        #expect(SearchIndex.keptRow("tab|1", in: after) == 1)
        #expect(SearchIndex.keptRow(item(.app, "Notes").identity, in: after) == 2)
    }

    @Test func fallsBackToTopRow() {
        let after = [item(.tab, "New", id: "tab|9")]
        #expect(SearchIndex.keptRow("tab|1", in: after) == 0)
        #expect(SearchIndex.keptRow(nil, in: after) == 0)
    }

    @Test func identityPrefersExplicitID() {
        #expect(item(.tab, "A", id: "tab|5").identity == "tab|5")
        #expect(item(.tab, "A").identity != item(.window, "A").identity)
    }
}

struct TabGroupParsingTests {
    typealias G = ChromeGroupProvider

    @Test func englishHeader() {
        #expect(G.parseHeader(" group Beam - 7 Tabs, •  Cloudflare, •  Lemon Squeezy")
                == .init(name: "Beam", count: 7, localized: false))
        #expect(G.parseHeader("group KBT - 2024 - 1 Tab") == .init(name: "KBT - 2024", count: 1, localized: false))
    }

    @Test func localizedHeaders() {
        // Real German Chrome 2026-11 (horizontal strip): the name is quoted.
        #expect(G.parseHeader(" Gruppe „Arbeit“ – 1 Tab, •  Example Domain – Erweitert")
                == .init(name: "Arbeit", count: 1, localized: false))
        #expect(G.parseHeader("Gruppe Beam – 7 Tabs, •  Stripe") == .init(name: "Gruppe Beam", count: 7, localized: true))
        // Real Hebrew Chrome 2026-11: a leading RLE mark and the count as a word.
        #expect(G.parseHeader("\u{202B} הקבוצה עבודה – כרטיסייה אחת, •  Example Domain – מורחב")
                == .init(name: "הקבוצה עבודה", count: nil, localized: true))
        #expect(G.parseHeader("הקבוצה Beam – 3 כרטיסיות") == .init(name: "הקבוצה Beam", count: 3, localized: true))
        #expect(G.parseHeader("   ") == nil)
    }

    @Test func learnsLocalizedGroupWord() {
        let r = G.dropGroupWord(["Gruppe Beam", "Gruppe Arbeit"], learned: nil)
        #expect(r.names == ["Beam", "Arbeit"] && r.word == "Gruppe")
        // One group: nothing to learn from, keep the name whole unless learned before.
        #expect(G.dropGroupWord(["Gruppe Beam"], learned: nil).names == ["Gruppe Beam"])
        #expect(G.dropGroupWord(["Gruppe Beam"], learned: "Gruppe").names == ["Beam"])
        #expect(G.memberKey(.init(name: "Gruppe Beam", count: 2, localized: true)) == "Beam")
    }

    private func n(_ kind: Character, _ title: String) -> G.Node {
        G.Node(isHeader: kind == "h", isTab: kind == "t", title: title)
    }

    @Test func verticalContainer() {
        // Vertical tabs: each group is its own container (header, spacer, member tabs).
        let nodes = [n("h", "Gruppe Work – 2 Tabs"), n("g", ""), n("t", "Mail – Teil der Gruppe Work"), n("t", "Docs – Teil der Gruppe Work")]
        let r = G.layout(nodes, name: G.memberKey)
        #expect(r.count == 1 && r[0].0 == 0 && r[0].2 == [2, 3])
    }

    @Test func flatStripStopsAtUngroupedTabs() {
        let nodes = [n("t", "Solo"), n("h", "group A - 1 Tab"), n("t", "One - Part of group A"), n("t", "Other"),
                     n("h", "group B - 2 Tabs"), n("t", "x - Part of group B"), n("t", "y - Part of group B")]
        let r = G.layout(nodes, name: G.memberKey)
        #expect(r.map { $0.1 } == ["A", "B"])
        #expect(r[0].2 == [2] && r[1].2 == [5, 6])
    }

    @Test func germanFlatStrip() {
        let nodes = [n("t", "Suche – Arbeitsspeichernutzung – 205 MB"), n("h", " Gruppe „Arbeit“ – 1 Tab, •  Example Domain – Erweitert"),
                     n("t", "Example Domain – Teil der Gruppe Arbeit – Arbeitsspeichernutzung – 32,8 MB"), n("t", "Example Domain")]
        let r = G.layout(nodes, name: G.memberKey)
        #expect(r.count == 1 && r[0].1 == "Arbeit" && r[0].2 == [2])
    }

    @Test func hebrewFlatStrip() {
        // Members say "חלק מהקבוצה עבודה": the group word is inflected, so match on the name alone.
        let h = "\u{202B} הקבוצה עבודה – כרטיסייה אחת, •  Example Domain – מורחב"
        let nodes = [n("t", "(he) - שגיאת רשת"), n("h", h), n("t", "Example Domain – חלק מהקבוצה עבודה – השימוש בזיכרון – 32.0 MB"), n("t", "Example Domain")]
        let r = G.layout(nodes, name: G.memberKey)
        #expect(r.count == 1 && r[0].2 == [2])
        #expect(G.dropGroupWord(["הקבוצה עבודה", "הקבוצה בית"], learned: nil).names == ["עבודה", "בית"])
    }

    @Test func collapsedFlatGroupHasNoMembers() {
        // A collapsed group's tabs aren't listed; the next ungrouped tab must not be taken.
        let nodes = [n("h", "group A - 3 Tabs"), n("t", "Unrelated")]
        #expect(G.layout(nodes, name: G.memberKey)[0].2.isEmpty)
    }
}

struct NormalizationTests {
    @Test func diacriticsAndCase() {
        #expect(Matcher.score("cafe", in: "Café Rouge") != nil)
        #expect(Matcher.score("ÉCOLE", in: "ecole") == Matcher.exact)
        #expect(Matcher.score("zurich", in: "Zürich") == Matcher.exact)
    }

    @Test func hebrewIgnoresNiqqud() {
        #expect(Matcher.score("שלום", in: "שָׁלוֹם עולם") != nil)
        #expect(Matcher.score("עולם", in: "שלום עולם")! >= Matcher.wordPrefix - 500)
    }

    @Test func widthAndCJK() {
        #expect(Matcher.score("safari", in: "Ｓａｆａｒｉ") == Matcher.exact)
        #expect(Matcher.score("東京", in: "東京タワー - Google") != nil)
    }

    @Test func appWatcherIgnoresBundleInternals() {
        #expect(AppWatcher.isRelevant("/Applications/"))
        #expect(AppWatcher.isRelevant("/Applications/DaVinci Resolve/"))
        #expect(!AppWatcher.isRelevant("/Applications/Google Chrome.app/Contents/Frameworks/"))
        #expect(!AppWatcher.isRelevant("/Applications/Foo.app/"))
    }

    @Test func appleScriptQuoting() {
        #expect(ChromeProvider.quoted(#"a "b" \c"#) == #""a \"b\" \\c""#)
    }
}

struct MatcherSpeedTests {
    /// Not a strict benchmark: guards against normalization making typing visibly slower.
    @Test func rankingStaysFast() {
        let titles = (0..<3000).map { i in i % 3 == 0 ? "Café número \(i) – Zürich" : i % 3 == 1 ? "שלום עולם \(i)" : "Plain tab title \(i)" }
        let items = titles.map { SearchItem(kind: .tab, title: $0, subtitle: "", keys: [$0], icon: nil, activate: {}) }
        let clock = ContinuousClock()
        let t = clock.measure { for q in ["c", "ca", "caf", "zur", "של", "plain t"] { _ = SearchIndex.rank(items, query: q) } }
        print("rank 3000 items × 6 queries: \(t)")
        #expect(t < .seconds(1))
    }
}

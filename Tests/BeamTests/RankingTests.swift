// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
@testable import BeamCore

private func item(_ kind: ItemKind, _ title: String, url: String? = nil, boost: Int = 0) -> SearchItem {
    SearchItem(kind: kind, title: title, subtitle: "", keys: [title],
               secondaryKeys: url.map { [$0] } ?? [], boost: boost, icon: nil, activate: {})
}

private func titles(_ items: [SearchItem], _ q: String, limit: Int = 9) -> [String] {
    SearchIndex.rank(items, query: q, limit: limit).map { "\($0.kind):\($0.title)" }
}

struct RankingTests {
    @Test func emptyQuery() {
        #expect(SearchIndex.rank([item(.app, "Notes")], query: "  ").isEmpty)
    }

    @Test func windowsThenTabsThenApps() {
        let items = [item(.app, "Notes"), item(.tab, "Notes"), item(.window, "Notes")]
        #expect(titles(items, "notes") == ["window:Notes", "tab:Notes", "app:Notes"])
    }

    @Test func sessionRanksWithAppsBelowTabs() {
        let items = [item(.claudeSession, "Fix login flow"), item(.app, "Finder"), item(.tab, "Finder tips")]
        #expect(titles(items, "fi") == ["tab:Finder tips", "app:Finder", "claudeSession:Fix login flow"])
    }

    @Test func appBeatsURLOnlyTab() {
        let items = [item(.tab, "Inbox", url: "github.com/pulls"), item(.app, "GitHub Desktop")]
        #expect(titles(items, "github") == ["app:GitHub Desktop", "tab:Inbox"])
    }

    @Test func urlMatchBreaksTiesWithinKind() {
        let items = [item(.tab, "Docs", url: "example.com"), item(.tab, "Docs", url: "docs.rs")]
        #expect(SearchIndex.rank(items, query: "docs").first?.secondaryKeys == ["docs.rs"])
    }

    @Test func strongBeatsFuzzyRegardlessOfKind() {
        let items = [item(.window, "Google Chrome"), item(.app, "GCH Tool")]
        #expect(titles(items, "gch") == ["app:GCH Tool", "window:Google Chrome"])
    }

    @Test func groupBelowTabEvenOnExactName() {
        let items = [item(.tabGroup, "Beam"), item(.tab, "Beam — type to jump to any app")]
        #expect(titles(items, "beam") == ["tab:Beam — type to jump to any app", "tabGroup:Beam"])
    }

    @Test func defaultOrderGroupsClosedThenAppsThenSessions() {
        let items = [item(.claudeSession, "Fin"), item(.app, "Fin"), item(.closedGroup, "Fin"), item(.tabGroup, "Fin"), item(.tab, "Fin"), item(.window, "Fin")]
        #expect(titles(items, "fin") == ["window:Fin", "tab:Fin", "tabGroup:Fin", "closedGroup:Fin", "app:Fin", "claudeSession:Fin"])
    }

    @Test func customOrderApplies() {
        let items = [item(.window, "Notes"), item(.app, "Notes"), item(.tabGroup, "Notes")]
        let order: [ItemKind] = [.app, .tabGroup, .window, .tab, .closedGroup]
        #expect(SearchIndex.rank(items, query: "notes", order: order).map { "\($0.kind)" } == ["app", "tabGroup", "window"])
    }

    @Test func customOrderLeavesFuzzyScoreFirst() {
        let items = [item(.window, "Google Chrome"), item(.app, "GCH Tool")]
        let order: [ItemKind] = [.window, .app]
        #expect(SearchIndex.rank(items, query: "gch", order: order).map(\.title) == ["GCH Tool", "Google Chrome"])
    }

    @Test func kindOrderNormalize() {
        #expect(KindOrder.normalize([]) == ItemKind.defaultOrder)
        #expect(KindOrder.normalize([0, 0, 99]) == [.app, .window, .tab, .tabGroup, .closedGroup, .bookmark, .claudeSession, .slack])
    }

    @Test func maxResultsClamp() {
        #expect(MaxResults.clamp(0) == MaxResults.range.lowerBound)
        #expect(MaxResults.clamp(100) == MaxResults.range.upperBound)
        #expect(MaxResults.clamp(12) == 12)
    }

    @Test func savedGroupTitles() {
        #expect(ChromeGroupProvider.savedGroup(fromTitle: " Finances group - Closed")?.name == "Finances")
        #expect(ChromeGroupProvider.savedGroup(fromTitle: " Beam group - Opened")?.closed == false)
        #expect(ChromeGroupProvider.savedGroup(fromTitle: "Bookmarks") == nil)
    }

    @Test func limit() {
        let items = (0..<20).map { item(.app, "App \($0)") }
        #expect(SearchIndex.rank(items, query: "app", limit: 9).count == 9)
    }

    @Test(arguments: [("(11) Inbox", "Inbox"), ("(99+) Inbox", "Inbox"), ("Inbox (3)", "Inbox (3)"), ("(x) Inbox", "(x) Inbox")])
    func stripBadge(_ input: String, _ expected: String) {
        #expect(ChromeProvider.stripBadge(input) == expected)
    }

    @Test func boostReordersWithinTierOnly() {
        let items = [item(.slack, "Alex Li"), item(.slack, "Alexandra Stone", boost: Matcher.maxBoost),
                     item(.slack, "Dana Alex", boost: Matcher.maxBoost), item(.slack, "Alex", boost: 0)]
        #expect(titles(items, "alex") == ["slack:Alex", "slack:Alexandra Stone", "slack:Alex Li", "slack:Dana Alex"])
    }

    private func slack(_ title: String, _ scope: SearchScope, boost: Int = 0) -> SearchItem {
        SearchItem(kind: .slack, title: title, subtitle: "", keys: [title], boost: boost, scope: scope, icon: nil, activate: {})
    }

    @Test func scopeParsing() {
        #expect(SearchScope.parse(" @ tal ") == (.people, "tal"))
        #expect(SearchScope.parse("#") == (.channels, ""))
        #expect(SearchScope.parse("tal") == (nil, "tal"))
    }

    @Test func slackShowsOnlyBehindItsPrefix() {
        let items = [item(.app, "Talkie"), slack("Tal Cohen", .people), slack("tal-sandbox", .channels)]
        let titles = { (q: String) in SearchIndex.search(items, query: q).map(\.title) }
        #expect(titles("@tal") == ["Tal Cohen"])
        #expect(titles("#tal") == ["tal-sandbox"])
        #expect(titles("tal") == ["Talkie"])
    }

    @Test func bareScopeListsRecentFirstAndSkipsStrangers() {
        let items = [slack("Noa", .people, boost: 600), slack("Dana", .people, boost: 1400),
                     slack("Stranger", .people), slack("general", .channels, boost: 900)]
        #expect(SearchIndex.search(items, query: "@").map(\.title) == ["Dana", "Noa"])
        #expect(SearchIndex.search(items, query: "@", limit: 1).map(\.title) == ["Dana"])
    }
}

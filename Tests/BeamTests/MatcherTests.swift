// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
@testable import BeamCore

struct MatcherTests {
    /// Each tier subtracts the target's length, so shorter targets win ties.
    @Test func tiers() {
        #expect(Matcher.score("safari", in: "Safari") == Matcher.exact)
        #expect(Matcher.score("saf", in: "Safari") == Matcher.prefix - 6)
        #expect(Matcher.score("code", in: "Visual Studio Code") == Matcher.wordPrefix - 18)
        #expect(Matcher.score("fari", in: "Safari") == Matcher.substring - 6)
        let fuzzy = Matcher.score("gch", in: "Google Chrome")!
        #expect(fuzzy > Matcher.fuzzy - 13 && fuzzy < Matcher.substring - 500)
    }

    @Test func shorterTargetWinsWithinTier() {
        #expect(Matcher.score("note", in: "Notes")! > Matcher.score("note", in: "Notes Helper")!)
    }

    @Test func fuzzyNeedsWordBoundaries() {
        #expect(Matcher.score("sfr", in: "Safari") == nil)
    }

    @Test func noMatch() {
        #expect(Matcher.score("xyz", in: "Safari") == nil)
    }

    @Test func strength() {
        #expect(Matcher.isStrong(Matcher.substring))
        #expect(!Matcher.isStrong(Matcher.score("gch", in: "Google Chrome")!))
    }
}

struct AnyOrderTests {
    @Test func wordsInAnyOrderMatchAtSubstringTier() {
        let s = Matcher.score("mobile-core", in: "core-mobile-team-devs")
        #expect(s == Matcher.substring - "core-mobile-team-devs".count)
        #expect(Matcher.score("mobile core", in: "core-mobile-team-devs") == s)
        #expect(Matcher.score("mo co", in: "core-mobile-team-devs") == s)
        #expect(Matcher.score("chrome google", in: "Google Chrome") != nil)
    }

    @Test func everyWordMustStartADifferentTargetWord() {
        #expect(Matcher.score("mobile-cor-x", in: "core-mobile-team-devs").map(Matcher.isStrong) != true)
        #expect(Matcher.score("co co", in: "core-mobile").map(Matcher.isStrong) != true)
        #expect(Matcher.score("bile core", in: "core-mobile").map(Matcher.isStrong) != true)
    }

    @Test func singleWordKeepsOrderedTiers() {
        #expect(Matcher.score("mobilecore", in: "core-mobile").map(Matcher.isStrong) != true)
    }

    @Test func inOrderMatchStillRanksFirst() {
        let inOrder = Matcher.score("mobile-core", in: "contact-mobile-core") ?? 0
        let anyOrder = Matcher.score("mobile-core", in: "core-mobile-team-devs") ?? 0
        #expect(inOrder > anyOrder)
    }
}

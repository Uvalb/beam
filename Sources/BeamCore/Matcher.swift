// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Scores a query against a target string. Higher is better; nil means no match.
/// Tiers: exact > prefix > word-prefix > substring (or all words in any order) > fuzzy (subsequence).
enum Matcher {
    static let exact = 10_000
    static let prefix = 8_000
    static let wordPrefix = 6_000
    static let substring = 4_000
    static let fuzzy = 1_000
    static let maxLengthPenalty = 500
    /// Largest `SearchItem.boost` that can reorder items within a tier but never lift one into the next.
    static let maxBoost = prefix - wordPrefix - maxLengthPenalty - 1

    /// True for substring-or-better matches (anything above the fuzzy tier).
    static func isStrong(_ score: Int) -> Bool { score >= substring - 500 }

    /// Case-, diacritic- and width-insensitive form: "Café" and "cafe" match, Hebrew niqqud is
    /// ignored, full-width "Ｓａｆａｒｉ" matches "safari". Plain ASCII (most keys) skips the folding.
    static func normalize(_ s: String) -> String {
        if s.utf8.allSatisfy({ $0 < 0x80 }) { return s.lowercased() }
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        // Folding keeps Hebrew and Arabic vowel points; titles rarely agree on them, so drop them.
        guard folded.unicodeScalars.contains(where: isPoint) else { return folded }
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { !isPoint($0) }))
    }

    private static func isPoint(_ u: Unicode.Scalar) -> Bool {
        (0x0591...0x05C7).contains(u.value) && u.value != 0x05BE && u.value != 0x05C0 && u.value != 0x05C3 && u.value != 0x05C6
            || (0x064B...0x065F).contains(u.value) || u.value == 0x0670
    }

    static func score(_ query: String, in target: String) -> Int? {
        let q = normalize(query)
        let t = normalize(target)
        guard !q.isEmpty, !t.isEmpty else { return nil }

        // Shorter targets win ties within a tier.
        let lengthPenalty = min(t.count, maxLengthPenalty)
        if t == q { return exact }
        if t.hasPrefix(q) { return prefix - lengthPenalty }
        if let first = t.range(of: q) {
            // Any occurrence at a word start counts, not just the first ("code" in "xcode code").
            var r: Range<String.Index>? = first
            while let cur = r {
                let prev = t[t.index(before: cur.lowerBound)]
                if !prev.isLetter && !prev.isNumber { return wordPrefix - lengthPenalty }
                r = t.range(of: q, range: t.index(after: cur.lowerBound)..<t.endIndex)
            }
            return substring - lengthPenalty
        }
        if allWordsMatch(q, t) { return substring - lengthPenalty }
        return fuzzyScore(q, t).map { fuzzy + $0 - lengthPenalty }
    }

    /// Slack-style: "mobile-core" finds "core-mobile-team-devs". Needs 2+ query words, each starting
    /// a different target word; a single word stays with the ordered tiers.
    private static func allWordsMatch(_ q: String, _ t: String) -> Bool {
        let queryWords = words(q)
        guard queryWords.count > 1 else { return false }
        var targetWords = words(t)
        // Longest first, so a short word can't take the only target word a longer one fits.
        for word in queryWords.sorted(by: { $0.count > $1.count }) {
            guard let i = targetWords.firstIndex(where: { $0.hasPrefix(word) }) else { return false }
            targetWords.remove(at: i)
        }
        return true
    }

    private static func words(_ s: String) -> [Substring] {
        s.split { !$0.isLetter && !$0.isNumber }
    }

    /// Subsequence match where each run of matched characters must start at a word
    /// boundary ("gch" → "Google CHrome"), so long titles don't match on scattered
    /// letters. Rewards consecutive runs.
    private static func fuzzyScore(_ q: String, _ t: String) -> Int? {
        let qc = Array(q), tc = Array(t)
        var qi = 0, score = 0, run = 0
        var prev: Character = " "
        for ch in tc {
            let boundary = !prev.isLetter && !prev.isNumber
            if qi < qc.count && ch == qc[qi] && (run > 0 || boundary) {
                run += 1
                score += 10 * run + (boundary ? 30 : 0)
                qi += 1
            } else {
                run = 0
            }
            prev = ch
        }
        return qi == qc.count ? min(score, 900) : nil
    }
}

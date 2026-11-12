// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

/// Support keeps its state in a static UserDefaults, so these run one at a time.
@Suite(.serialized)
struct SupportTests {
    init() {
        let suite = "BeamTests.Support"
        UserDefaults().removePersistentDomain(forName: suite)
        Support.d = UserDefaults(suiteName: suite)!
    }

    private func beam(_ times: Int) { for _ in 0..<times { Support.recordBeam() } }

    @Test func firstMilestone() {
        beam(99)
        #expect(Support.pillMilestone == nil)
        #expect(Support.recordBeam() == 100)
        #expect(Support.pillMilestone == 100)
    }

    @Test func pillLastsFiveBeams() {
        beam(100)
        beam(Support.pillBeams - 1)
        #expect(Support.pillMilestone == 100)
        beam(1)
        #expect(Support.pillMilestone == nil)
    }

    @Test func dismiss() {
        beam(100)
        Support.dismissPill()
        #expect(Support.pillMilestone == nil)
    }

    @Test func supporterSeesNothing() {
        Support.d.set(true, forKey: "supportIsSupporter")
        beam(99)
        #expect(Support.recordBeam() == nil)
        #expect(Support.pillMilestone == nil)
    }

    @Test func milestoneShownOnce() {
        beam(100)
        Support.d.set(50, forKey: "beamCount")
        beam(49)
        #expect(Support.recordBeam() == nil)
    }

    @Test func markSupporterStopsReminders() {
        beam(99)
        Support.markSupporter()
        #expect(Support.isSupporter)
        #expect(Support.recordBeam() == nil)
        #expect(Support.pillMilestone == nil)
    }

    private let key = "BEAM-ABCDE-FGHJK-LMNPQ-RSTUV"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func recheckDueAfterThirtyDays() {
        Support.markSupporter(key: key, now: t0)
        #expect(Support.keyDueForRecheck(now: t0.addingTimeInterval(29 * 86_400)) == nil)
        #expect(Support.keyDueForRecheck(now: t0.addingTimeInterval(30 * 86_400)) == key)
    }

    @Test func lemonSqueezyKeysAreNotRechecked() {
        Support.markSupporter(key: "38b1460a-5104-4067-a91d-77b872934d51", now: t0)
        #expect(Support.keyDueForRecheck(now: t0.addingTimeInterval(400 * 86_400)) == nil)
    }

    @Test func invalidRecheckRevokes() {
        Support.markSupporter(key: key, now: t0)
        Support.applyRecheck(.invalid)
        #expect(!Support.isSupporter)
        #expect(Support.keyDueForRecheck(now: t0.addingTimeInterval(400 * 86_400)) == nil)
    }

    @Test func offlineRecheckKeepsSupporter() {
        Support.markSupporter(key: key, now: t0)
        Support.applyRecheck(nil)
        #expect(Support.isSupporter)
    }

    @Test func validRecheckResetsClock() {
        Support.markSupporter(key: key, now: t0)
        let later = t0.addingTimeInterval(31 * 86_400)
        Support.applyRecheck(.valid, now: later)
        #expect(Support.keyDueForRecheck(now: later.addingTimeInterval(86_400)) == nil)
    }
}

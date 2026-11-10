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
}

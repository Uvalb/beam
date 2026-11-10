// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let broken = ProviderHealth.Observation(outcome: .broken(.v8), filesSeen: 2, parsed: 0)

struct ProviderHealthTests {
    @Test func okAndNoDataClearTheState() {
        let s = ProviderHealth.next(nil, broken, sourceVersion: "1", now: t0)
        #expect(s != nil)
        #expect(ProviderHealth.next(s, .init(outcome: .ok), sourceVersion: "1", now: t0) == nil)
        #expect(ProviderHealth.next(s, .init(outcome: .noData), sourceVersion: "1", now: t0) == nil)
    }

    @Test func confirmsOnlyAfterThreeLoadsAndADay() {
        var s = ProviderHealth.next(nil, broken, sourceVersion: "1", now: t0)!
        s = ProviderHealth.next(s, broken, sourceVersion: "1", now: t0 + 10)!
        s = ProviderHealth.next(s, broken, sourceVersion: "1", now: t0 + 20)!
        #expect(s.loads == 3)
        #expect(!ProviderHealth.isConfirmed(s, now: t0 + 20))
        #expect(ProviderHealth.isConfirmed(s, now: t0 + day))
    }

    @Test func otherAppUpdateRestartsTheClock() {
        var s = ProviderHealth.next(nil, broken, sourceVersion: "1", now: t0)!
        s.loads = 10
        let after = ProviderHealth.next(s, broken, sourceVersion: "2", now: t0 + 2 * day)!
        #expect(after.loads == 1)
        #expect(after.since == t0 + 2 * day)
        #expect(!ProviderHealth.isConfirmed(after, now: t0 + 2 * day))
    }

    @Test func reportHoldsOnlyVersionsAndKind() {
        let s = ProviderHealth.State(kind: "v8", sourceVersion: "4.41.105", since: t0, loads: 3, filesSeen: 2, parsed: 0)
        let body = ProviderHealth.reportBody(.slack, s, beamVersion: "0.3.0", beamBuild: "42", commit: "abc1234", macOS: "15.4.1")
        #expect(body == """
        Beam 0.3.0 (42, abc1234) · macOS 15.4.1
        Provider: slack · Kind: v8 · Source app: Slack 4.41.105
        Files seen: 2 · Parsed: 0 · Broken since: 2027-01-15
        """)
        let issue = ProviderHealth.issueURL(.slack, title: "t", body: body)!.absoluteString
        #expect(issue.hasPrefix(Support.repoURL.absoluteString + "/issues/new?"))
        #expect(issue.contains("template=provider_broken.yml"))
        #expect(issue.contains("report=Beam%200.3.0"))
        let mail = ProviderHealth.mailURL(title: "t", body: body)!.absoluteString
        #expect(mail.hasPrefix("mailto:support@beamlauncher.app?subject=t&body="))
    }

    @Test func recordShowsNoticeOnceConfirmedAndHonoursDismissal() {
        let suite = "beam.health.tests"
        ProviderHealth.d = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite); ProviderHealth.d = .standard }
        let app = URL(fileURLWithPath: "/nonexistent.app")  // version "unknown"
        #expect(ProviderHealth.record(.slack, broken, appURL: app, now: t0) == nil)
        #expect(ProviderHealth.record(.slack, broken, appURL: app, now: t0 + day / 2) == nil)
        let notice = ProviderHealth.record(.slack, broken, appURL: app, now: t0 + day)
        #expect(notice?.keys == ["slack"])
        #expect(notice?.scope == nil)
        let app2 = SearchItem(kind: .app, title: "Slack", subtitle: "", keys: ["Slack"], icon: nil, activate: {})
        #expect(SearchIndex.search([app2, notice!], query: "slack").map(ProviderHealth.isNotice) == [false, true])
        #expect(ProviderHealth.confirmed(now: t0 + day) == [.slack])
        ProviderHealth.d.set("unknown", forKey: "health.slack.dismissedVersion")
        #expect(ProviderHealth.record(.slack, broken, appURL: app, now: t0 + day) == nil)
        #expect(ProviderHealth.confirmed(now: t0 + day) == [.slack])  // Settings still shows it
        #expect(ProviderHealth.record(.slack, .init(outcome: .ok), appURL: app, now: t0 + day) == nil)
        #expect(ProviderHealth.confirmed(now: t0 + day).isEmpty)
        // A dismissed "needs access" row stays out of results; Settings still shows it.
        #expect(ProviderHealth.record(.slack, .init(outcome: .noAccess), appURL: app) != nil)
        ProviderHealth.d.set(true, forKey: ProviderHealth.accessDismissedKey(.slack))
        #expect(ProviderHealth.record(.slack, .init(outcome: .noAccess), appURL: app) == nil)
        #expect(ProviderHealth.needsAccess(.slack))
    }

    // MARK: Classification

    @Test func claudeClassifiesStoreFiles() {
        #expect(ClaudeSessionProvider.read(Data("{\"sessionId\":\"a\"}".utf8)).1 == .decoded)
        #expect(ClaudeSessionProvider.read(Data("{\"sessionId\":\"a\",\"isArchived\":true}".utf8)).1 == .decoded)
        #expect(ClaudeSessionProvider.read(Data("{\"id\":\"a\"}".utf8)).1 == .missingID)
        #expect(ClaudeSessionProvider.read(Data("nope".utf8)).1 == .malformed)
    }

    @Test func claudeHealth() {
        typealias C = ClaudeSessionProvider
        #expect(C.health(statuses: [], anyEntry: false).outcome == .noData)
        #expect(C.health(statuses: [], anyEntry: true).outcome == .broken(.layoutChanged))
        #expect(C.health(statuses: [.malformed, .decoded], anyEntry: true).outcome == .ok)
        #expect(C.health(statuses: [.malformed, .missingID], anyEntry: true).outcome == .broken(.missingField))
        #expect(C.health(statuses: [.malformed], anyEntry: true).outcome == .broken(.decodeFailed))
    }

    @Test func claudeScanOfARealFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        // Empty folders and Finder's .DS_Store are not a changed layout (never used Claude Code).
        try Data().write(to: root.appendingPathComponent(".DS_Store"))
        #expect(ClaudeSessionProvider.scan(root.path).health.outcome == .noData)
        try Data().write(to: root.appendingPathComponent("a/session.db"))
        #expect(ClaudeSessionProvider.scan(root.path).health.outcome == .broken(.layoutChanged))
        try FileManager.default.removeItem(at: root.appendingPathComponent("a/session.db"))
        try Data("{\"renamed\":1}".utf8).write(to: root.appendingPathComponent("a/b/local_1.json"))
        #expect(ClaudeSessionProvider.scan(root.path).health == .init(outcome: .broken(.missingField), filesSeen: 1, parsed: 0))
        #expect(ClaudeSessionProvider.scan(root.path + "/missing").health.outcome == .noData)
    }

    @Test func slackFailureKinds() {
        #expect(SlackCache.failureKind([0xFF, 0x11, 0x02, 0x05, 0x01]) == .snappy)
        #expect(SlackCache.failureKind(Array("?".utf8)) == .envelope)
        #expect(SlackCache.failureKind([0xFF, 0x0F, 0x3F]) == .v8)
    }

    @Test func slackHealthPicksFurthestFailure() {
        #expect(SlackProvider.health(failures: []).outcome == .noData)
        #expect(SlackProvider.health(failures: [.snappy, .missingKey]).outcome == .broken(.missingKey))
        #expect(SlackProvider.health(failures: [.envelope, .v8]).outcome == .broken(.v8))
    }

    @Test func slackAccessDenialIsNotNoData() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        #expect(SlackProvider.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: posix])))
        #expect(SlackProvider.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)))
        #expect(!SlackProvider.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        #expect(!SlackProvider.isAccessDenied(NSTemporaryDirectory() + "/beam-missing-\(UUID())"))
        #expect(ProviderHealth.next(nil, .init(outcome: .noAccess), sourceVersion: "1", now: Date()) == nil)
    }
}

@Suite struct ReviewFixTests {
    let tab = SearchItem(kind: .tab, title: "Issue #1234", subtitle: "", keys: ["Issue #1234"], icon: nil, activate: {})

    @Test func hashIsPlainTextWithoutSlack() {
        #expect(SearchIndex.search([tab], query: "#1234").map(\.title) == ["Issue #1234"])
    }

    @Test func hashScopesWhenSlackIsLoaded() {
        let ch = SearchItem(kind: .slack, title: "general", subtitle: "", keys: ["general"], scope: .channels, icon: nil, activate: {})
        #expect(SearchIndex.search([tab, ch], query: "#gen").map(\.title) == ["general"])
    }

    @Test func staleGroupWordIsForgotten() {
        #expect(ChromeGroupProvider.learnGroupWord(["Gruppe Arbeit"], stored: "הקבוצה") == nil)
        #expect(ChromeGroupProvider.learnGroupWord(["הקבוצה עבודה"], stored: "הקבוצה") == "הקבוצה")
        #expect(ChromeGroupProvider.learnGroupWord([], stored: "הקבוצה") == "הקבוצה")
    }
}

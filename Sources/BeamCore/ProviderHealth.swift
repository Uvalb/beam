// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Notices when a provider that reads another app's undocumented data stops working, and lets the
/// user report it (decision 0015). Nothing is sent by Beam: a report is a GitHub issue or an email
/// the user opens themselves, holding only versions, the provider and a failure kind.
enum ProviderHealth {
    enum Provider: String, CaseIterable {
        case claudeSessions = "claude-sessions", slack

        var appName: String { self == .slack ? "Slack" : "Claude" }
        var resultsName: String { self == .slack ? "Slack results" : "Claude Code sessions" }
        var bundleID: String { self == .slack ? SlackProvider.bundleID : ClaudeSessionProvider.bundleID }
        var keys: [String] { self == .slack ? ["slack"] : ["claude", "claude code sessions"] }
        var itemKind: ItemKind { self == .slack ? .slack : .claudeSession }
    }

    /// A closed list, so a report can never carry free text from the other app's data.
    enum Kind: String {
        case decodeFailed = "decode-failed", missingField = "missing-field", layoutChanged = "layout-changed"
        case snappy, envelope, v8, missingKey = "missing-key"
    }

    /// `noData` (nothing to read) is never a failure: the user may simply not use the app.
    /// `noAccess` is macOS refusing the read (the user denied "access data from other apps"): not a
    /// bug to report, and macOS won't ask again, so it's shown at once with a way to fix it.
    enum Outcome: Equatable { case ok, noData, noAccess, broken(Kind) }

    struct Observation: Equatable {
        var outcome: Outcome
        var filesSeen = 0
        var parsed = 0
    }

    /// A failure that has lasted; persisted per provider.
    struct State: Codable, Equatable {
        var kind: String
        var sourceVersion: String
        var since: Date
        var loads: Int
        var filesSeen: Int
        var parsed: Int
    }

    /// Gentle and rare: only a failure seen on several loads over a day, on one version of the other app.
    static let minLoads = 3
    static let minDuration: TimeInterval = 24 * 60 * 60

    static func next(_ state: State?, _ obs: Observation, sourceVersion: String, now: Date) -> State? {
        guard case .broken(let kind) = obs.outcome else { return nil }
        // An update of the other app restarts the clock: it may have fixed (or changed) things.
        guard var s = state, s.sourceVersion == sourceVersion else {
            return State(kind: kind.rawValue, sourceVersion: sourceVersion, since: now, loads: 1, filesSeen: obs.filesSeen, parsed: obs.parsed)
        }
        s.loads += 1
        s.kind = kind.rawValue
        s.filesSeen = obs.filesSeen
        s.parsed = obs.parsed
        return s
    }

    static func isConfirmed(_ s: State, now: Date) -> Bool {
        s.loads >= minLoads && now.timeIntervalSince(s.since) >= minDuration
    }

    // MARK: Storage

    static var d = UserDefaults.standard
    private static let lock = NSLock()
    private static func stateKey(_ p: Provider) -> String { "health.\(p.rawValue)" }
    private static func dismissedKey(_ p: Provider) -> String { "health.\(p.rawValue).dismissedVersion" }
    private static func noAccessKey(_ p: Provider) -> String { "health.\(p.rawValue).noAccess" }
    /// The user chose not to grant access: no "needs access" row in results (Settings still shows it).
    static func accessDismissedKey(_ p: Provider) -> String { "health.\(p.rawValue).accessDismissed" }

    /// The last load was refused by macOS.
    static func needsAccess(_ p: Provider) -> Bool { d.bool(forKey: noAccessKey(p)) }

    static func state(_ p: Provider) -> State? {
        d.data(forKey: stateKey(p)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
    }

    /// Records one load and returns the result row to show in its place when the failure is confirmed
    /// and not dismissed for this version of the other app; nil otherwise.
    @discardableResult
    static func record(_ p: Provider, _ obs: Observation, appURL: URL, now: Date = Date()) -> SearchItem? {
        let version = sourceVersion(appURL)
        lock.lock(); defer { lock.unlock() }
        var obs = obs, previous = state(p)
        // For trying the flow by hand: `defaults write com.beam.launcher BeamSimulateBrokenProvider slack`
        // (or claude-sessions) makes that provider read as broken, already a day old.
        if d.string(forKey: "BeamSimulateBrokenProvider") == p.rawValue {
            obs = Observation(outcome: .broken(p == .slack ? .v8 : .decodeFailed), filesSeen: obs.filesSeen, parsed: 0)
            if previous?.sourceVersion != version {
                previous = State(kind: "", sourceVersion: version, since: now - minDuration, loads: minLoads - 1, filesSeen: 0, parsed: 0)
            }
        }
        if obs.outcome == .noAccess { d.set(true, forKey: noAccessKey(p)) } else { d.removeObject(forKey: noAccessKey(p)) }
        // A denial isn't a parsing failure: drop any broken state it caused before it was detected.
        if obs.outcome == .noAccess {
            d.removeObject(forKey: stateKey(p))
            return d.bool(forKey: accessDismissedKey(p)) ? nil : accessNotice(p)
        }
        let s = next(previous, obs, sourceVersion: version, now: now)
        if let s, let data = try? JSONEncoder().encode(s) { d.set(data, forKey: stateKey(p)) } else { d.removeObject(forKey: stateKey(p)) }
        guard let s, isConfirmed(s, now: now), d.string(forKey: dismissedKey(p)) != version else { return nil }
        return notice(p)
    }

    /// Confirmed failures, dismissed or not, for Settings.
    static func confirmed(now: Date = Date()) -> [Provider] {
        Provider.allCases.filter { state($0).map { isConfirmed($0, now: now) } ?? false }
    }

    static func sourceVersion(_ appURL: URL) -> String {
        Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static func notice(_ p: Provider) -> SearchItem {
        SearchItem(kind: p.itemKind, title: "\(p.resultsName) stopped working",
                   subtitle: "Probably after a \(p.appName) update. Press Return to report it.",
                   keys: p.keys, id: "health.\(p.rawValue)",
                   icon: warningIcon,
                   activate: { DispatchQueue.main.async { showReport(p) } })
    }

    private static func accessNotice(_ p: Provider) -> SearchItem {
        SearchItem(kind: p.itemKind, title: "\(p.resultsName) need access",
                   subtitle: "macOS is blocking Beam from reading \(p.appName). Press Return to fix it.",
                   keys: p.keys, id: "health.\(p.rawValue).access",
                   icon: warningIcon,
                   activate: { DispatchQueue.main.async { showAccessHelp(p) } })
    }

    static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// macOS asks "access data from other apps" only once; after a denial the only way back is
    /// System Settings. Full Disk Access covers other apps' containers and has a pane we can open.
    @MainActor
    static func showAccessHelp(_ p: Provider) {
        let alert = NSAlert()
        alert.messageText = "Let Beam read \(p.appName)"
        alert.informativeText = "macOS stopped Beam from reading \(p.appName)’s data (the App Store \(p.appName) keeps it in its own container), and it won’t ask again.\n\nIn System Settings, turn on Beam Launcher under Full Disk Access, then quit and reopen Beam. Beam only reads the names of your \(p.appName) channels and people, and nothing leaves your Mac."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t show this in results again"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { d.set(true, forKey: accessDismissedKey(p)) }
        if response == .alertFirstButtonReturn { NSWorkspace.shared.open(fullDiskAccessURL) }
    }

    static func isNotice(_ item: SearchItem) -> Bool { item.id?.hasPrefix("health.") == true }

    private static let warningIcon: NSImage? = {
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Stopped working")?
            .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        image?.isTemplate = false
        return image
    }()

    // MARK: Report

    static let reportEmail = "support@beamlauncher.app"

    /// Built only from versions, the provider and the closed `Kind`: never titles, names or paths.
    static func reportBody(_ p: Provider, _ s: State, beamVersion: String, beamBuild: String, commit: String, macOS: String) -> String {
        let day = ISO8601DateFormatter.string(from: s.since, timeZone: .gmt, formatOptions: [.withFullDate])
        return """
        Beam \(beamVersion) (\(beamBuild), \(commit)) · macOS \(macOS)
        Provider: \(p.rawValue) · Kind: \(s.kind) · Source app: \(p.appName) \(s.sourceVersion)
        Files seen: \(s.filesSeen) · Parsed: \(s.parsed) · Broken since: \(day)
        """
    }

    static func reportTitle(_ p: Provider, _ s: State) -> String {
        "\(p.resultsName) stopped working (\(p.appName) \(s.sourceVersion), \(s.kind))"
    }

    static func issueURL(_ p: Provider, title: String, body: String) -> URL? {
        var c = URLComponents(url: Support.repoURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        // The template applies the `provider-broken` label for anyone; a `labels=` parameter only
        // works for people with triage rights.
        c?.queryItems = [URLQueryItem(name: "template", value: "provider_broken.yml"),
                         URLQueryItem(name: "title", value: title), URLQueryItem(name: "report", value: body),
                         // Fills a blank issue when the template isn't there (e.g. not on main yet).
                         URLQueryItem(name: "body", value: body)]
        return c?.url
    }

    static func mailURL(title: String, body: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = reportEmail
        c.queryItems = [URLQueryItem(name: "subject", value: title), URLQueryItem(name: "body", value: body)]
        return c.url
    }

    private static func currentBody(_ p: Provider, _ s: State) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return reportBody(p, s, beamVersion: info["CFBundleShortVersionString"] as? String ?? "?",
                          beamBuild: info["CFBundleVersion"] as? String ?? "?",
                          commit: info["BeamCommit"] as? String ?? "unknown",
                          macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }

    /// Shows exactly what would be sent, then opens it where the user picks. Email is offered too:
    /// it shares the user's address, which lets the maintainer follow up, but that's their choice.
    @MainActor
    static func showReport(_ p: Provider) {
        guard let s = state(p) else { return }
        let title = reportTitle(p, s), body = currentBody(p, s)
        let alert = NSAlert()
        alert.messageText = "\(p.resultsName) stopped working"
        alert.informativeText = "Beam reads \(p.appName)’s own files, which \(p.appName) can change in any update. A report helps fix it. It holds only this, nothing from your \(p.appName):"
        let text = NSTextField(wrappingLabelWithString: body)
        text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        text.frame.size = NSSize(width: 420, height: 60)
        alert.accessoryView = text
        alert.addButton(withTitle: "Open GitHub Issue")
        alert.addButton(withTitle: "Email…")
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t show this again for \(p.appName) \(s.sourceVersion)"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { d.set(s.sourceVersion, forKey: dismissedKey(p)) }
        switch response {
        case .alertFirstButtonReturn: issueURL(p, title: title, body: body).map { _ = NSWorkspace.shared.open($0) }
        case .alertSecondButtonReturn: mailURL(title: title, body: body).map { _ = NSWorkspace.shared.open($0) }
        case .alertThirdButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(title + "\n\n" + body, forType: .string)
        default: break
        }
    }
}

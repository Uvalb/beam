// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Local-only usage counter and the gentle "consider supporting Beam" nudge.
/// State lives in UserDefaults. Network requests are only the optional Sparkle update check and the license check (Licensing.swift): once when a key is entered, then about monthly for beamlauncher.app keys so a refunded key stops counting.
enum Support {
    /// The website and source repo, linked from About. `from=app` tells the site not to start a download.
    static let websiteURL = URL(string: "https://beamlauncher.app/?from=app")!
    static let repoURL = URL(string: "https://github.com/Uvalb/beam")!
    /// The website's support section.
    static let supportURL = URL(string: "https://beamlauncher.app/?from=app#support")!

    static let milestones = [100, 1_000, 5_000, 10_000, 25_000, 50_000, 100_000]
    /// The pill stays for this many beams after a milestone (e.g. 100–105).
    static let pillBeams = 5

    private enum Key {
        static let count = "beamCount"
        static let lastMilestoneShown = "supportLastMilestoneShown"
        static let pillUntil = "supportPillUntil"
        static let pillMilestone = "supportPillMilestone"
        static let supporter = "supportIsSupporter"
        static let license = "supportLicense"
        static let beamKey = "supportBeamKey"
        static let lastCheck = "supportLicenseLastCheck"
    }

    /// Swappable so tests can use a throwaway suite.
    static var d: UserDefaults = .standard

    static var count: Int { d.integer(forKey: Key.count) }
    static var isSupporter: Bool { d.bool(forKey: Key.supporter) }
    static var license: LicenseInfo? { LicenseInfo(dictionary: d.dictionary(forKey: Key.license)) }
    /// Lemon Squeezy's customer portal: receipts, and managing a yearly plan.
    static let ordersURL = URL(string: "https://link.com")! // Stripe Managed Payments: orders, receipts and cancelling live on Link

    /// Call once per successful beam. Returns the milestone if this beam reached one.
    @discardableResult
    static func recordBeam() -> Int? {
        let n = count + 1
        d.set(n, forKey: Key.count)
        guard !isSupporter, milestones.contains(n), n > d.integer(forKey: Key.lastMilestoneShown) else { return nil }
        d.set(n, forKey: Key.lastMilestoneShown)
        d.set(n, forKey: Key.pillMilestone)
        d.set(n + pillBeams, forKey: Key.pillUntil)
        return n
    }

    /// The milestone to show in the pill, while within its beam window.
    static var pillMilestone: Int? {
        guard !isSupporter, count < d.integer(forKey: Key.pillUntil) else { return nil }
        let m = d.integer(forKey: Key.pillMilestone)
        return m > 0 ? m : nil
    }

    /// Every "Support Beam" entry point lands here.
    static func openDonatePage() {
        dismissPill()
        NSWorkspace.shared.open(supportURL)
    }

    /// `beam://license?key=…` (or plain `beam://license`) from the website's thank-you page.
    /// Returns the key if present, "" for no key, nil if it isn't a license link.
    static func licenseKey(fromURL url: URL) -> String? {
        guard url.scheme == "beam", url.host == "license" else { return nil }
        let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "key" }?.value ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Called once a license key checks out. Reminders stop for good.
    /// A beamlauncher.app key is kept whole so it can be re-checked; Lemon Squeezy keys never are.
    static func markSupporter(_ info: LicenseInfo? = nil, key: String? = nil, now: Date = Date()) {
        d.set(true, forKey: Key.supporter)
        if let info { d.set(info.dictionary, forKey: Key.license) }
        if let key = key?.uppercased(), Licensing.isBeamKey(key) { d.set(key, forKey: Key.beamKey) }
        d.set(now.timeIntervalSince1970, forKey: Key.lastCheck)
        dismissPill()
    }

    static let recheckInterval: TimeInterval = 30 * 86_400

    /// The stored key, when a re-check is due.
    static func keyDueForRecheck(now: Date = Date()) -> String? {
        guard isSupporter, let key = d.string(forKey: Key.beamKey) else { return nil }
        return now.timeIntervalSince1970 - d.double(forKey: Key.lastCheck) >= recheckInterval ? key : nil
    }

    /// Applies a re-check's answer. Only a definite "invalid" (refunded or charged back) revokes;
    /// offline or odd answers change nothing, so being offline never costs anyone their badge.
    static func applyRecheck(_ result: LicenseResult?, info: LicenseInfo? = nil, now: Date = Date()) {
        switch result {
        case .valid?:
            if let info { d.set(info.dictionary, forKey: Key.license) }
            d.set(now.timeIntervalSince1970, forKey: Key.lastCheck)
        case .invalid?:
            for k in [Key.supporter, Key.license, Key.beamKey, Key.lastCheck] { d.removeObject(forKey: k) }
        default: break
        }
    }

    /// Called at launch; does nothing unless a check is due.
    static func recheckIfDue() async {
        guard let key = keyDueForRecheck() else { return }
        let answer = try? await LicenseCheck.runBeam(key: key, session: .shared)
        applyRecheck(answer?.0, info: answer?.1)
    }

    static func dismissPill() { d.set(0, forKey: Key.pillUntil) }

    static func formatted(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

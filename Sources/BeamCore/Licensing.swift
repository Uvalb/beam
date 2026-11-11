// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The one-time license key check. Picking an amount and paying happen on the website
/// (no in-app funnel to measure, no telemetry); this file only checks the emailed key.
/// `Licensing.parse` is tested; `LicenseCheck.run` is one of Beam's two kinds of request (the other is Sparkle's update check).
enum LicenseResult: Equatable {
    case valid
    case invalid          // unknown, disabled or expired key
    case testKey          // a test-mode key while live keys are required
    case wrongProduct     // a valid key from some other store
}

enum Licensing {
    static let validateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!
    /// Keys issued by beamlauncher.app after a Stripe checkout look like BEAM-XXXXX-XXXXX-XXXXX-XXXXX
    /// and are checked there. `defaults write com.beam.launcher BeamValidateURL <url>` points at a
    /// preview deployment for testing; a key only marks someone as a supporter, so there's nothing to protect.
    static var beamValidateURL: URL {
        UserDefaults.standard.string(forKey: "BeamValidateURL").flatMap(URL.init(string:))
            ?? URL(string: "https://beamlauncher.app/api/validate")!
    }
    static func isBeamKey(_ key: String) -> Bool {
        key.range(of: #"^BEAM(-[2-9A-HJ-NP-Z]{5}){4}$"#, options: .regularExpression) != nil
    }
    static let timeout: TimeInterval = 10
    /// Test-mode keys are free to make in any Lemon Squeezy store, so only debug builds accept them.
    #if DEBUG
    static let acceptTestKeys = true
    #else
    static let acceptTestKeys = false
    #endif
    /// Beam's Lemon Squeezy store ID, so valid keys from other stores don't count.
    static let expectedStoreID: Int? = 509476

    /// Interprets the validate response. Returns nil if it isn't the JSON we expect.
    static func parse(_ data: Data, acceptTestKeys: Bool = acceptTestKeys,
                      expectedStoreID: Int? = expectedStoreID) -> LicenseResult? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let valid = json["valid"] as? Bool else { return nil }
        guard valid else { return .invalid }
        let key = json["license_key"] as? [String: Any]
        if let status = key?["status"] as? String, status == "disabled" || status == "expired" { return .invalid }
        if let expected = expectedStoreID, (json["meta"] as? [String: Any])?["store_id"] as? Int != expected {
            return .wrongProduct
        }
        if !acceptTestKeys, key?["test_mode"] as? Bool == true { return .testKey }
        return .valid
    }

    /// Interprets beamlauncher.app's answer: {"valid": bool, "test": bool, "plan": "y12"}.
    static func parseBeam(_ data: Data, acceptTestKeys: Bool = acceptTestKeys) -> LicenseResult? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let valid = json["valid"] as? Bool else { return nil }
        guard valid else { return .invalid }
        if !acceptTestKeys, json["test"] as? Bool == true { return .testKey }
        return .valid
    }
}

/// What About shows for a supporter. Only the key's last characters are kept.
struct LicenseInfo: Equatable {
    var keyEnding: String
    var plan: String      // e.g. "Beam Launcher Supporter (yearly) – $12"
    var email: String
    var testMode: Bool

    static func from(_ data: Data, key: String) -> LicenseInfo {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let meta = json?["meta"] as? [String: Any]
        let lk = json?["license_key"] as? [String: Any]
        let plan = [meta?["product_name"], meta?["variant_name"]].compactMap { $0 as? String }
            .filter { !$0.isEmpty && $0 != "Default" }.joined(separator: " – ")
        return LicenseInfo(keyEnding: String(key.suffix(4)), plan: plan,
                           email: meta?["customer_email"] as? String ?? "",
                           testMode: lk?["test_mode"] as? Bool ?? false)
    }

    var dictionary: [String: Any] { ["keyEnding": keyEnding, "plan": plan, "email": email, "testMode": testMode] }
    init(keyEnding: String, plan: String, email: String, testMode: Bool) {
        self.keyEnding = keyEnding; self.plan = plan; self.email = email; self.testMode = testMode
    }
    init?(dictionary d: [String: Any]?) {
        guard let d, let k = d["keyEnding"] as? String else { return nil }
        self.init(keyEnding: k, plan: d["plan"] as? String ?? "", email: d["email"] as? String ?? "",
                  testMode: d["testMode"] as? Bool ?? false)
    }
}

enum LicenseError: Error { case offline, unexpected }

enum LicenseCheck {
    /// Asks Lemon Squeezy once whether the key is valid. Needs no secret. We use
    /// `validate` (not `activate`) because it changes nothing server-side. The key is never logged.
    static func run(key: String, session: URLSession = .shared) async throws -> (LicenseResult, LicenseInfo) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if Licensing.isBeamKey(key.uppercased()) { return try await runBeam(key: key.uppercased(), session: session) }
        var req = URLRequest(url: Licensing.validateURL, timeoutInterval: Licensing.timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "license_key", value: key)]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let data: Data
        do { (data, _) = try await session.data(for: req) } catch { throw LicenseError.offline }
        // Unknown keys come back as 404 with {"valid": false}, so parse before judging the status.
        if let result = Licensing.parse(data) { return (result, LicenseInfo.from(data, key: key)) }
        throw LicenseError.unexpected
    }

    /// Same one-time check for keys from beamlauncher.app (Stripe checkout).
    static func runBeam(key: String, session: URLSession) async throws -> (LicenseResult, LicenseInfo) {
        var req = URLRequest(url: Licensing.beamValidateURL, timeoutInterval: Licensing.timeout)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "key", value: key)]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let data: Data
        do { (data, _) = try await session.data(for: req) } catch { throw LicenseError.offline }
        guard let result = Licensing.parseBeam(data) else { throw LicenseError.unexpected }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let plan = Licensing.planName(json?["plan"] as? String)
        return (result, LicenseInfo(keyEnding: String(key.suffix(4)), plan: plan, email: "",
                                    testMode: json?["test"] as? Bool ?? false))
    }
}

extension Licensing {
    static func planName(_ code: String?) -> String {
        switch code {
        case "y12": return "Supporter (yearly) – $12"
        case "y24": return "Supporter (yearly) – $24"
        case "y60": return "Supporter (yearly) – $60"
        case "once": return "Supporter (one-time)"
        default: return "Supporter"
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security

/// Who signed the running app. Ad-hoc (`make run`) builds have no team ID.
enum CodeSigning {
    /// Beam's Developer ID team. Forks: change this along with `SUFeedURL` and `SUPublicEDKey`.
    static let officialTeamID = "P9GCM9K6AH"

    static func teamID() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

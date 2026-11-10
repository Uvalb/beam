// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

struct LicensingTests {
    private func parse(_ json: String, test: Bool = true, store: Int? = nil) -> LicenseResult? {
        Licensing.parse(Data(json.utf8), acceptTestKeys: test, expectedStoreID: store)
    }

    @Test func licenseLinks() {
        #expect(Support.licenseKey(fromURL: URL(string: "beam://license?key=ABC-123")!) == "ABC-123")
        #expect(Support.licenseKey(fromURL: URL(string: "beam://license")!) == "")
        #expect(Support.licenseKey(fromURL: URL(string: "beam://other?key=x")!) == nil)
        #expect(Support.licenseKey(fromURL: URL(string: "https://license?key=x")!) == nil)
    }

    @Test func validKey() {
        #expect(parse(#"{"valid":true,"license_key":{"status":"active","test_mode":false}}"#) == .valid)
    }

    @Test func invalidKey() {
        #expect(parse(#"{"valid":false,"error":"license_key not found."}"#) == .invalid)
        #expect(parse(#"{"valid":true,"license_key":{"status":"disabled"}}"#) == .invalid)
    }

    @Test func testModeKey() {
        let json = #"{"valid":true,"license_key":{"status":"active","test_mode":true}}"#
        #expect(parse(json, test: true) == .valid)
        #expect(parse(json, test: false) == .testKey)
    }

    @Test func otherStore() {
        let json = #"{"valid":true,"license_key":{"status":"active"},"meta":{"store_id":9}}"#
        #expect(parse(json, store: 9) == .valid)
        #expect(parse(json, store: 1) == .wrongProduct)
    }

    @Test func garbage() {
        #expect(parse("<html>") == nil)
        #expect(parse("{}") == nil)
    }

    @Test func licenseInfo() {
        let json = #"{"valid":true,"license_key":{"status":"active","test_mode":true},"meta":{"product_name":"Beam Launcher Supporter (yearly)","variant_name":"$12","customer_email":"a@b.c"}}"#
        let info = LicenseInfo.from(Data(json.utf8), key: "ABCD-1234")
        #expect(info == LicenseInfo(keyEnding: "1234", plan: "Beam Launcher Supporter (yearly) – $12", email: "a@b.c", testMode: true))
        #expect(LicenseInfo(dictionary: info.dictionary) == info)
    }
}

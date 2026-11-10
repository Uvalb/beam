// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

struct LicensingEdgeTests {
    private func parse(_ json: String, store: Int? = nil) -> LicenseResult? {
        Licensing.parse(Data(json.utf8), acceptTestKeys: true, expectedStoreID: store)
    }

    @Test func expired() {
        #expect(parse(#"{"valid":true,"license_key":{"status":"expired"}}"#) == .invalid)
    }

    @Test func missingMetaWhenStoreExpected() {
        #expect(parse(#"{"valid":true,"license_key":{"status":"active"}}"#, store: 9) == .wrongProduct)
    }

    @Test func defaultVariantDropped() {
        let json = #"{"meta":{"product_name":"Beam","variant_name":"Default"}}"#
        #expect(LicenseInfo.from(Data(json.utf8), key: "AB").plan == "Beam")
        #expect(LicenseInfo.from(Data(json.utf8), key: "AB").keyEnding == "AB")
    }

    @Test func infoFromGarbage() {
        #expect(LicenseInfo.from(Data("<html>".utf8), key: "K") == LicenseInfo(keyEnding: "K", plan: "", email: "", testMode: false))
        #expect(LicenseInfo(dictionary: nil) == nil)
        #expect(LicenseInfo(dictionary: ["plan": "x"]) == nil)
    }
}

/// Serves canned responses to LicenseCheck without touching the network.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data)?)?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        guard let (status, data) = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func read(_ s: InputStream) -> Data {
        s.open(); defer { s.close() }
        var d = Data(), buf = [UInt8](repeating: 0, count: 1024)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
        return d
    }
}

@Suite(.serialized)
struct LicenseCheckTests {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }()

    @Test func validKeyAndFormBody() async throws {
        let store = Licensing.expectedStoreID ?? 0
        StubProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url == Licensing.validateURL)
            return (200, Data(#"{"valid":true,"license_key":{"status":"active","test_mode":false},"meta":{"store_id":\#(store),"customer_email":"a@b.c"}}"#.utf8))
        }
        let (result, info) = try await LicenseCheck.run(key: "AB+C 1234", session: session)
        #expect(result == .valid)
        #expect(info.keyEnding == "1234")
        #expect(info.email == "a@b.c")
        #expect(String(decoding: StubProtocol.lastBody ?? Data(), as: UTF8.self) == "license_key=AB+C%201234"
                || String(decoding: StubProtocol.lastBody ?? Data(), as: UTF8.self) == "license_key=AB%2BC%201234")
    }

    @Test func notFoundStillParsed() async throws {
        StubProtocol.handler = { _ in (404, Data(#"{"valid":false,"error":"license_key not found."}"#.utf8)) }
        #expect(try await LicenseCheck.run(key: "x", session: session).0 == .invalid)
    }

    @Test func offline() async {
        StubProtocol.handler = { _ in nil }
        await #expect(throws: LicenseError.offline) { try await LicenseCheck.run(key: "x", session: session) }
    }

    @Test func unexpectedBody() async {
        StubProtocol.handler = { _ in (502, Data("<html>bad gateway</html>".utf8)) }
        await #expect(throws: LicenseError.unexpected) { try await LicenseCheck.run(key: "x", session: session) }
    }
}

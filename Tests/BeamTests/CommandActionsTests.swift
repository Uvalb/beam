// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

struct PathInputTests {
    @Test func detectsPaths() {
        #expect(PathInput.isPath("/usr/local"))
        #expect(PathInput.isPath("~/Documents"))
        #expect(PathInput.isPath("  ~/x"))
        #expect(!PathInput.isPath("youtube"))
        #expect(!PathInput.isPath("a/b"))
        #expect(!PathInput.isPath("~foo"))
    }

    @Test func expandsPastedPaths() {
        #expect(PathInput.expand("'/tmp/a b/'") == "/tmp/a b")
        #expect(PathInput.expand("/tmp/a\\ b") == "/tmp/a b")
        #expect(PathInput.expand("~/x") == NSHomeDirectory() + "/x")
        #expect(PathInput.expand("/") == "/")
    }

    @Test func completesFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("beam-\(UUID().uuidString)")
        for d in ["Alpha", "alpine", ".hidden", "Beta"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("alfile"))
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.path + "/"
        #expect(PathInput.completions(for: base + "al") == [base + "Alpha/", base + "alpine/"])
        #expect(PathInput.completions(for: base + "b") == [base + "Beta/"])
        #expect(PathInput.completions(for: base).count == 3)               // no hidden, no files
        #expect(PathInput.completions(for: base + ".").count == 1)
        #expect(PathInput.completions(for: "plain").isEmpty)
        #expect(PathInput.directory(root.path + "/alfile")?.path == root.path)   // a file opens its folder
        #expect(PathInput.directory(base + "nope") == nil)
        #expect(PathInput.commonPrefix(["Alpha/", "alpine/"]) == "Alp")
    }
}

struct URLInputTests {
    @Test func defaultsToDotCom() {
        #expect(URLInput.candidates("youtube", history: []) == ["youtube.com"])
        #expect(URLInput.candidates("GitHub.io", history: []) == ["github.io"])
        #expect(URLInput.candidates("localhost:3000", history: []) == ["localhost:3000"])
        #expect(URLInput.candidates("example.com/a/b", history: []) == ["example.com/a/b"])
    }

    @Test func historyComesFirst() {
        #expect(URLInput.candidates("you", history: ["youtube.co.il", "x.com"]) == ["youtube.co.il", "you.com"])
        #expect(URLInput.candidates("youtube.co.il", history: ["youtube.co.il"]) == ["youtube.co.il"])
    }

    @Test func rejectsNonHosts() {
        #expect(URLInput.candidates("two words", history: []).isEmpty)
        #expect(URLInput.candidates("", history: []).isEmpty)
        #expect(URLInput.candidates("/usr", history: []).isEmpty)
        #expect(URLInput.candidates("ab_c", history: []).isEmpty)
        #expect(URLInput.candidates("-x", history: []).isEmpty)
    }

    @Test func schemes() {
        #expect(URLInput.url(for: "youtube.com")?.absoluteString == "https://youtube.com")
        #expect(URLInput.url(for: "localhost:3000/x")?.absoluteString == "http://localhost:3000/x")
        #expect(URLInput.url(for: "192.168.1.1")?.absoluteString == "http://192.168.1.1")
    }
}

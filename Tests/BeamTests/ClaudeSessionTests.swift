// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

private func record(_ fields: String) -> Data { Data("{\"sessionId\":\"local_abc\",\(fields)}".utf8) }

struct ClaudeSessionTests {
    @Test func parsesTitleAndFolder() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"Fix login\",\"cwd\":\"/Users/me/github/mobiapp\",\"lastFocusedAt\":42"))
        #expect(s == .init(id: "local_abc", title: "Fix login", folder: "mobiapp", worktree: nil, lastFocused: 42))
        #expect(s?.subtitle == "mobiapp")
        #expect(s?.folderKeys == ["mobiapp"])
    }

    @Test func worktreeKeepsRepoName() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"OTP\",\"cwd\":\"/Users/me/github/mobiapp/.claude/worktrees/verify-otp-3f7aaf\""))
        #expect(s?.folder == "mobiapp")
        #expect(s?.worktree == "verify-otp-3f7aaf")
        #expect(s?.subtitle == "mobiapp › verify-otp-3f7aaf")
        #expect(s?.folderKeys == ["mobiapp", "verify-otp-3f7aaf"])
    }

    @Test func skipsArchived() {
        #expect(ClaudeSessionProvider.parse(record("\"title\":\"Old\",\"isArchived\":true")) == nil)
    }

    @Test func scratchWorkspaceShowsNoFolder() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"Quick\",\"cwd\":\"/x/Claude/scratch-workspaces/a/b/scratch-1\""))
        #expect(s?.folder == "No folder")
    }

    @Test func untitledFallsBackToFolder() {
        let s = ClaudeSessionProvider.parse(record("\"cwd\":\"/Users/me/github/beam\",\"lastFocusedAt\":null"))
        #expect(s?.title == "beam")
        #expect(s?.lastFocused == 0)
        #expect(s?.folderKeys == [])
    }

    @Test func rejectsMalformedJSON() {
        #expect(ClaudeSessionProvider.parse(Data("nope".utf8)) == nil)
    }

    @Test func placeholderFolderIsNotAKey() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"Quick\""))
        #expect(s?.folderKeys == [])
    }

    @Test func activityTimeFillsInForNeverFocused() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"CLI\",\"lastActivityAt\":7"))
        #expect(s?.lastFocused == 7)
    }

    @Test func storeWalkSkipsNonSessionsAndSortsByRecency() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("beam-sessions-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("ws/folder")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try record("\"title\":\"Older\",\"lastFocusedAt\":1").write(to: dir.appendingPathComponent("local_a.json"))
        try Data("{\"sessionId\":\"local_b\",\"title\":\"Newer\",\"lastFocusedAt\":2}".utf8).write(to: dir.appendingPathComponent("local_b.json"))
        try Data("{\"version\":1,\"items\":[]}".utf8).write(to: root.appendingPathComponent("scheduled-tasks.json"))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("deleted_x"))
        #expect(ClaudeSessionProvider.sessions(in: root.path).map(\.title) == ["Newer", "Older"])
    }

    @Test func worktreeFieldsWinOverPath() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"T\",\"cwd\":\"/w/elsewhere/wt-1\",\"originCwd\":\"/Users/me/code/beam\",\"worktreeName\":\"wt-1\""))
        #expect(s?.folder == "beam")
        #expect(s?.worktree == "wt-1")
    }

    @Test func nullWorktreeNameFallsBackToPath() {
        let s = ClaudeSessionProvider.parse(record("\"title\":\"T\",\"cwd\":\"/u/app/.claude/worktrees/x-1\",\"originCwd\":\"/u/app\",\"worktreeName\":null"))
        #expect(s?.folder == "app")
        #expect(s?.worktree == "x-1")
    }

    @Test func sessionIdIsPercentEncoded() {
        #expect(ClaudeSessionProvider.url(for: "local_a&b=c")?.absoluteString == "claude://code/continue?session=local_a%26b%3Dc")
        #expect(ClaudeSessionProvider.url(for: "local_abc")?.absoluteString == "claude://code/continue?session=local_abc")
    }

    @Test func storeWalkPicksUpChangedAndDeletedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("beam-sessions-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("ws/folder")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = dir.appendingPathComponent("local_a.json")
        try record("\"title\":\"Before\"").write(to: file)
        #expect(ClaudeSessionProvider.sessions(in: root.path).map(\.title) == ["Before"])
        try record("\"title\":\"After\"").write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        #expect(ClaudeSessionProvider.sessions(in: root.path).map(\.title) == ["After"])
        try FileManager.default.removeItem(at: file)
        #expect(ClaudeSessionProvider.sessions(in: root.path).isEmpty)
    }
}

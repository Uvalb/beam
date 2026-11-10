// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import BeamCore

struct BookmarkTests {
    @Test func parsesNestedFoldersAndSkipsNonWebLinks() {
        let json = """
        {"roots":{"bookmark_bar":{"type":"folder","children":[
          {"type":"url","name":"Swift","url":"https://swift.org/"},
          {"type":"folder","name":"F","children":[{"type":"url","name":"Evil","url":"javascript:alert(1)"},
                                                  {"type":"url","name":"GH","url":"https://github.com"}]}]},
         "other":{"type":"folder","children":[]}}}
        """
        #expect(BookmarkProvider.parse(Data(json.utf8)) == [
            .init(name: "Swift", url: "https://swift.org/"), .init(name: "GH", url: "https://github.com")])
        #expect(BookmarkProvider.parse(Data("nonsense".utf8)).isEmpty)
    }

    @Test func profileNamesFromLocalState() {
        let json = #"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Work"}}}}"#
        #expect(BookmarkProvider.profileNames(Data(json.utf8)) == ["Default": "Personal", "Profile 1": "Work"])
    }

    @Test func onlyStrongMatchesAndBelowApps() {
        func item(_ kind: ItemKind, _ title: String, _ keys: [String]) -> SearchItem {
            SearchItem(kind: kind, title: title, subtitle: "", keys: keys, icon: nil, activate: {})
        }
        let bm = item(.bookmark, "Swift Language", ["Swift Language", "swift.org"])
        let app = item(.app, "Swift Playgrounds", ["Swift Playgrounds"])
        let r = SearchIndex.rank([bm, app], query: "swift")
        #expect(r.map(\.kind) == [.app, .bookmark])
        #expect(SearchIndex.rank([bm], query: "sft").isEmpty)   // fuzzy only: dropped
    }
}

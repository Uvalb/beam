// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// A main menu that's never seen (Beam is an accessory app, so no menu bar shows),
/// but gives every window the standard key equivalents: Cmd-X/C/V/A/Z, Cmd-W, emoji.
/// Without it AppKit has nothing to route those shortcuts through.
/// There's deliberately no Quit item, so a stray Cmd-Q in the search panel doesn't quit Beam.
enum MainMenu {
    @MainActor static func install() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Hide Beam", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        add(app, to: main)

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)  // AppKit appends Emoji & Symbols, Dictation, Writing Tools to a menu titled "Edit"

        NSApp.mainMenu = main
    }

    @MainActor private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem()
        item.submenu = menu
        main.addItem(item)
    }
}

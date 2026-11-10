// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Beam's own About window. The standard About panel puts credits in a fixed-size,
/// white, scrolling box, which can't fit the supporter details and links.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show(credits: NSAttributedString) {
        window?.close()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let commit = info["BeamCommit"] as? String ?? "unknown build"

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let name = NSTextField(labelWithString: "Beam Launcher")
        name.font = .boldSystemFont(ofSize: 14)
        let ver = NSTextField(labelWithString: "Version \(version) (\(commit))")
        ver.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        ver.textColor = .secondaryLabelColor

        let width: CGFloat = 300
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textStorage?.setAttributedString(credits)
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let h = ceil(text.layoutManager?.usedRect(for: text.textContainer!).height ?? 0)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.widthAnchor.constraint(equalToConstant: width).isActive = true
        text.heightAnchor.constraint(equalToConstant: h).isActive = true

        let stack = NSStackView(views: [icon, name, ver, text])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(18, after: ver)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 28, bottom: 24, right: 28)

        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = ""
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

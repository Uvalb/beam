// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Borderless text button that shows the pointing-hand cursor, so it reads as a link.
private final class LinkButton: NSButton {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    func setTitle(_ title: String, color: NSColor) {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color])
        sizeToFit()
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onCommandD: (() -> Void)?
    /// ⌘ plus a key (`t`, `f`, `\r`); returns whether it was handled.
    var onCommandKey: ((String) -> Bool)?
    var onCommandChanged: ((Bool) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers {
            if key == "d", let f = onCommandD { f(); return true }
            if ["t", "f", "\r"].contains(key), onCommandKey?(key) == true { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged { onCommandChanged?(event.modifierFlags.contains(.command)) }
        super.sendEvent(event)
    }
}

/// Spotlight-style floating search bar with live results.
final class SearchPanel: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let index: SearchIndex
    private let panel: KeyPanel
    private let field = NSTextField()
    private let glyph = BeamIconView()
    private var bar: NSView!
    private var list: NSView!
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var results: [SearchItem] = []

    // Support nudge: a strip under the bar for a few opens after a milestone,
    // and a short celebratory "stamp" right after the milestone beam itself.
    private let pill = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    private let pillSupport = LinkButton()
    /// Quiet gray link in the bar once the pill is gone (hidden for supporters).
    private let barSupport = LinkButton()
    private let pillClose = NSButton()
    /// Quiet hint left of the support link: what ⌘ would do for the typed text.
    private let cmdHint = NSTextField(labelWithString: "")
    private var pillMilestone: Int?
    private let pillHeight: CGFloat = 32
    private let stampLabel = NSTextField(labelWithString: "")
    private var stampTimer: Timer?
    private var isStamping = false
    /// Bumped on every show/hide so a stale stamp fade can't close a newer panel.
    private var generation = 0

    private let width: CGFloat = 680
    private let fieldHeight: CGFloat = 52
    /// Space between the search bar and the results panel, as in Spotlight.
    private let gap: CGFloat = 8
    private let rowHeight: CGFloat = 44
    private var maxRows: Int { MaxResults.current }

    init(index: SearchIndex) {
        self.index = index
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
                         styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                         backing: .buffered, defer: false)
        super.init()
        setupPanel()
        index.onUpdate = { [weak self] in self?.updateResults() }
    }

    private func setupPanel() {
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let root = NSView()
        if #available(macOS 26, *) {
            // One container so the two glass shapes sample the backdrop together and
            // adapt light/dark as a unit; separately, the small bar and the big list
            // could land on opposite appearances. Spacing 0 keeps them from merging.
            let container = NSGlassEffectContainerView()
            container.spacing = 0
            container.contentView = root
            panel.contentView = container
        } else {
            panel.contentView = root
        }

        // Two separate rounded glass shapes: the search bar and, below it, the results.
        let barContent: NSView
        (bar, barContent) = Self.makeGlass(cornerRadius: fieldHeight / 2)
        let listContent: NSView
        (list, listContent) = Self.makeGlass(cornerRadius: 22)
        root.addSubview(bar)
        root.addSubview(list)

        barContent.addSubview(glyph)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.placeholderString = "Beam to…"
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        barContent.addSubview(field)

        stampLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .regular)
        stampLabel.textColor = .labelColor
        stampLabel.isHidden = true
        barContent.addSubview(stampLabel)

        pill.wantsLayer = true
        pill.isHidden = true
        pillLabel.font = .systemFont(ofSize: 13)
        pillLabel.textColor = .secondaryLabelColor
        pillLabel.lineBreakMode = .byTruncatingTail
        pill.addSubview(pillLabel)
        pillSupport.isBordered = false
        pillSupport.setTitle("Support Beam", color: .systemPink)
        pillSupport.toolTip = "⌘D"
        pillSupport.target = self
        pillSupport.action = #selector(supportClicked)
        pill.addSubview(pillSupport)
        pillClose.isBordered = false
        pillClose.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        pillClose.contentTintColor = .tertiaryLabelColor
        pillClose.target = self
        pillClose.action = #selector(dismissPill)
        pill.addSubview(pillClose)
        barContent.addSubview(pill)
        barSupport.isBordered = false
        barSupport.setTitle("Support Beam", color: .tertiaryLabelColor)
        barSupport.toolTip = "⌘D"
        barSupport.target = self
        barSupport.action = #selector(supportClicked)
        barContent.addSubview(barSupport)
        cmdHint.font = .systemFont(ofSize: 13, weight: .medium)
        cmdHint.textColor = .tertiaryLabelColor
        cmdHint.alignment = .right
        cmdHint.isHidden = true
        barContent.addSubview(cmdHint)
        panel.onCommandD = { [weak self] in self?.supportClicked() }
        panel.onCommandKey = { [weak self] in self?.commandKey($0) ?? false }
        panel.onCommandChanged = { [weak self] held in
            guard let self, held != self.cmdHeld else { return }
            self.cmdHeld = held
            self.updateResults()
        }

        let col = NSTableColumn(identifier: .init("main"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = rowHeight
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.hasVerticalScroller = false
        listContent.addSubview(scroll)
    }

    /// A rounded glass surface (Liquid Glass on macOS 26, a masked blur before that)
    /// and the view to put its content in. Masking the shape, rather than rounding a
    /// layer, is what makes the window shadow follow the rounded corners.
    private static func makeGlass(cornerRadius r: CGFloat) -> (NSView, NSView) {
        let content = NSView()
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = r
            glass.contentView = content
            return (glass, content)
        }
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        let mask = NSImage(size: NSSize(width: 2 * r + 1, height: 2 * r + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        blur.maskImage = mask
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)
        return (blur, content)
    }

    // MARK: Show / hide

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        resetStamp()
        pillMilestone = Support.pillMilestone
        if let m = pillMilestone {
            pillLabel.stringValue = "You've beamed \(Support.formatted(m)) times. If Beam saves you time, help keep it alive."
        }
        index.refreshLive()
        field.stringValue = ""
        cmdHeld = false
        tabState = nil
        shownQuery = ""
        results = []
        table.reloadData()
        layout()
        // Center on the screen containing the mouse (the "active" screen).
        let mouse = NSEvent.mouseLocation
        // No screen at all happens briefly during clamshell and display-sleep transitions.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - width / 2
        let top = vf.maxY - vf.height * 0.22
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        glyph.play()
    }

    func hide() {
        panel.orderOut(nil)   // before resetStamp restores alpha, or a faded stamp flashes back
        resetStamp()
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isStamping { hide() }
    }

    @objc private func supportClicked() {
        Support.openDonatePage()
        hide()
    }

    @objc private func dismissPill() {
        Support.dismissPill()
        pillMilestone = nil
        layout()
    }

    // MARK: Milestone stamp

    /// Activates `item` while the panel briefly shows the glyph burst and the
    /// count rolling up, then fades out. Never delays the beam itself.
    private func stamp(_ milestone: Int, then item: SearchItem) {
        isStamping = true
        generation += 1
        let gen = generation
        results = []
        table.reloadData()
        pillMilestone = nil
        field.isHidden = true
        stampLabel.isHidden = false
        panel.ignoresMouseEvents = true
        layout()
        item.activate()
        glyph.burst()

        let start = CACurrentMediaTime()
        let roll: CFTimeInterval = 0.9
        let suffix = " beams · Consider supporting Beam"
        stampTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            let p = min(1, (CACurrentMediaTime() - start) / roll)
            let e = 1 - pow(1 - p, 3)
            self?.stampLabel.stringValue = Support.formatted(Int((Double(milestone) * e).rounded())) + suffix
            if p >= 1 { t.invalidate() }
        }
        RunLoop.main.add(stampTimer!, forMode: .common)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.generation == gen else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.hide()
            })
        }
    }

    private func resetStamp() {
        generation += 1
        stampTimer?.invalidate(); stampTimer = nil
        isStamping = false
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        field.isHidden = false
        stampLabel.isHidden = true
    }

    private func layout() {
        // Never taller than the screen below the panel's top; extra results scroll.
        let bottom = (panel.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        let room = panel.frame.maxY - bottom - fieldHeight - gap - 16 - 20
        let fit = max(1, Int(room / rowHeight))
        let rows = min(results.count, maxRows, fit)
        let listHeight = rows > 0 ? CGFloat(rows) * rowHeight + 16 : 0
        let barHeight = fieldHeight + (pillMilestone != nil ? pillHeight : 0)
        let height = barHeight + (rows > 0 ? gap + listHeight : 0)
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)

        bar.frame = NSRect(x: 0, y: height - barHeight, width: width, height: barHeight)
        let fieldY = barHeight - fieldHeight
        // Spans from the bar's left edge so pixels can beam in from off-screen-left.
        glyph.frame = NSRect(x: 0, y: fieldY, width: 50, height: fieldHeight)
        glyph.iconOrigin = CGPoint(x: 18, y: (fieldHeight - 24) / 2)
        barSupport.isHidden = pillMilestone != nil || Support.isSupporter || isStamping
        barSupport.frame.origin = CGPoint(x: width - 22 - barSupport.frame.width,
                                          y: fieldY + (fieldHeight - barSupport.frame.height) / 2)
        var fieldRight = barSupport.isHidden ? width - 18 : barSupport.frame.minX - 12
        let hint = isStamping ? nil : CommandActions.hint(for: field.stringValue, held: cmdHeld)
        cmdHint.isHidden = hint == nil
        if let hint {
            cmdHint.stringValue = hint
            cmdHint.sizeToFit()
            cmdHint.frame.origin = CGPoint(x: fieldRight - cmdHint.frame.width,
                                           y: fieldY + (fieldHeight - cmdHint.frame.height) / 2)
            fieldRight = cmdHint.frame.minX - 12
        }
        field.frame = NSRect(x: 52, y: fieldY + (fieldHeight - 28) / 2, width: fieldRight - 52, height: 28)
        stampLabel.frame = NSRect(x: 56, y: fieldY + (fieldHeight - 26) / 2, width: width - 76, height: 26)

        pill.isHidden = pillMilestone == nil
        pill.frame = NSRect(x: 0, y: 0, width: width, height: pillHeight)
        pill.layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.12).cgColor
        pillClose.frame = NSRect(x: width - 38, y: (pillHeight - 20) / 2, width: 20, height: 20)
        pillSupport.sizeToFit()
        pillSupport.frame.origin = CGPoint(x: pillClose.frame.minX - 8 - pillSupport.frame.width,
                                           y: (pillHeight - pillSupport.frame.height) / 2)
        pillLabel.frame = NSRect(x: 22, y: (pillHeight - 17) / 2, width: pillSupport.frame.minX - 34, height: 17)

        list.isHidden = rows == 0
        list.frame = NSRect(x: 0, y: 0, width: width, height: listHeight)
        scroll.frame = NSRect(x: 0, y: 8, width: width, height: listHeight - 16)
        table.tableColumns.first?.width = width
        panel.invalidateShadow()
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) { tabState = nil; updateResults() }

    /// The query `results` were built for, so a background refresh (same query) keeps the
    /// selected item instead of jumping back to the top row under the user's Return.
    private var shownQuery = ""
    /// ⌘ is down: the list shows actions on the typed text instead of matches (0020).
    private var cmdHeld = false
    /// Tab completion in progress: the choices, and the one shown last (-1 = only the common prefix).
    private var tabState: (choices: [String], index: Int)?

    private func updateResults() {
        guard panel.isVisible, !isStamping else { return }
        let query = field.stringValue
        if SearchScope.parse(query).0 != nil { index.scopedQueryTyped() }
        let row = table.selectedRow
        let selected = query == shownQuery && results.indices.contains(row) ? results[row].identity : nil
        let actions = cmdHeld ? CommandActions.items(for: query) : []
        results = actions.isEmpty ? index.search(query, limit: maxRows) : actions
        shownQuery = query
        table.reloadData()
        if !results.isEmpty {
            let keep = SearchIndex.keptRow(selected, in: results)
            table.selectRowIndexes([keep], byExtendingSelection: false)
            table.scrollRowToVisible(keep)
        }
        layout()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        // ⌘ held turns the arrows into these (to the end/start of the text): keep them moving the selection.
        case #selector(NSResponder.moveToEndOfDocument(_:)), #selector(NSResponder.moveToEndOfParagraph(_:)),
             #selector(NSResponder.moveToEndOfLine(_:)) where cmdHeld && !results.isEmpty: move(1); return true
        case #selector(NSResponder.moveToBeginningOfDocument(_:)), #selector(NSResponder.moveToBeginningOfParagraph(_:)),
             #selector(NSResponder.moveToBeginningOfLine(_:)) where cmdHeld && !results.isEmpty: move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): launch(table.selectedRow); return true
        case #selector(NSResponder.cancelOperation(_:)): hide(); return true
        case #selector(NSResponder.insertTab(_:)): return completePath()
        default: return false
        }
    }

    /// Tab on a typed path: complete the folder name, shell style. One Tab fills the shared prefix (or
    /// the only choice); more Tabs step through the choices. Not a path: Tab does nothing.
    private func completePath() -> Bool {
        let typed = field.stringValue
        guard PathInput.isPath(typed) else { return true }
        var state = tabState
        if state == nil {
            let choices = PathInput.completions(for: typed)
            guard !choices.isEmpty else { NSSound.beep(); return true }
            let common = PathInput.commonPrefix(choices)
            state = (choices, common.count > typed.count ? -1 : 0)
            if choices.count == 1 || state!.index == -1 { setField(choices.count == 1 ? choices[0] : common) }
            else { setField(choices[0]) }
        } else {
            let next = (state!.index + 1) % state!.choices.count
            state!.index = next
            setField(state!.choices[next])
        }
        tabState = state
        return true
    }

    private func setField(_ text: String) {
        field.stringValue = text
        field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        updateResults()
    }

    /// ⌘T / ⌘F / ⌘↵. Runs the matching action on the typed text even if the list wasn't refreshed yet.
    private func commandKey(_ key: String) -> Bool {
        let query = field.stringValue
        let item: SearchItem?
        switch key {
        case "t": item = CommandActions.terminalItem(query)
        case "f": item = CommandActions.finderItem(query)
        default:
            // The selected action row if one is showing (a host, or Terminal/Finder on a path the
            // arrows moved to), else the best guess for the typed text.
            let row = table.selectedRow
            item = cmdHeld && results.indices.contains(row) && results[row].kind == .action
                ? results[row] : CommandActions.urlItems(query).first
        }
        guard let item else { NSSound.beep(); return true }
        hide()
        item.activate()
        return true
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let row = Self.wrap(table.selectedRow, by: delta, count: results.count)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    /// Arrow-key selection, wrapping at both ends; no selection (-1) counts as the first row.
    static func wrap(_ row: Int, by delta: Int, count: Int) -> Int {
        ((max(row, 0) + delta) % count + count) % count
    }

    @objc private func clicked() { launch(table.clickedRow) }

    private func launch(_ row: Int) {
        guard results.indices.contains(row) else { return }
        let item = results[row]
        if let milestone = Support.recordBeam() {
            stamp(milestone, then: item)
        } else {
            hide()
            item.activate()
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ResultRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = results[row]
        let cell = (tableView.makeView(withIdentifier: ResultCell.id, owner: nil) as? ResultCell) ?? ResultCell()
        cell.configure(item)
        return cell
    }
}

/// Rounded, inset selection highlight like Spotlight's, instead of a full-width bar.
private final class ResultRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 12, yRadius: 12).fill()
    }
}

private final class ResultCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("ResultCell")
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    /// Every row's badge column is as wide as the widest badge, so titles line up and none is cut off.
    private static let badgeWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let widest = ItemKind.allCases.map { ($0.badge as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(max(70, widest + 4))
    }()

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        badge.font = .systemFont(ofSize: 11, weight: .medium)
        badge.textColor = .tertiaryLabelColor
        badge.alignment = .right
        for v in [icon, title, subtitle, badge] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -10),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: Self.badgeWidth),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: SearchItem) {
        icon.image = item.icon
        title.stringValue = item.title
        subtitle.stringValue = item.subtitle
        badge.stringValue = item.trailing ?? item.kind.badge
    }
}

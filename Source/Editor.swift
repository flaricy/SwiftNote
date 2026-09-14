import AppKit

final class TimeOverlay: NSView {
    weak var editor: NoteTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { editor?.drawTimes(dirtyRect) }
}
final class NoteTextView: NSTextView, NSViewToolTipOwner {
    let timeOverlay = TimeOverlay()
    func installTimeOverlay() {
        timeOverlay.editor = self; timeOverlay.frame = bounds
        timeOverlay.autoresizingMask = [.width, .height]; addSubview(timeOverlay)
    }
    var records: [LineRecord] = [] { didSet { timeOverlay.needsDisplay = true } }
    var recordRanges: [NSRange] = []
    var showTimes = true { didSet { resizeContainer(); needsDisplay = true } }
    var hasClickedLine = false { didSet { timeOverlay.needsDisplay = true } }
    var onImageSelected: ((NSTextAttachment?) -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var onPastePlainText: ((String) -> Bool)?
    var onInsert: ((String, NSRange) -> Bool)?
    var onDeleteAtStart: (() -> Bool)?
    var onTableTab: ((Bool) -> Bool)?
    var onCommandKey: ((UInt16) -> Bool)?
    var onChecklist: ((Int) -> Void)?
    var onTableEdit: ((Bool) -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let at = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if at < (string as NSString).length, let p = textStorage?.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle, !p.textBlocks.isEmpty {
            setSelectedRange(NSRange(location: at, length: 0))
            menu.addItem(.separator())
            for (title, action) in [("在下方插入一行", #selector(addRow)), ("删除这一行", #selector(removeRow))] { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        }
        return menu
    }
    @objc func addRow() { onTableEdit?(false) }
    @objc func removeRow() { onTableEdit?(true) }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), onCommandKey?(event.keyCode) == true { return }
        super.keyDown(with: event)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if !hasMarkedText(), onInsert?(text, range) == true { return }
        super.insertText(insertString, replacementRange: replacementRange)
    }
    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), onDeleteAtStart?() == true { return }
        super.deleteBackward(sender)
    }
    override func insertTab(_ sender: Any?) {
        if onTableTab?(false) == true { return }; super.insertTab(sender)
    }
    override func insertBacktab(_ sender: Any?) {
        if onTableTab?(true) == true { return }; super.insertBacktab(sender)
    }

    var datesForTooltips: [Date] = []
    private var hoverPoint: NSPoint?
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTracking { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        timeOverlay.needsDisplay = true
        super.mouseMoved(with: event)
    }
    override func mouseEntered(with event: NSEvent) { hoverPoint = convert(event.locationInWindow, from: nil); timeOverlay.needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hoverPoint = nil; timeOverlay.needsDisplay = true }

    let fullDate: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
    let todayTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    let shortDate: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f }()
    override var acceptsFirstResponder: Bool { true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); resizeContainer() }
    func resizeContainer() {
        timeOverlay.needsDisplay = true
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = NSSize(width: max(100, bounds.width - textContainerInset.width*2), height: .greatestFiniteMagnitude)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect); timeOverlay.needsDisplay = true
        if string.isEmpty, !hasMarkedText() {
            ("写点什么，或输入 /" as NSString).draw(at: NSPoint(x: textContainerOrigin.x+5, y: textContainerOrigin.y), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
    func drawTimes(_ dirtyRect: NSRect) {
        removeAllToolTips(); datesForTooltips = []
        guard showTimes, hasClickedLine, let lm = layoutManager, let tc = textContainer, !records.isEmpty, lm.numberOfGlyphs > 0 else { return }
        let origin = textContainerOrigin
        let caret = selectedRange().location
        // A trailing empty paragraph has no timestamp to show.
        guard caret < (string as NSString).length || !string.hasSuffix("\n") else { return }
        let activeGlyph = lm.glyphIndexForCharacter(at: min(caret, (string as NSString).length-1))
        let activeRect = lm.lineFragmentRect(forGlyphAt: activeGlyph, effectiveRange: nil)
        let activeKey = Int((origin.y+activeRect.minY).rounded())
        let local = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = lm.glyphRange(forBoundingRect: local, in: tc)
        struct Row {
            var endX: CGFloat
            var baseline: CGFloat
            var rightEdge: CGFloat
            var modified: Date
        }
        var rows: [Int: Row] = [:]
        let string = self.string as NSString
        let visibleCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{200b}" )).inverted
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, range, _ in
            guard range.location < lm.numberOfGlyphs else { return }
            let chars = lm.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            // Exclude newlines, trailing spaces, and empty table-cell placeholders.
            let last = string.rangeOfCharacter(from: visibleCharacters, options: .backwards, range: chars)
            guard last.location != NSNotFound else { return }
            let trimmed = NSRange(location: chars.location, length: NSMaxRange(last)-chars.location)
            let inkGlyphs = lm.glyphRange(forCharacterRange: trimmed, actualCharacterRange: nil)
            let ink = lm.boundingRect(forGlyphRange: inkGlyphs, in: tc)
            guard let row = self.recordRanges.lastIndex(where: { $0.location <= chars.location }), row < self.records.count else { return }
            let baseline = origin.y + rect.minY + lm.location(forGlyphAt: range.location).y
            let endX = origin.x + ink.maxX
            let rightEdge = min(self.bounds.width-self.textContainerInset.width, origin.x+rect.maxX-tc.lineFragmentPadding)
            let key = Int((origin.y+rect.minY).rounded())
            let date = self.records[row].modified
            if let old = rows[key] {
                rows[key] = Row(endX: max(endX, old.endX), baseline: max(baseline, old.baseline), rightEdge: max(rightEdge, old.rightEdge), modified: max(old.modified, date))
            } else { rows[key] = Row(endX: endX, baseline: baseline, rightEdge: rightEdge, modified: date) }
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let color = NSColor.secondaryLabelColor.withAlphaComponent(0.50)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for (key, row) in rows.sorted(by: { $0.key < $1.key }) where key == activeKey {
            let label = Calendar.current.isDateInToday(row.modified) ? todayTime.string(from: row.modified) : shortDate.string(from: row.modified)
            let width = ceil((label as NSString).size(withAttributes: attributes).width)
            let x = ceil(row.endX)+9
            let tooltipRect: NSRect
            if x+width <= row.rightEdge {
                let rect = NSRect(x: x, y: row.baseline-font.ascender, width: width, height: ceil(font.ascender-font.descender)+2)
                (label as NSString).draw(in: rect, withAttributes: attributes)
                tooltipRect = rect.insetBy(dx: -3, dy: -3)
            } else {
                // The normal text inset leaves just enough room for a clock even on a full line.
                let iconX = min(x, self.bounds.width-22)
                guard iconX >= row.endX+3 else { continue }
                let rect = NSRect(x: iconX, y: row.baseline-10, width: 12, height: 12)
                color.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)); ring.lineWidth = 1; ring.stroke()
                let hands = NSBezierPath(); hands.lineWidth = 1; hands.lineCapStyle = .round
                hands.move(to: NSPoint(x: rect.midX, y: rect.minY+3)); hands.line(to: NSPoint(x: rect.midX, y: rect.midY)); hands.line(to: NSPoint(x: rect.midX+2.5, y: rect.midY+1.5)); hands.stroke()
                tooltipRect = rect.insetBy(dx: -4, dy: -4)
            }
            datesForTooltips.append(row.modified)
            if let point = hoverPoint, tooltipRect.contains(point) {
                let text = fullDate.string(from: row.modified) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
                let size = text.size(withAttributes: attrs)
                let width = ceil(size.width)+24
                let y = tooltipRect.maxY+7+30 <= visibleRect.maxY ? tooltipRect.maxY+7 : tooltipRect.minY-37
                let bubble = NSRect(x: max(visibleRect.minX+8, min(tooltipRect.minX, visibleRect.maxX-width-8)), y: y, width: width, height: 30)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius = 8; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
                MemoTheme.surface.setFill()
                NSBezierPath(roundedRect: bubble, xRadius: 7, yRadius: 7).fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
                let border = NSBezierPath(roundedRect: bubble, xRadius: 7, yRadius: 7); border.lineWidth = 0.5; border.stroke()
                text.draw(at: NSPoint(x: bubble.minX+12, y: bubble.minY+7), withAttributes: attrs)
            }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let index = Int(bitPattern: data)-1
        guard datesForTooltips.indices.contains(index) else { return "" }
        return "最近修改：" + fullDate.string(from: datesForTooltips[index])
    }
    override func mouseDown(with event: NSEvent) {
        hasClickedLine = true
        let point = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 {
            let glyph = lm.glyphIndex(for: NSPoint(x: point.x-textContainerOrigin.x, y: point.y-textContainerOrigin.y), in: tc)
            let char = lm.characterIndexForGlyph(at: min(glyph, lm.numberOfGlyphs-1))
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: min(glyph, lm.numberOfGlyphs-1), length: 1), in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            if rect.insetBy(dx: -2, dy: -2).contains(point), char < (string as NSString).length, ["☐", "☑"].contains((string as NSString).substring(with: NSRange(location: char, length: 1))) { onChecklist?(char); return }
        }
        super.mouseDown(with: event)
        timeOverlay.needsDisplay = true
        let selected = selectedRange()
        if selected.location < (textStorage?.length ?? 0), let a = textStorage?.attribute(.attachment, at: selected.location, effectiveRange: nil) as? NSTextAttachment { onImageSelected?(a) }
        else { onImageSelected?(nil) }
    }
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if board.data(forType: .rtfd) == nil, board.data(forType: .rtf) == nil, let text = board.string(forType: .string), onPastePlainText?(text) == true { return }
        if let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let image = images.first,
           NSPasteboard.general.string(forType: .string) == nil { onPasteImage?(image); return }
        super.paste(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.compactMap { NSImage(contentsOf: $0) }
            if !images.isEmpty { let point = convert(sender.draggingLocation, from: nil); setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0)); for image in images { onPasteImage?(image) }; return true }
        }
        return super.performDragOperation(sender)
    }
}

// Small native surfaces keep formatting close to the text without adding a permanent toolbar.
final class CommandButton: NSButton {
    var current = false
    var onHover: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area { removeTrackingArea(area) }
        let new = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self); addTrackingArea(new); area = new
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func draw(_ dirtyRect: NSRect) {
        if current { NSColor.controlAccentColor.withAlphaComponent(0.10).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill() }
        super.draw(dirtyRect)
    }
}

final class EditorSurface: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9); path.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke(); path.lineWidth = 0.5; path.stroke()
    }
}

final class EditorController: NSObject, NSTextViewDelegate {
    let view = NoteTextView(frame: .zero)
    var didEdit: (() -> Void)?
    var requestImage: (() -> Void)?
    let commandPalette = EditorSurface()
    let selectionTools = EditorSurface()
    var slashRange: NSRange?
    var commandIndex = 0
    var commandItems: [(String, String, Int)] = []
    let allCommands: [(String, String, Int)] = [("正文", "text", 0), ("标题 1", "h1 heading", 1), ("标题 2", "h2 heading", 2), ("标题 3", "h3 heading", 3), ("标题 4", "h4 heading", 4), ("项目列表", "bullet list", 5), ("待办事项", "todo checkbox", 6), ("编号列表", "number list", 7), ("引用", "quote", 8), ("表格", "table", 9), ("图片", "image photo", 10)]

    // One immediate Backspace can decline a heading shortcut without deleting its text.
    var pendingHeading: (range: NSRange, original: NSAttributedString, caret: Int, convertedCaret: Int, typing: [NSAttributedString.Key: Any])?
    var updating = false
    var defaultSize: CGFloat = 16
    var defaultFamily: String?
    var selectedImage: NSTextAttachment?
    var onImageSelected: ((Bool) -> Void)?
    var onFormatChanged: ((Int, NSFont) -> Void)?
    override init() {
        super.init()
        view.installTimeOverlay()
        view.isRichText = true; view.importsGraphics = true; view.allowsUndo = true
        view.isEditable = true; view.isSelectable = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.minSize = NSSize(width: 200, height: 0); view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.backgroundColor = MemoTheme.paper
        view.insertionPointColor = MemoTheme.accent
        view.selectedTextAttributes = [.backgroundColor: MemoTheme.selection, .foregroundColor: NSColor.labelColor]
        view.typingAttributes = bodyAttributes(); view.delegate = self
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = true
        view.usesFindPanel = true; view.isIncrementalSearchingEnabled = true
        view.registerForDraggedTypes([.fileURL, .png, .tiff])
        view.onImageSelected = { [weak self] image in self?.selectedImage = image; self?.onImageSelected?(image != nil) }
        view.onPasteImage = { [weak self] image in self?.insertImage(image) }
        view.onPastePlainText = { [weak self] text in self?.pasteMarkdown(text) ?? false }
        for surface in [commandPalette, selectionTools] {
            surface.isHidden = true; surface.wantsLayer = true
            surface.layer?.shadowColor = NSColor.black.cgColor; surface.layer?.shadowOpacity = 0.12; surface.layer?.shadowRadius = 7; surface.layer?.shadowOffset = CGSize(width: 0, height: -2)
            view.addSubview(surface)
        }
        for (i, symbol) in ["bold", "italic", "underline", "strikethrough"].enumerated() {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)!, target: self, action: #selector(selectionFormat(_:)))
            button.tag = i; button.isBordered = false; button.contentTintColor = .labelColor
            button.toolTip = ["粗体 ⌘B", "斜体 ⌘I", "下划线 ⌘U", "删除线"][i]; button.setAccessibilityLabel(button.toolTip)
            button.frame = NSRect(x: 5+i*32, y: 3, width: 30, height: 28); selectionTools.addSubview(button)
        }
        view.onChecklist = { [weak self] at in self?.toggleChecklist(at: at) }
        view.onTableEdit = { [weak self] remove in self?.editTableRow(remove: remove) }
        view.onCommandKey = { [weak self] key in self?.commandKey(key) ?? false }
        view.onInsert = { [weak self] text, range in self?.handleInsertion(text, at: range) ?? false }
        view.onDeleteAtStart = { [weak self] in self?.backspaceBlock() ?? false }
        view.onTableTab = { [weak self] backwards in self?.navigateTable(backwards: backwards) ?? false }
    }
    func load(_ text: NSAttributedString, lines: [LineRecord]) {
        pendingHeading = nil
        view.hasClickedLine = false; commandPalette.isHidden = true; selectionTools.isHidden = true; slashRange = nil
        updating = true; view.textStorage?.setAttributedString(text)
        view.records = lines; view.recordRanges = paragraphRanges(text.string)
        view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily)
        view.undoManager?.removeAllActions(); view.setSelectedRange(NSRange(location: 0, length: 0)); view.scrollRangeToVisible(NSRange(location: 0, length: 0))
        selectedImage = nil; onImageSelected?(false); view.resizeContainer(); updating = false; view.needsDisplay = true
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        view.timeOverlay.needsDisplay = true
        if let pending = pendingHeading, view.selectedRange() != NSRange(location: pending.convertedCaret, length: 0) { pendingHeading = nil }
        guard !updating else { return }
        updateSelectionTools()
        updateCommandPalette()
        let position = view.selectedRange().location
        let attrs = position < (view.textStorage?.length ?? 0) ? view.textStorage!.attributes(at: position, effectiveRange: nil) : view.typingAttributes
        onFormatChanged?((attrs[.paragraphStyle] as? NSParagraphStyle)?.headerLevel ?? 0, attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: defaultSize))
        if view.selectedRange().length == 1, let attachment = attrs[.attachment] as? NSTextAttachment { selectedImage = attachment; onImageSelected?(true) }
        else { selectedImage = nil; onImageSelected?(false) }
    }
    func textDidChange(_ notification: Notification) {
        pendingHeading = nil
        guard !updating else { return }
        renderInlineMarkdown()
        updateCommandPalette()
        didEdit?()
    }
    func replace(_ range: NSRange, with value: NSAttributedString, caret: Int? = nil) {
        view.breakUndoCoalescing()
        guard view.shouldChangeText(in: range, replacementString: value.string) else { return }
        view.textStorage?.replaceCharacters(in: range, with: value)
        view.setSelectedRange(NSRange(location: caret ?? range.location+value.length, length: 0)); view.didChangeText(); view.breakUndoCoalescing()
    }
    func caretRect() -> NSRect {
        guard let lm = view.layoutManager, let tc = view.textContainer else { return .zero }
        lm.ensureLayout(for: tc)
        let position = min(view.selectedRange().location, max(0, (view.string as NSString).length-1))
        guard lm.numberOfGlyphs > 0 else { return NSRect(origin: view.textContainerOrigin, size: NSSize(width: 1, height: 22)) }
        let glyph = lm.glyphIndexForCharacter(at: position)
        let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return rect.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }
    func place(_ surface: NSView, size: NSSize, above: Bool) {
        let caret = caretRect(); let visible = view.visibleRect
        let x = max(visible.minX+8, min(caret.minX+5, visible.maxX-size.width-8))
        var y = above ? caret.minY-size.height-5 : caret.maxY+5
        if y < visible.minY+4 { y = caret.maxY+5 }
        if y+size.height > visible.maxY-4 { y = max(visible.minY+4, caret.minY-size.height-5) }
        surface.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }
    func updateSelectionTools() {
        let range = view.selectedRange()
        let valid = range.length > 0 && !view.hasMarkedText() && !updating && !view.attributedString().attributedSubstring(from: range).string.contains("\u{fffc}")
        selectionTools.isHidden = !valid
        if valid {
            place(selectionTools, size: NSSize(width: 138, height: 34), above: true)
            if let lm = view.layoutManager, let tc = view.textContainer {
                let glyph = lm.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
                let start = lm.boundingRect(forGlyphRange: glyph, in: tc).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
                let selectedGlyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let ink = lm.boundingRect(forGlyphRange: selectedGlyphs, in: tc).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
                let visible = view.visibleRect
                let candidates = [
                    NSRect(x: ink.maxX+12, y: start.midY-17, width: 138, height: 34),
                    NSRect(x: max(visible.minX+8, start.minX), y: ink.minY-39, width: 138, height: 34),
                    NSRect(x: max(visible.minX+8, start.minX), y: ink.maxY+6, width: 138, height: 34)
                ]
                // Only float into free space; the persistent Aa menu remains available otherwise.
                let allGlyphs = lm.glyphRange(forBoundingRect: visible.offsetBy(dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y), in: tc)
                var occupied: [NSRect] = []
                lm.enumerateLineFragments(forGlyphRange: allGlyphs) { _, used, _, _, _ in
                    if used.width > 1 { occupied.append(used.offsetBy(dx: self.view.textContainerOrigin.x, dy: self.view.textContainerOrigin.y)) }
                }
                if let frame = candidates.first(where: { candidate in visible.insetBy(dx: 4, dy: 4).contains(candidate) && !occupied.contains(where: { $0.intersects(candidate.insetBy(dx: -3, dy: -3)) }) }) { selectionTools.frame = frame }
                else { selectionTools.isHidden = true }
            }
            let attrs = view.textStorage!.attributes(at: range.location, effectiveRange: nil)
            let traits = NSFontManager.shared.traits(of: attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: defaultSize))
            for case let button as NSButton in selectionTools.subviews {
                let active = button.tag == 0 ? traits.contains(.boldFontMask) : (button.tag == 1 ? traits.contains(.italicFontMask) : (attrs[button.tag == 2 ? .underlineStyle : .strikethroughStyle] as? Int ?? 0) != 0)
                button.contentTintColor = active ? .controlAccentColor : .labelColor
            }
        }
    }
    @objc func selectionFormat(_ sender: NSButton) {
        if sender.tag < 2 { formatFont(trait: sender.tag == 0 ? .boldFontMask : .italicFontMask) }
        else { toggleAttribute(sender.tag == 2 ? .underlineStyle : .strikethroughStyle) }
        updateSelectionTools()
    }
    func toggleAttribute(_ key: NSAttributedString.Key) {
        let range = view.selectedRange()
        if range.length == 0 {
            var attrs = view.typingAttributes; attrs[key] = (attrs[key] as? Int ?? 0) == 0 ? 1 : 0; view.typingAttributes = attrs; return
        }
        let value = NSMutableAttributedString(attributedString: view.textStorage!.attributedSubstring(from: range))
        let enabled = (value.attribute(key, at: 0, effectiveRange: nil) as? Int ?? 0) == 0
        value.addAttribute(key, value: enabled ? 1 : 0, range: NSRange(location: 0, length: value.length))
        replace(range, with: value); view.setSelectedRange(range); view.window?.makeFirstResponder(view)
    }
    func updateCommandPalette() {
        guard !view.hasMarkedText(), view.selectedRange().length == 0 else { commandPalette.isHidden = true; slashRange = nil; return }
        let string = view.string as NSString; let caret = view.selectedRange().location
        let para = string.paragraphRange(for: NSRange(location: caret, length: 0))
        let prefix = string.substring(with: NSRange(location: para.location, length: caret-para.location))
        guard prefix.hasPrefix("/"), !prefix.contains(" "), prefix.count < 24 else { commandPalette.isHidden = true; slashRange = nil; return }
        let query = String(prefix.dropFirst()).lowercased()
        commandItems = allCommands.filter { query.isEmpty || $0.0.contains(query) || $0.1.contains(query) }
        guard !commandItems.isEmpty else { commandPalette.isHidden = true; slashRange = nil; return }
        slashRange = NSRange(location: para.location, length: prefix.utf16.count); commandIndex = 0
        drawCommands(); commandPalette.isHidden = false; selectionTools.isHidden = true
    }
    func drawCommands() {
        commandPalette.subviews.forEach { $0.removeFromSuperview() }
        for (i, item) in commandItems.enumerated() {
            let b = CommandButton(title: "  "+item.0, target: self, action: #selector(pickCommand(_:))); b.tag = i
            let symbols = ["text.alignleft", "textformat.size", "textformat.size", "textformat.size", "textformat.size", "list.bullet", "checkmark.square", "list.number", "text.quote", "tablecells", "photo"]
            b.image = NSImage(systemSymbolName: symbols[item.2], accessibilityDescription: nil); b.imagePosition = .imageLeading
            b.current = i == commandIndex
            b.onHover = { [weak self] in
                guard let self, self.commandIndex != i else { return }; self.commandIndex = i
                for case let button as CommandButton in self.commandPalette.subviews { button.current = button.tag == i; button.contentTintColor = button.current ? .controlAccentColor : .labelColor; button.needsDisplay = true }
            }
            b.isBordered = false; b.alignment = .left; b.font = .systemFont(ofSize: 12, weight: i == commandIndex ? .medium : .regular)
            b.contentTintColor = i == commandIndex ? .controlAccentColor : .labelColor
            b.frame = NSRect(x: 7, y: 6+i*28, width: 200, height: 28); commandPalette.addSubview(b)
        }
        place(commandPalette, size: NSSize(width: 214, height: 12+commandItems.count*28), above: false)
    }
    func commandKey(_ key: UInt16) -> Bool {
        guard !commandPalette.isHidden else { return false }
        if key == 53 { commandPalette.isHidden = true; slashRange = nil; return true }
        if key == 125 || key == 126 { commandIndex = (commandIndex + (key == 125 ? 1 : commandItems.count-1)) % commandItems.count; drawCommands(); return true }
        if key == 36 || key == 76 { executeCommand(); return true }
        return false
    }
    @objc func pickCommand(_ sender: NSButton) { commandIndex = sender.tag; executeCommand() }
    func executeCommand() {
        guard let range = slashRange, commandItems.indices.contains(commandIndex), NSMaxRange(range) <= (view.string as NSString).length else { return }
        let command = commandItems[commandIndex].2
        commandPalette.isHidden = true; slashRange = nil
        replace(range, with: NSAttributedString(string: "", attributes: bodyAttributes(size: defaultSize, family: defaultFamily)))
        switch command {
        case 0...4: applyParagraph(level: command)
        case 5...7:
            let marker = command == 5 ? "• " : (command == 6 ? "☐ " : "1. ")
            replace(view.selectedRange(), with: NSAttributedString(string: marker, attributes: bodyAttributes(size: defaultSize, family: defaultFamily)))
        case 8:
            var attrs = bodyAttributes(size: defaultSize, family: defaultFamily)
            let p = attrs[.paragraphStyle] as! NSMutableParagraphStyle; p.firstLineHeadIndent = 20; p.headIndent = 20; attrs[.foregroundColor] = NSColor.secondaryLabelColor
            view.typingAttributes = attrs
        case 9: insertTable(rows: 3, columns: 3)
        case 10: requestImage?()
        default: break
        }
        view.window?.makeFirstResponder(view)
    }
    func handleInsertion(_ text: String, at range: NSRange) -> Bool {
        pendingHeading = nil
        guard !updating, range.length == 0 else { return false }
        if text == "\n", !commandPalette.isHidden { executeCommand(); return true }
        let s = view.string as NSString
        let paragraph = s.paragraphRange(for: range)
        let prefix = s.substring(with: NSRange(location: paragraph.location, length: range.location-paragraph.location))
        let style = range.location < s.length ? view.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : view.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        guard style?.textBlocks.isEmpty != false else { return false }
        if text == " ", prefix.first == "\\", ["#", "##", "###", "####"].contains(String(prefix.dropFirst())) {
            let literal = String(prefix.dropFirst()) + " "
            replace(NSRange(location: paragraph.location, length: prefix.utf16.count), with: NSAttributedString(string: literal, attributes: view.typingAttributes))
            return true
        }
        if text == " ", ["#", "##", "###", "####", "-", "*", ">", "[]", "[ ]", "1."].contains(prefix) {
            let originalTyping = view.typingAttributes
            let original = NSMutableAttributedString(attributedString: view.textStorage!.attributedSubstring(from: paragraph))
            original.insert(NSAttributedString(string: " ", attributes: originalTyping), at: range.location-paragraph.location)
            let level = prefix.first == "#" ? prefix.count : 0
            let marker = ["-", "*"].contains(prefix) ? "• " : (["[]", "[ ]"].contains(prefix) ? "☐ " : (prefix == "1." ? "1. " : ""))
            var attrs = headingAttributes(level)
            if prefix == ">", let p = attrs[.paragraphStyle] as? NSMutableParagraphStyle { p.headIndent = 20; p.firstLineHeadIndent = 20; attrs[.foregroundColor] = NSColor.secondaryLabelColor }
            let replacement = NSMutableAttributedString(string: marker, attributes: attrs)
            let suffixRange = NSRange(location: range.location, length: NSMaxRange(paragraph)-range.location)
            if suffixRange.length > 0 {
                let suffix = NSMutableAttributedString(attributedString: view.textStorage!.attributedSubstring(from: suffixRange))
                suffix.addAttributes(attrs, range: NSRange(location: 0, length: suffix.length)); replacement.append(suffix)
            }
            replace(paragraph, with: replacement, caret: paragraph.location+marker.utf16.count)
            view.typingAttributes = attrs
            if level > 0 {
                pendingHeading = (NSRange(location: paragraph.location, length: replacement.length), original, range.location+1, paragraph.location, originalTyping)
            }
            return true
        }
        if text == "\n" {
            let numberPrefix = prefix.range(of: "^[0-9]+\\. ", options: .regularExpression).map { String(prefix[$0]) }
            let marker = ["• ", "☐ ", "☑ "].first(where: { prefix.hasPrefix($0) }) ?? numberPrefix
            if let marker {
                if prefix == marker {
                    replace(NSRange(location: paragraph.location, length: prefix.utf16.count), with: NSAttributedString(string: "", attributes: bodyAttributes(size: defaultSize, family: defaultFamily)))
                } else {
                    let next = numberPrefix.flatMap { Int($0.dropLast(2)) }.map { "\($0+1). " } ?? (marker == "• " ? "• " : "☐ ")
                    replace(range, with: NSAttributedString(string: "\n"+next, attributes: bodyAttributes(size: defaultSize, family: defaultFamily)))
                }
                view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily)
                return true
            }
            if (style?.headerLevel ?? 0) > 0 || (style?.headIndent ?? 0) > 0 {
                // Insert the paragraph break with the current style, then reset only the new paragraph.
                replace(range, with: NSAttributedString(string: "\n", attributes: view.typingAttributes))
                if view.selectedRange().location < (view.string as NSString).length { applyParagraph(level: 0) }
                view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily)
                return true
            }
        }
        return false
    }
    func backspaceBlock() -> Bool {
        if let pending = pendingHeading, view.selectedRange() == NSRange(location: pending.convertedCaret, length: 0) {
            pendingHeading = nil
            replace(pending.range, with: pending.original, caret: pending.caret)
            view.typingAttributes = pending.typing
            return true
        }
        pendingHeading = nil
        let selection = view.selectedRange(); guard selection.length == 0 else { return false }
        let s = view.string as NSString; let paragraph = s.paragraphRange(for: selection)
        let prefix = s.substring(with: NSRange(location: paragraph.location, length: selection.location-paragraph.location))
        if ["• ", "☐ ", "☑ "].contains(prefix) || prefix.range(of: "^[0-9]+\\. $", options: .regularExpression) != nil {
            replace(NSRange(location: paragraph.location, length: prefix.utf16.count), with: NSAttributedString(string: "", attributes: bodyAttributes(size: defaultSize, family: defaultFamily)))
            view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily); return true
        }
        let style = view.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        if prefix.isEmpty, ((style?.headerLevel ?? 0)>0 || (style?.headIndent ?? 0)>0), style?.textBlocks.isEmpty != false { applyParagraph(level: 0); return true }
        return false
    }
    func navigateTable(backwards: Bool) -> Bool {
        let s = view.string as NSString; let at = view.selectedRange().location
        guard at < s.length, let style = view.textStorage?.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle, let cell = style.textBlocks.first as? NSTextTableBlock else { return false }
        var cells: [NSRange] = []
        var lastPosition: (Int, Int)?
        for r in paragraphRanges(view.string) where r.length > 0 {
            guard let p = view.textStorage?.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle, let b = p.textBlocks.first as? NSTextTableBlock, b.table === cell.table else { continue }
            if let old = lastPosition, old.0 == b.startingRow, old.1 == b.startingColumn { cells[cells.count-1] = NSUnionRange(cells.last!, r) }
            else { cells.append(r) }
            lastPosition = (b.startingRow, b.startingColumn)
        }
        guard let i = cells.firstIndex(where: { NSLocationInRange(at, $0) }) else { return false }
        let next = i + (backwards ? -1 : 1)
        if cells.indices.contains(next) {
            let r = cells[next]; view.setSelectedRange(NSRange(location: r.location, length: max(0, r.length-1)))
            view.scrollRangeToVisible(view.selectedRange())
        } else if !backwards { view.setSelectedRange(NSRange(location: NSMaxRange(cells[i]), length: 0)); view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily) }
        return true
    }
    func toggleChecklist(at: Int? = nil) {
        let text = view.string as NSString
        let location = at ?? text.paragraphRange(for: view.selectedRange()).location
        guard location < text.length, ["☐", "☑"].contains(text.substring(with: NSRange(location: location, length: 1))) else { return }
        let oldSelection = view.selectedRange()
        let attrs = view.textStorage!.attributes(at: location, effectiveRange: nil)
        replace(NSRange(location: location, length: 1), with: NSAttributedString(string: text.substring(with: NSRange(location: location, length: 1)) == "☐" ? "☑" : "☐", attributes: attrs))
        view.setSelectedRange(oldSelection)
    }
    func editTableRow(remove: Bool) {
        let at = view.selectedRange().location
        guard at < (view.string as NSString).length, let p = view.textStorage?.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle, let selected = p.textBlocks.first as? NSTextTableBlock else { return }
        let storage = view.attributedString()
        var cells: [(NSRange, NSTextTableBlock)] = []
        for range in paragraphRanges(storage.string) where range.length > 0 {
            if let p = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle, let b = p.textBlocks.first as? NSTextTableBlock, b.table === selected.table {
                if let previous = cells.last, previous.1.startingRow == b.startingRow, previous.1.startingColumn == b.startingColumn {
                    cells[cells.count-1].0 = NSUnionRange(previous.0, range)
                } else { cells.append((range, b)) }
            }
        }
        guard let first = cells.first, let last = cells.last else { return }
        let rowCount = (cells.map { $0.1.startingRow }.max() ?? 0)+1
        guard !remove || rowCount > 1 else { return }
        let table = NSTextTable(); table.numberOfColumns = selected.table.numberOfColumns; table.layoutAlgorithm = .fixedLayoutAlgorithm; table.collapsesBorders = true; table.setValue(100, type: .percentageValueType, for: .width)
        let result = NSMutableAttributedString()
        for row in 0..<(rowCount + (remove ? -1 : 1)) {
            let oldRow: Int? = remove ? (row >= selected.startingRow ? row+1 : row) : (row == selected.startingRow+1 ? nil : (row > selected.startingRow+1 ? row-1 : row))
            for col in 0..<table.numberOfColumns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
                block.setValue(100/CGFloat(table.numberOfColumns), type: .percentageValueType, for: .width); block.setWidth(1, type: .absoluteValueType, for: .border); block.setBorderColor(.separatorColor); block.setWidth(8, type: .absoluteValueType, for: .padding)
                if row == 0 { block.backgroundColor = .controlBackgroundColor }
                let value: NSMutableAttributedString
                if let old = cells.first(where: { $0.1.startingRow == oldRow && $0.1.startingColumn == col }) { value = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: old.0)) }
                else { value = NSMutableAttributedString(string: "\u{200b}\n", attributes: bodyAttributes(size: defaultSize, family: defaultFamily)) }
                value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { old, r, _ in
                    let style = (old as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle(); style.textBlocks = [block]; value.addAttribute(.paragraphStyle, value: style, range: r)
                }
                result.append(value)
            }
        }
        replace(NSRange(location: first.0.location, length: NSMaxRange(last.0)-first.0.location), with: result, caret: first.0.location)
    }
    func headingAttributes(_ level: Int) -> [NSAttributedString.Key: Any] {
        var attrs = bodyAttributes(size: defaultSize, family: defaultFamily)
        let p = (attrs[.paragraphStyle] as! NSMutableParagraphStyle)
        p.headerLevel = level
        if level > 0 {
            let sizes: [CGFloat] = [defaultSize, 30, 25, 21, 18]
            let f = defaultFamily.flatMap { NSFont(name: $0, size: sizes[level]) } ?? NSFont.systemFont(ofSize: sizes[level])
            attrs[.font] = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
            p.paragraphSpacingBefore = 10; p.paragraphSpacing = 10
        }
        return attrs
    }
    func applyParagraph(level: Int) {
        let selected = view.selectedRange(); let s = view.string as NSString
        let range = s.paragraphRange(for: selected)
        let attrs = headingAttributes(level)
        if range.length > 0 {
            let value = NSMutableAttributedString(attributedString: view.attributedSubstring(forProposedRange: range, actualRange: nil)!)
            value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { previous, run, _ in
                var preserved = attrs
                if let old = previous as? NSParagraphStyle, !old.textBlocks.isEmpty, let style = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                    style.textBlocks = old.textBlocks; preserved[.paragraphStyle] = style
                }
                value.addAttributes(preserved, range: run)
            }
            replace(range, with: value); view.setSelectedRange(selected)
        }
        var typing = attrs
        if selected.location < (view.textStorage?.length ?? 0), let style = view.textStorage?.attribute(.paragraphStyle, at: selected.location, effectiveRange: nil) as? NSParagraphStyle, !style.textBlocks.isEmpty { typing[.paragraphStyle] = style }
        view.typingAttributes = typing; view.window?.makeFirstResponder(view)
    }
    func formatFont(family: String? = nil, size: CGFloat? = nil, trait: NSFontTraitMask? = nil) {
        if let family { defaultFamily = family }
        if let size { defaultSize = size }
        let selected = view.selectedRange()
        let target = selected.length > 0 || trait != nil ? selected : (view.string as NSString).paragraphRange(for: selected)
        let baseFont = selected.length > 0 && selected.location < (view.textStorage?.length ?? 0) ? view.textStorage?.attribute(.font, at: selected.location, effectiveRange: nil) as? NSFont : view.typingAttributes[.font] as? NSFont
        let removeTrait = trait.map { NSFontManager.shared.traits(of: baseFont ?? NSFont.systemFont(ofSize: defaultSize)).contains($0) } ?? false
        func convert(_ old: NSFont) -> NSFont {
            var f = family.flatMap { NSFont(name: $0, size: size ?? old.pointSize) } ?? (size.map { NSFontManager.shared.convert(old, toSize: $0) } ?? old)
            if let trait { f = removeTrait ? NSFontManager.shared.convert(f, toNotHaveTrait: trait) : NSFontManager.shared.convert(f, toHaveTrait: trait) }
            return f
        }
        if target.length > 0 {
            let value = NSMutableAttributedString(attributedString: view.textStorage!.attributedSubstring(from: target))
            value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { f, r, _ in value.addAttribute(.font, value: convert(f as? NSFont ?? NSFont.systemFont(ofSize: self.defaultSize)), range: r) }
            replace(target, with: value); view.setSelectedRange(selected)
        }
        var a = view.typingAttributes; a[.font] = convert(a[.font] as? NSFont ?? NSFont.systemFont(ofSize: defaultSize)); view.typingAttributes = a
        view.window?.makeFirstResponder(view)
    }
    func renderInlineMarkdown() {
        guard !view.hasMarkedText(), view.undoManager?.isUndoing != true, view.undoManager?.isRedoing != true, let storage = view.textStorage, storage.length > 0 else { return }
        let caret = view.selectedRange().location
        let range = (storage.string as NSString).paragraphRange(for: NSRange(location: min(caret, storage.length), length: 0))
        let patterns: [(String, NSFontTraitMask?, Bool)] = [("\\*\\*([^*\\n]+)\\*\\*", .boldFontMask, false), ("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", .italicFontMask, false), ("`([^`\\n]+)`", nil, true)]
        for (pattern, trait, code) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.matches(in: storage.string, range: range).last, NSMaxRange(match.range) == caret else { continue }
            let continuationAttributes = storage.attributes(at: match.range.location, effectiveRange: nil)
            let content = storage.attributedSubstring(from: match.range(at: 1))
            let replacement = NSMutableAttributedString(attributedString: content)
            replacement.enumerateAttribute(.font, in: NSRange(location: 0, length: replacement.length)) { f, r, _ in
                let old = f as? NSFont ?? NSFont.systemFont(ofSize: self.defaultSize)
                let font = code ? NSFont.monospacedSystemFont(ofSize: old.pointSize, weight: .regular) : NSFontManager.shared.convert(old, toHaveTrait: trait!)
                replacement.addAttribute(.font, value: font, range: r)
                if code { replacement.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: r) }
            }
            view.breakUndoCoalescing()
            updating = true
            // Register the replacement with NSTextView so Markdown conversion remains undoable.
            if view.shouldChangeText(in: match.range, replacementString: replacement.string) {
                storage.replaceCharacters(in: match.range, with: replacement); view.didChangeText()
                view.setSelectedRange(NSRange(location: max(0, caret-match.range.length+replacement.length), length: 0))
            }
            view.typingAttributes = continuationAttributes
            updating = false
            view.breakUndoCoalescing()
            break
        }
    }
    func pasteMarkdown(_ text: String) -> Bool {
        guard text.range(of: "(?m)^(#{1,4} |[-*] |> )|\\*\\*[^*]+\\*\\*|`[^`]+`", options: .regularExpression) != nil else { return false }
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            var line = raw; var level = 0; var quote = false
            for n in (1...4).reversed() { let marker = String(repeating: "#", count: n)+" "; if line.hasPrefix(marker) { line.removeFirst(marker.count); level = n; break } }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• "+line.dropFirst(2) }
            if line.hasPrefix("> ") { line = String(line.dropFirst(2)); quote = true }
            var attrs = headingAttributes(level)
            if quote, let p = attrs[.paragraphStyle] as? NSMutableParagraphStyle { p.headIndent = 20; p.firstLineHeadIndent = 20; attrs[.foregroundColor] = NSColor.secondaryLabelColor }
            let paragraph = NSMutableAttributedString(string: line, attributes: attrs)
            for (pattern, trait, code) in [("\\*\\*([^*]+)\\*\\*", NSFontTraitMask.boldFontMask, false), ("(?<!\\*)\\*([^*]+)\\*(?!\\*)", NSFontTraitMask.italicFontMask, false), ("`([^`]+)`", NSFontTraitMask.boldFontMask, true)] {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    for match in regex.matches(in: paragraph.string, range: NSRange(location: 0, length: paragraph.length)).reversed() {
                        let value = NSMutableAttributedString(attributedString: paragraph.attributedSubstring(from: match.range(at: 1)))
                        let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: defaultSize)
                        value.addAttribute(.font, value: code ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : NSFontManager.shared.convert(font, toHaveTrait: trait), range: NSRange(location: 0, length: value.length))
                        paragraph.replaceCharacters(in: match.range, with: value)
                    }
                }
            }
            result.append(paragraph)
            if index < lines.count-1 { result.append(NSAttributedString(string: "\n", attributes: attrs)) }
        }
        replace(view.selectedRange(), with: result); view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily)
        return true
    }
    func insertImage(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = min(1, 2400/CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width)*scale)); let height = max(1, Int(CGFloat(source.height)*scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: source, size: NSSize(width: width, height: height)).draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = UUID().uuidString+".png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let displayWidth = min(CGFloat(width), max(120, (view.textContainer?.containerSize.width ?? 500)-18))
        attachment.bounds = NSRect(x: 0, y: 0, width: displayWidth, height: displayWidth*CGFloat(height)/CGFloat(width))
        let display = NSImage(data: data)!; display.size = attachment.bounds.size; attachment.attachmentCell = NSTextAttachmentCell(imageCell: display)
        let value = NSMutableAttributedString(string: "", attributes: bodyAttributes())
        let selection = view.selectedRange()
        if selection.location > 0 && (view.string as NSString).substring(with: NSRange(location: selection.location-1, length: 1)) != "\n" { value.append(NSAttributedString(string: "\n", attributes: bodyAttributes())) }
        value.append(NSAttributedString(attachment: attachment)); value.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
        replace(selection, with: value)
        view.setSelectedRange(NSRange(location: selection.location+value.length, length: 0))
        view.typingAttributes = bodyAttributes(size: defaultSize, family: defaultFamily)
        selectedImage = attachment; onImageSelected?(false); view.window?.makeFirstResponder(view)
    }
    func resizeImage(width: CGFloat) {
        guard let selectedImage, let storage = view.textStorage else { return }
        var range: NSRange?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, r, stop in if let a = value as? NSTextAttachment, a === selectedImage { range = r; stop.pointee = true } }
        guard let range, let data = selectedImage.fileWrapper?.regularFileContents, let image = NSImage(data: data) else { return }
        let ratio = image.size.height/max(1,image.size.width)
        let copy = NSTextAttachment(fileWrapper: selectedImage.fileWrapper)
        copy.bounds = NSRect(x: 0, y: 0, width: width, height: width*ratio); image.size = copy.bounds.size
        copy.attachmentCell = NSTextAttachmentCell(imageCell: image)
        replace(range, with: NSAttributedString(attachment: copy)); self.selectedImage = copy
        view.setSelectedRange(range)
    }
    func insertTable(rows: Int, columns: Int) {
        let table = NSTextTable(); table.numberOfColumns = columns; table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true; table.hidesEmptyCells = false
        table.setValue(100, type: .percentageValueType, for: .width)
        let result = NSMutableAttributedString(string: "\n", attributes: bodyAttributes())
        for row in 0..<rows {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setValue(100/CGFloat(columns), type: .percentageValueType, for: .width)
                block.setWidth(1, type: .absoluteValueType, for: .border); block.setBorderColor(.separatorColor)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                if row == 0 { block.backgroundColor = NSColor.controlBackgroundColor }
                let p = NSMutableParagraphStyle(); p.textBlocks = [block]; p.paragraphSpacing = 3
                var a = bodyAttributes(); a[.paragraphStyle] = p
                if row == 0 { a[.font] = NSFont.systemFont(ofSize: 15, weight: .semibold) }
                result.append(NSAttributedString(string: row == 0 ? "列 \(column+1)\n" : "\u{200b}\n", attributes: a))
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
        let at = view.selectedRange(); replace(at, with: result); view.typingAttributes = bodyAttributes(); view.window?.makeFirstResponder(view)
    }
}

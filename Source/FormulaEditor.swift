import AppKit

// This view occupies a real text attachment: TextKit moves surrounding text
// out of the way instead of placing an editor over an existing paragraph.
final class FormulaEditor: NSView, NSTextFieldDelegate {
    let input = NSTextField()
    let sourceEditor = FormulaSourceTextView()
    let preview = NSImageView()
    let message = NSTextField(labelWithString: "")
    let block: Bool
    let originalRange: NSRange
    let original: NSAttributedString
    var temporaryRange: NSRange
    var attachmentIndex: Int
    let spacer = FormulaDraftCell()
    var rendered: NSTextAttachment?
    var onChange: (() -> Void)?
    var onFinish: ((Bool) -> Bool)?
    var onGeometry: (() -> Void)?
    var valid = false
    var availableWidth: CGFloat = 300
    let fontSize: CGFloat
    override var isFlipped: Bool { true }

    init(formula: MathFormula, range: NSRange, original: NSAttributedString, fontSize: CGFloat) {
        block = formula.block; originalRange = range; self.original = original
        temporaryRange = range; attachmentIndex = range.location; self.fontSize = fontSize
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = MemoTheme.paper.cgColor
        sourceEditor.isFieldEditor = true; sourceEditor.allowsUndo = true
        sourceEditor.isAutomaticQuoteSubstitutionEnabled = false; sourceEditor.isAutomaticDashSubstitutionEnabled = false
        input.stringValue = formula.latex; input.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        input.cell?.wraps = false; input.cell?.isScrollable = true; input.usesSingleLineMode = true
        input.isBordered = false; input.drawsBackground = false; input.focusRingType = .none
        input.placeholderString = "LaTeX"
        input.delegate = self; input.setAccessibilityLabel(block ? L("独立公式源码") : L("行内公式源码"))
        preview.imageScaling = .scaleProportionallyDown
        message.usesSingleLineMode = false; message.cell?.wraps = true; message.cell?.isScrollable = false
        message.lineBreakMode = .byWordWrapping; message.maximumNumberOfLines = 0
        message.font = .systemFont(ofSize: 10); message.textColor = .secondaryLabelColor
        for child in [preview, input, message] { addSubview(child) }
    }
    required init?(coder: NSCoder) { fatalError("Programmatic editor") }
    @MainActor func refresh() {
        do {
            rendered = try MathFormula(latex: input.stringValue, block: block).attachment(fontSize: fontSize)
            preview.image = (rendered?.attachmentCell as? NSTextAttachmentCell)?.image
            valid = true; message.stringValue = L("↩ 完成   esc 取消"); message.textColor = .secondaryLabelColor
        } catch {
            rendered = nil; preview.image = nil; valid = false
            message.stringValue = input.stringValue.isEmpty ? L("输入后即刻呈现") : error.localizedDescription
            message.textColor = input.stringValue.isEmpty ? .secondaryLabelColor : .systemRed
        }
        updateGeometry()
    }
    func updateGeometry() {
        let image = preview.image?.size ?? NSSize(width: 120, height: 24)
        let sourceWidth = (input.stringValue as NSString).size(withAttributes: [.font: input.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
        let hintWidth = (message.stringValue as NSString).size(withAttributes: [.font: message.font!]).width + 20
        let width = block ? availableWidth : min(availableWidth, max(140, min(240, hintWidth), image.width+16, min(340, sourceWidth+20)))
        let scale = min(1, (width-16)/max(1,image.width))
        let height = min(220, max(30, image.height*scale))
        let messageWidth = max(1, width-16)
        let messageHeight = max(16, ceil(message.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: messageWidth, height: 10000)).height))
        spacer.size = NSSize(width: width, height: height+39+messageHeight+10)
        let font = NSFont.systemFont(ofSize: fontSize)
        spacer.baseline = block ? 0 : (font.ascender+font.descender)/2+height/2+5-spacer.size.height
        setFrameSize(spacer.size)
        preview.frame = NSRect(x: 8, y: 5, width: width-16, height: height)
        preview.imageAlignment = block ? .alignCenter : .alignLeft
        input.frame = NSRect(x: 8, y: height+12, width: width-16, height: 22)
        message.frame = NSRect(x: 8, y: height+39, width: messageWidth, height: messageHeight)
        needsDisplay = true; onGeometry?()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        MemoTheme.accent.withAlphaComponent(0.30).setStroke()
        let line = NSBezierPath(); line.move(to: NSPoint(x: 8, y: input.frame.maxY+2)); line.line(to: NSPoint(x: bounds.width-8, y: input.frame.maxY+2)); line.lineWidth = 0.5; line.stroke()
    }
    func controlTextDidChange(_ notification: Notification) { guard !sourceEditor.hasMarkedText() else { return }; MainActor.assumeIsolated { refresh() }; onChange?() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if (selector == #selector(NSResponder.deleteBackward(_:)) || selector == #selector(NSResponder.deleteForward(_:))), input.stringValue.isEmpty, !textView.hasMarkedText() { _ = onFinish?(false); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) { _ = onFinish?(false); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { _ = onFinish?(true); return true }
        return false
    }
}
final class FormulaSourceTextView: NSTextView {
    private let sourceUndo = UndoManager()
    override var undoManager: UndoManager? { sourceUndo }
}
final class FormulaDraftCell: NSTextAttachmentCell {
    var size = NSSize(width: 260, height: 95)
    var baseline: CGFloat = 0
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: baseline) }
    override func cellSize() -> NSSize { size }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
}

extension EditorController {
    @MainActor func beginFormulaEditing(block: Bool, range: NSRange) {
        guard finishFormulaEditing(cancel: false), let storage = view.textStorage, NSMaxRange(range) <= storage.length else { return }
        let original = storage.attributedSubstring(from: range)
        var formula = MathFormula(latex: "", block: block)
        if range.length == 1, let attachment = original.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
           let existing = MathFormula.read(attachment) { formula = existing }
        let draft = FormulaEditor(formula: formula, range: range, original: original, fontSize: defaultSize)
        formulaDraft = draft
        let placeholder = NSTextAttachment(); placeholder.attachmentCell = draft.spacer
        let replacement = NSMutableAttributedString(attachment: placeholder)
        let anchor = min(range.location, max(0, storage.length-1))
        let attrs = storage.length > 0 ? storage.attributes(at: anchor, effectiveRange: nil) : bodyAttributes()
        if let style = attrs[.paragraphStyle] { replacement.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: 1)) }
        if formula.block {
            let text = storage.string as NSString
            if range.location > 0 && text.substring(with: NSRange(location: range.location-1, length: 1)) != "\n" {
                replacement.insert(NSAttributedString(string: "\n", attributes: attrs), at: 0); draft.attachmentIndex += 1
            }
            if NSMaxRange(range) == storage.length || text.substring(with: NSRange(location: NSMaxRange(range), length: 1)) != "\n" { replacement.append(NSAttributedString(string: "\n", attributes: attrs)) }
        }
        updating = true; storage.replaceCharacters(in: range, with: replacement)
        draft.temporaryRange = NSRange(location: range.location, length: replacement.length)
        view.isEditable = false; commandPalette.isHidden = true; selectionTools.isHidden = true
        view.addSubview(draft); updating = false
        draft.onGeometry = { [weak self] in self?.positionFormulaDraft() }
        draft.onFinish = { [weak self] cancel in MainActor.assumeIsolated { self?.finishFormulaEditing(cancel: cancel) ?? true } }
        draft.availableWidth = formulaWidth(at: draft.attachmentIndex)
        draft.refresh(); positionFormulaDraft()
        view.scrollRangeToVisible(NSRange(location: draft.attachmentIndex, length: 1))
        view.window?.makeFirstResponder(draft.input); draft.input.selectText(nil)
    }
    func formulaWidth(at index: Int) -> CGFloat {
        let width = max(120, (view.textContainer?.containerSize.width ?? 400)-12)
        if let style = view.textStorage?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle,
           let cell = style.textBlocks.first as? NSTextTableBlock {
            return max(100, width * CGFloat(cell.columnSpan)/CGFloat(max(1,cell.table.numberOfColumns))-24)
        }
        return width
    }
    func positionFormulaDraft() {
        guard !positioningFormulaDraft, let draft = formulaDraft, let lm = view.layoutManager, let tc = view.textContainer else { return }
        positioningFormulaDraft = true; defer { positioningFormulaDraft = false }
        let width = formulaWidth(at: draft.attachmentIndex)
        if draft.availableWidth != width { draft.availableWidth = width; draft.updateGeometry() }
        let range = NSRange(location: draft.attachmentIndex, length: 1)
        lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil); lm.ensureLayout(for: tc)
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphs, in: tc).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        draft.setFrameOrigin(rect.origin)
        view.needsDisplay = true
    }
    @MainActor @discardableResult func finishFormulaEditing(cancel: Bool) -> Bool {
        guard let draft = formulaDraft else { return true }
        let deletingEmpty = !cancel && draft.input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !cancel && !deletingEmpty { draft.refresh() }
        if !cancel && !deletingEmpty && !draft.valid { view.window?.makeFirstResponder(draft.input); NSSound.beep(); return false }
        if !cancel && !deletingEmpty && draft.block, let style = view.textStorage?.attribute(.paragraphStyle, at: draft.attachmentIndex, effectiveRange: nil) as? NSParagraphStyle, !style.textBlocks.isEmpty {
            draft.message.stringValue = L("表格内请使用 /math-inline"); draft.message.textColor = .systemRed
            view.window?.makeFirstResponder(draft.input); return false
        }
        // Restore the untouched source before making the single undoable edit.
        updating = true
        view.textStorage?.replaceCharacters(in: draft.temporaryRange, with: draft.original)
        formulaDraft = nil; draft.removeFromSuperview(); view.isEditable = true; updating = false
        view.setSelectedRange(NSRange(location: NSMaxRange(draft.originalRange), length: 0))
        view.window?.makeFirstResponder(view)
        if deletingEmpty {
            let storage = view.textStorage!
            let originalStyle = draft.original.length > 0 ? draft.original.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
            var attributes = bodyAttributes(size: defaultSize, family: defaultFamily)
            if let originalStyle, !originalStyle.textBlocks.isEmpty { attributes[.paragraphStyle] = originalStyle }
            let paragraph = (view.string as NSString).paragraphRange(for: draft.originalRange)
            if draft.block && (originalStyle?.textBlocks.isEmpty ?? true) {
                let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paragraph))
                replacement.deleteCharacters(in: NSRange(location: draft.originalRange.location-paragraph.location, length: draft.originalRange.length))
                if replacement.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    replacement.addAttributes(attributes, range: NSRange(location: 0, length: replacement.length))
                    replace(paragraph, with: replacement, caret: draft.originalRange.location)
                } else { replace(draft.originalRange, with: NSAttributedString(string: "", attributes: attributes)) }
            } else { replace(draft.originalRange, with: NSAttributedString(string: "", attributes: attributes)) }
            view.typingAttributes = attributes
        } else if !cancel {
            do { try insertFormula(MathFormula(latex: draft.input.stringValue, block: draft.block), replacing: draft.originalRange, rendered: draft.rendered) }
            catch { NSSound.beep(); return false }
        }
        if cancel { didEdit?() }
        view.resizeContainer(); return true
    }
}

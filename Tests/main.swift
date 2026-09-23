import AppKit
import Foundation
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func check(_ value: @autoclosure () -> Bool, _ label: String) { if !value() { fatalError("FAIL: \(label)") }; print("PASS: \(label)") }
let old = [LineRecord(fingerprint: "a", modified: Date(timeIntervalSince1970: 1)), LineRecord(fingerprint: "b", modified: Date(timeIntervalSince1970: 2))]
let changed = reconcile(old, ["a", "x", "b"], now: Date(timeIntervalSince1970: 10))
check(changed[0] == old[0] && changed[2] == old[1] && changed[1].modified == Date(timeIntervalSince1970: 10), "insert keeps unchanged line timestamps")
check(reconcile(changed, ["a", "b"], now: Date()) == old, "deletion preserves other line timestamps")
let editor = EditorController()
let window = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 800,height: 700), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = editor.view
func type(_ s: String) { for c in s { editor.view.insertText(String(c), replacementRange: editor.view.selectedRange()); RunLoop.current.run(until: Date().addingTimeInterval(0.005)) } }
for level in 1...4 {
    editor.load(NSAttributedString(string: ""), lines: [])
    type(String(repeating: "#", count: level)+" ")
    type("标题")
    check(!editor.view.string.contains("#"), "H\(level) Markdown marker removed")
    let p = editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    check(p?.headerLevel == level, "H\(level) semantic paragraph style")
}
editor.load(NSAttributedString(string: ""), lines: [])
type("普通第一行\n")
check((editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 0, "first line is normal body")
type("**粗体**")
check(editor.view.string.contains("粗体") && !editor.view.string.contains("**"), "inline Markdown bold rendered")
editor.load(NSAttributedString(string: "English 正文\n", attributes: bodyAttributes()), lines: []);editor.view.setSelectedRange(NSRange(location: 0,length: 7)); editor.formatFont(family: "Menlo-Regular", size: 22)
let font = editor.view.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
print("FONT",font.fontName,font.pointSize,font.familyName ?? "nil");check(font.pointSize == 22 && font.familyName == "Menlo", "font and font size")
editor.view.setSelectedRange(NSRange(location: editor.view.string.utf16.count,length: 0)); editor.insertTable(rows: 3, columns: 3)
var cellCount=0
editor.view.textStorage!.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0,length: editor.view.string.utf16.count)) { value, _, _ in if let p=value as? NSParagraphStyle, !p.textBlocks.isEmpty { cellCount += 1 } }
check(cellCount == 9, "native editable 3x3 table")
let image=NSImage(size: NSSize(width: 400,height: 200));image.lockFocus();NSColor.systemOrange.setFill();NSRect(x:0,y:0,width:400,height:200).fill();image.unlockFocus()
editor.view.setSelectedRange(NSRange(location: editor.view.string.utf16.count,length: 0));editor.insertImage(image);editor.resizeImage(width: 240)
check(editor.selectedImage?.bounds.size == NSSize(width:240,height:120), "image insertion and aspect-ratio scaling")
let root=URL(fileURLWithPath: CommandLine.arguments[1]);let store=try NoteStore(root:root);let id=try store.create()
let doc=editor.view.attributedString();let lines=reconcile([],fingerprints(doc),now:Date())
try store.update(id:id,text:doc,lines:lines,date:Date())
let restored=try store.load(id)
check(restored.string == doc.string,"rich document persistence")
var restoredImage:NSTextAttachment?
restored.enumerateAttribute(.attachment,in:NSRange(location:0,length:restored.length)){ a,_,_ in if let a=a as? NSTextAttachment {restoredImage=a} }
check(restoredImage != nil,"embedded image restored")
let size=restoredImage?.attachmentCell?.cellSize() ?? .zero
check(abs(size.width-240)<2 && abs(size.height-120)<2,"resized image persists")
let again=try NoteStore(root:root);check(again.notes.first!.lines == lines,"timestamps persist across store restart")
editor.load(NSAttributedString(string: ""), lines: [])
check(editor.pasteMarkdown("## 粘贴标题\n普通 **粗体** 内容\n- 列表项"), "Markdown paste recognized")
check(editor.view.string == "粘贴标题\n普通 粗体 内容\n• 列表项", "Markdown paste rendered without markers")
check((editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "pasted heading level preserved")
editor.load(NSAttributedString(string: ""), lines: [])
type("**bold** normal")
let finalFont = editor.view.textStorage!.attribute(.font, at: editor.view.string.utf16.count-1, effectiveRange: nil) as! NSFont
check(!NSFontManager.shared.traits(of: finalFont).contains(.boldFontMask), "inline style does not leak into following text")


// Regression cases discovered by the independent editing review.
func fresh(_ text: String = "") { editor.load(NSAttributedString(string: text, attributes: bodyAttributes()), lines: []); editor.view.setSelectedRange(NSRange(location: text.utf16.count, length: 0)) }
func fast(_ text: String) { for c in text { editor.view.insertText(String(c), replacementRange: editor.view.selectedRange()) } }
fresh(); fast("# hello")
check(editor.view.string == "hello" && editor.view.selectedRange().location == 5, "fast Markdown keeps the caret after the typed text")
fresh("existing"); editor.view.setSelectedRange(NSRange(location: 0, length: 0)); fast("# ")
check((editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 1 && editor.view.string == "existing", "heading conversion preserves and styles existing text")
fresh(); fast("## "); editor.view.deleteBackward(nil); fast("plain")
check((editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 0, "backspace declines automatic heading into body text")
fresh(); fast("- "); editor.view.deleteBackward(nil); fast("plain")
check(editor.view.string == "plain", "backspace removes the whole empty bullet")
fresh("alpha"); editor.view.setSelectedRange(NSRange(location: 2, length: 0)); editor.formatFont(trait: .boldFontMask); editor.formatFont(trait: .boldFontMask); fast("X")
check(!NSFontManager.shared.traits(of: editor.view.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as! NSFont).contains(.boldFontMask), "typing bold can be enabled and disabled inside a word")
fresh(); editor.insertImage(image); editor.insertImage(image); fast("after")
var attachments = 0; editor.view.textStorage!.enumerateAttribute(.attachment, in: NSRange(location: 0, length: editor.view.string.utf16.count)) { a, _, _ in if a is NSTextAttachment { attachments += 1 } }
check(attachments == 2 && editor.view.string.hasSuffix("after"), "multiple images survive continued typing")
fresh(); fast("/h2"); check(!editor.commandPalette.isHidden, "slash filters block commands"); fast("\n"); fast("Title")
check(editor.view.string == "Title" && (editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "slash command inserts heading without leftover markers")
fresh(); editor.insertTable(rows: 2, columns: 2); editor.view.setSelectedRange(NSRange(location: 1, length: 0)); editor.applyParagraph(level: 1)
check((editor.view.textStorage!.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.count == 1, "formatting inside a table retains its cell")
editor.view.setSelectedRange(NSRange(location: 1, length: 0)); fast("first\nsecond "); editor.editTableRow(remove: false)
check(editor.view.string.contains("first\nsecond "), "adding a table row preserves multiline cell content")
fresh(); editor.view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); editor.view.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
check(editor.view.string == "你", "IME marked text commits without Markdown interference")
fresh(); fast("# Title"); editor.view.insertNewline(nil); fast("body")
check((editor.view.textStorage!.attribute(.paragraphStyle, at: editor.view.string.utf16.count-1, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 0, "native Return after heading starts body")
fresh(); fast("- item"); editor.view.insertNewline(nil)
check(editor.view.string == "• item\n• ", "native Return continues a list")


// Literal hashes and an explicit way to decline automatic headings.
fresh(); fast("##")
check(editor.view.string == "##", "hashes alone remain literal")
fast(" "); editor.view.deleteBackward(nil); fast("literal")
check(editor.view.string == "## literal", "immediate backspace restores hashes and triggering space")
fresh(); fast("\\## literal")
check(editor.view.string == "## literal" && (editor.view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 0, "escaped heading prefix stays plain text")
fresh("existing"); editor.view.setSelectedRange(NSRange(location: 0, length: 0)); fast("## "); editor.view.deleteBackward(nil)
check(editor.view.string == "## existing" && editor.view.selectedRange().location == 3, "declining heading preserves suffix and caret")
fresh(); fast("## "); fast("Title"); editor.view.setSelectedRange(NSRange(location: 0, length: 0)); editor.view.deleteBackward(nil)
check(editor.view.string == "Title", "later backspace cannot restore stale heading marker")
fresh(); fast("##### text")
check(editor.view.string == "##### text", "unsupported heading level stays literal")

try MainActor.assumeIsolated {
    let formula = MathFormula(latex: "\\frac{a}{b} + x^2", block: false)
    let attachment = try formula.attachment()
    check(MathFormula.read(attachment) == formula, "formula attachment retains LaTeX source")
    let archived = try NSKeyedArchiver.archivedData(withRootObject: attachment.attachmentCell!, requiringSecureCoding: false)
    let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(archived) as? FormulaAttachmentCell
    check(decoded != nil && decoded?.cellSize() == attachment.attachmentCell?.cellSize(), "formula cell supports AppKit archiving")
    let rich = NSAttributedString(attachment: attachment)
    let data = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    let reopened = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
    check(MathFormula.read(reopened.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment) == formula, "RTFD formula source survives reopening")
    fresh("before after"); try editor.insertFormula(formula, replacing: NSRange(location: 7, length: 0))
    check(editor.view.string == "before \u{fffc}after", "inline formula keeps adjacent text")
    fresh("before after"); try editor.insertFormula(MathFormula(latex: "x^2", block: true), replacing: NSRange(location: 7, length: 0))
    check(editor.view.string == "before \n\u{fffc}\nafter", "block formula has paragraph boundaries")
    var rejected = false
    do { _ = try MathFormula(latex: "\\notAValidCommand", block: false).attachment() } catch { rejected = true }
    check(rejected, "invalid LaTeX is rejected before changing document")
}
var requestedFormula: (Bool, NSRange)?
editor.requestFormula = { requestedFormula = ($0, $1) }
fresh(); fast("/math-inline"); fast("\n")
check(requestedFormula?.0 == false && editor.view.string == "/math-inline", "formula command keeps source until confirmed")

try MainActor.assumeIsolated {
    fresh("prefix suffix")
    window.makeFirstResponder(editor.view)
    let undo = editor.view.undoManager!
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    try editor.insertFormula(MathFormula(latex: "x^2", block: true), replacing: NSRange(location: 7, length: 0))
    undo.endUndoGrouping()
    let withFormula = editor.view.string
    undo.undo()
    check(editor.view.string == "prefix suffix", "formula insertion undoes as one edit")
    undo.redo()
    check(editor.view.string == withFormula, "formula insertion can be redone")
    undo.groupsByEvent = true
    fresh()
    let long = MathFormula(latex: String(repeating: "x_1+x_2+", count: 12) + "x_n", block: true)
    try editor.insertFormula(long, replacing: NSRange(location: 0, length: 0))
    let beforeResize = fingerprints(editor.view.attributedString())
    editor.view.setFrameSize(NSSize(width: 350, height: 700))
    let attachment = editor.view.textStorage!.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment
    check(attachment.attachmentCell!.cellSize().width <= 294, "long formula fits narrow editor")
    check(beforeResize == fingerprints(editor.view.attributedString()), "resizing formula does not change line identity")
    fresh(); editor.insertTable(rows: 2, columns: 2)
    try editor.insertFormula(MathFormula(latex: "a/b", block: false), replacing: NSRange(location: 1, length: 0))
    check(!(editor.view.textStorage!.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as! NSParagraphStyle).textBlocks.isEmpty, "inline formula preserves its table cell")
    editor.beginFormulaEditing(block: false, range: NSRange(location: 1, length: 1))
    editor.formulaDraft?.input.stringValue = ""
    check(editor.finishFormulaEditing(cancel: false), "empty inline formula can be deleted in a table")
    check(!(editor.view.typingAttributes[.paragraphStyle] as! NSParagraphStyle).textBlocks.isEmpty, "deleting empty formula preserves table typing attributes")
    check(!(editor.view.textStorage!.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as! NSParagraphStyle).textBlocks.isEmpty, "deleting empty formula preserves table cell")
    fresh("before /math-inline after")
    editor.beginFormulaEditing(block: false, range: NSRange(location: 7, length: 12))
    check(editor.formulaDraft != nil && !editor.view.isEditable, "formula source expands in the document")
    editor.formulaDraft?.input.stringValue = "\\frac{1}{2}"; editor.formulaDraft?.refresh()
    check(editor.finishFormulaEditing(cancel: false), "valid inline source commits")
    check(editor.view.string == "before \u{fffc} after", "in-place commit preserves surrounding text")
    fresh("before /math-inline after")
    editor.beginFormulaEditing(block: false, range: NSRange(location: 7, length: 12))
    editor.formulaDraft?.input.stringValue = "\\invalidcommand"; editor.formulaDraft?.refresh()
    check(!editor.finishFormulaEditing(cancel: false), "invalid draft remains editable")
    check(editor.finishFormulaEditing(cancel: true) && editor.view.string == "before /math-inline after", "escape restores original source exactly")
}
try MainActor.assumeIsolated {
    fresh("M M M M M M M M M M M M ")
    editor.view.setFrameSize(NSSize(width: 300, height: 700))
    try editor.insertFormula(MathFormula(latex: "x^2+y^2=r^2", block: false), replacing: NSRange(location: 24, length: 0))
    let layout = editor.view.layoutManager!, container = editor.view.textContainer!
    layout.ensureLayout(for: container)
    let before = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 22), effectiveRange: nil)
    let formulaLine = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 24), effectiveRange: nil)
    check(formulaLine.minY >= before.maxY-1, "inline formula wraps when the remaining line cannot fit it")
    fresh("before\n/math-block\nafter")
    editor.beginFormulaEditing(block: true, range: NSRange(location: 7, length: 11))
    editor.formulaDraft?.input.stringValue = "\\frac{a}{b}"; editor.formulaDraft?.refresh()
    let draft = editor.formulaDraft!
    layout.ensureLayout(for: container)
    let following = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: 9, length: 5), actualCharacterRange: nil), in: container).offsetBy(dx: editor.view.textContainerOrigin.x, dy: editor.view.textContainerOrigin.y)
    check(following.minY >= draft.frame.maxY-1, "in-place block editor never covers the following paragraph")
    check(draft.sourceEditor.undoManager !== editor.view.undoManager, "formula source has an independent undo history")
    _ = editor.finishFormulaEditing(cancel: true)
}
try MainActor.assumeIsolated {
    fresh()
    try editor.insertFormula(MathFormula(latex: "x^2", block: true), replacing: NSRange(location: 0, length: 0))
    editor.view.insertNewline(nil); fast("left aligned")
    let bodyStyle = editor.view.textStorage!.attribute(.paragraphStyle, at: editor.view.string.utf16.count-1, effectiveRange: nil) as! NSParagraphStyle
    check(bodyStyle.alignment != .center, "Return after block formula starts left aligned body")
    fresh("/math-block")
    editor.beginFormulaEditing(block: true, range: NSRange(location: 0, length: 11))
    let draft = editor.formulaDraft!
    _ = draft.control(draft.input, textView: draft.sourceEditor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
    check(editor.formulaDraft == nil && editor.view.string.isEmpty && editor.view.isEditable, "Backspace deletes an empty formula block")
    fresh("before\n/math-block\nafter")
    editor.beginFormulaEditing(block: true, range: NSRange(location: 7, length: 11))
    check(editor.finishFormulaEditing(cancel: false) && editor.view.string == "before\n\nafter", "leaving an empty formula removes it without blocking navigation")
}
do {
    let suite = "SwiftNote.LanguageTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    let original = Localization.preferences
    Localization.preferences = defaults
    defer { Localization.preferences = original; defaults.removePersistentDomain(forName: suite) }
    check(Localization.language == .english, "interface defaults to English")
    let english = editor.allCommands
    check(english[11].0 == "Inline Math" && english[12].0 == "Block Math", "slash commands default to English")
    let content = editor.view.attributedString()
    Localization.language = .chinese
    check(editor.allCommands[11].0 == "行内公式" && L("设置") == "设置", "language change updates command names immediately")
    check(editor.allCommands.map { $0.1 } == english.map { $0.1 } && editor.allCommands.map { $0.2 } == english.map { $0.2 }, "language preserves command aliases and actions")
    check(editor.view.attributedString().isEqual(to: content), "switching language preserves memo content")
    check(UserDefaults(suiteName: suite)?.string(forKey: "interfaceLanguage") == "zh-Hans", "language preference persists")
    Localization.language = .english
    check(L("设置") == "Settings", "switching back restores English")
}
MainActor.assumeIsolated {
    let draft = FormulaEditor(formula: MathFormula(latex: "", block: false), range: NSRange(location: 0, length: 0), original: NSAttributedString(string: ""), fontSize: 16)
    for width in [CGFloat(100), 140, 240, 400] {
        draft.availableWidth = width; draft.refresh()
        check(draft.frame.width <= width, "formula hints stay within available width")
        let measured = draft.message.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: draft.message.frame.width, height: 10000))
        check(draft.message.frame.height >= ceil(measured.height) && draft.message.frame.maxY <= draft.bounds.maxY, "formula hint reserves full wrapped height")
        check(draft.input.placeholderString == "LaTeX", "compact formula placeholder remains readable")
    }
}
try MainActor.assumeIsolated {
    for size in [CGFloat(12), 24] {
        var attrs = bodyAttributes(size: size)
        attrs[.font] = NSFont.boldSystemFont(ofSize: size)
        editor.load(NSAttributedString(string: "你好 /math-inline", attributes: attrs), lines: [])
        editor.beginFormulaEditing(block: false, range: NSRange(location: 3, length: 12))
        check(editor.formulaDraft?.fontSize == size, "formula draft inherits surrounding font size")
        editor.formulaDraft?.input.stringValue = "f(x)+1"
        check(editor.finishFormulaEditing(cancel: false), "styled inline formula commits")
        editor.view.insertText(" 今天", replacementRange: editor.view.selectedRange())
        let storage = editor.view.textStorage!
        let before = storage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let after = storage.attribute(.font, at: storage.length-1, effectiveRange: nil) as! NSFont
        check(before.pointSize == after.pointSize && NSFontManager.shared.traits(of: before).contains(.boldFontMask) == NSFontManager.shared.traits(of: after).contains(.boldFontMask), "formula preserves font size and weight on both sides")
        let attachment = storage.attribute(.attachment, at: 3, effectiveRange: nil) as! NSTextAttachment
        let cell = attachment.attachmentCell!
        let center = cell.cellSize().height/2 + cell.cellBaselineOffset().y
        let formulaFont = storage.attribute(.font, at: 3, effectiveRange: nil) as! NSFont
        check(center.isFinite && formulaFont.pointSize == size, "formula retains its contextual text size")
    }
}
fresh("hello /")
editor.view.setSelectedRange(NSRange(location: 7, length: 0)); editor.updateCommandPalette()
check(!editor.commandPalette.isHidden && editor.commandItems.count == editor.allCommands.count, "slash opens all commands after existing text")
fresh("你好/math")
editor.view.setSelectedRange(NSRange(location: 7, length: 0)); editor.updateCommandPalette()
check(editor.commandItems.map { $0.2 } == [11, 12], "slash filters math commands in the middle of a line")
fresh("https://example.com/")
editor.view.setSelectedRange(NSRange(location: editor.view.string.utf16.count, length: 0)); editor.updateCommandPalette()
check(editor.commandPalette.isHidden, "URL slashes do not open command menu")
editor.defaultSize = 18; fresh()
check((editor.view.typingAttributes[.font] as! NSFont).pointSize == 18, "blank memo keeps readable default size after selection")
type("正文"); editor.view.insertNewline(nil); type("下一行")
check((editor.view.textStorage!.attribute(.font, at: editor.view.string.utf16.count-1, effectiveRange: nil) as! NSFont).pointSize == 18, "next line keeps body size")
try MainActor.assumeIsolated {
    for size in [CGFloat(14), 18, 24] {
        for family in ["Helvetica", "Georgia"] {
            for latex in ["f(x)+1", "\\frac{a+b}{c}", "x_i^2+y_j^2"] {
                let attrs = bodyAttributes(size: size, family: family)
                editor.load(NSAttributedString(string: "Text 今天 /math-inline", attributes: attrs), lines: [])
                let range = NSRange(location: 8, length: 12)
                editor.beginFormulaEditing(block: false, range: range)
                let draft = editor.formulaDraft!
                draft.input.stringValue = latex; draft.refresh()
                check(draft.valid, "font/formula matrix renders")
                let attachment = draft.rendered!
                let image = (attachment.attachmentCell as! NSTextAttachmentCell).image!.size
                let scale = min(1, draft.preview.frame.width/image.width, draft.preview.frame.height/image.height)
                let descent = -attachment.attachmentCell!.cellBaselineOffset().y * scale
                let baselineY = draft.preview.frame.midY+image.height*scale/2-descent
                check(abs(draft.bounds.height + draft.spacer.baseline-baselineY) < 0.1, "editing preview and committed formula share the baseline")
                check(editor.finishFormulaEditing(cancel: false), "font/formula matrix commits")
                editor.view.insertText(" 后文\nNext", replacementRange: editor.view.selectedRange())
                let font = editor.view.textStorage!.attribute(.font, at: editor.view.string.utf16.count-1, effectiveRange: nil) as! NSFont
                check(font.pointSize == size, "font/formula matrix preserves next-line size")
            }
        }
    }
    fresh("prefix /math")
    editor.view.setSelectedRange(NSRange(location: 12, length: 0)); editor.updateCommandPalette()
    editor.requestFormula = { block, range in MainActor.assumeIsolated { editor.beginFormulaEditing(block: block, range: range) } }
    editor.executeCommand()
    check(editor.formulaDraft != nil, "mid-line slash command opens formula editing")
    editor.formulaDraft?.input.stringValue = "x+1"
    check(editor.finishFormulaEditing(cancel: false) && editor.view.string.hasPrefix("prefix "), "mid-line command preserves preceding text")
    editor.requestFormula = nil
}
try MainActor.assumeIsolated {
    let legacy = try MathFormula(latex: "f(x)+1", block: false).attachment(fontSize: 12)
    let oldImage = (legacy.attachmentCell as! NSTextAttachmentCell).image!
    legacy.attachmentCell = FormulaAttachmentCell(image: oldImage, baselineRatio: 0)
    let saved = NSMutableAttributedString(attachment: legacy)
    saved.append(NSAttributedString(string: " = 2 什么？\n今天是个好日子", attributes: bodyAttributes(size: 18)))
    saved.addAttribute(.baselineOffset, value: 5, range: NSRange(location: 0, length: 1))
    let rtf = try saved.data(from: NSRange(location: 0, length: saved.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    let reopened = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
    let identity = fingerprints(reopened)
    let oldDate = Date(timeIntervalSince1970: 123)
    editor.load(reopened, lines: identity.map { LineRecord(fingerprint: $0, modified: oldDate) })
    let repaired = editor.view.attributedString()
    let attachment = repaired.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment
    check(attachment.attachmentCell!.cellBaselineOffset().y < 0, "reopened old formula gains the correct baseline")
    check(repaired.attribute(.baselineOffset, at: 0, effectiveRange: nil) == nil, "old text-level formula offset is removed")
    let expected = try MathFormula(latex: "f(x)+1", block: false).attachment(fontSize: 18)
    check(attachment.attachmentCell!.cellSize() == expected.attachmentCell!.cellSize(), "saved formula adopts adjacent body size")
    check(repaired.string == reopened.string && editor.view.records.allSatisfy { $0.modified == oldDate } && editor.view.records.map { $0.fingerprint } == fingerprints(repaired), "saved formula repair preserves content and modification times")
    editor.beginFormulaEditing(block: false, range: NSRange(location: 0, length: 1))
    check(editor.formulaDraft?.fontSize == 18, "editing a repaired saved formula keeps repaired size")
    _ = editor.finishFormulaEditing(cancel: true)
    let mixed = NSMutableAttributedString(string: "Large ", attributes: bodyAttributes(size: 30))
    mixed.append(NSAttributedString(string: "body ", attributes: bodyAttributes(size: 18)))
    let mixedIndex = mixed.length
    mixed.append(NSAttributedString(attachment: legacy))
    let displayed = MathFormula.refreshSavedFormulas(in: mixed)
    check((displayed.attribute(.font, at: mixedIndex, effectiveRange: nil) as! NSFont).pointSize == 18, "saved formula inherits nearest neighbor rather than paragraph heading size")
    check(reopened.attribute(.baselineOffset, at: 0, effectiveRange: nil) != nil, "display repair does not mutate source document")
}
print("ALL TESTS PASSED")

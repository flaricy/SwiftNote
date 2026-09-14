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

print("ALL TESTS PASSED")

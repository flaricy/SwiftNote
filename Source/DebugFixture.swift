#if DEBUG
import AppKit
extension AppController {
    func runVisualFixture() {
        guard ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] != nil,
              let path = ProcessInfo.processInfo.environment["LOCALNOTES_DATA_DIR"],
              let id = selectedID else { return }
        let mode = ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] ?? ""
        Localization.preferences = UserDefaults(suiteName: "SwiftNote.VisualFixture")!
        Localization.language = mode.hasSuffix("-zh") ? .chinese : .english
        applyLanguage()
        MainActor.assumeIsolated {
            editor.load(NSAttributedString(string: "随手记下，也能写公式\n\n今天的物理笔记： ", attributes: bodyAttributes()), lines: [])
            try? editor.insertFormula(MathFormula(latex: "\\frac{a+b}{c}=x^2", block: false), replacing: NSRange(location: editor.view.string.utf16.count, length: 0))
            let end = editor.view.string.utf16.count
            editor.view.setSelectedRange(NSRange(location: end, length: 0))
            editor.view.insertText("，接着记录推导。\n\n今天读到的高斯积分\n", replacementRange: editor.view.selectedRange())
            try? editor.insertFormula(MathFormula(latex: "\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx=\\sqrt{\\pi}", block: true), replacing: NSRange(location: editor.view.string.utf16.count, length: 0))
            edited(); _ = flush(); reloadList(); select(id)
            let narrow = mode.contains("narrow") || mode.hasPrefix("empty") || ["narrow", "inline"].contains(ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] ?? "")
            window.setContentSize(NSSize(width: narrow ? 740 : 1060, height: narrow ? 480 : 740)); window.center()
            if narrow { split.setPosition(205, ofDividerAt: 0) }
            try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: path + "/pid", atomically: true, encoding: .utf8)
            try? String(window.windowNumber).write(toFile: path + "/window-id", atomically: true, encoding: .utf8)
            if ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] == "inline" {
                let text = editor.view.textStorage!
                var first: NSRange?
                text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, stop in
                    if value is NSTextAttachment { first = range; stop.pointee = true }
                }
                if let first { editFormula(block: false, range: first) }
            }
            if mode.hasPrefix("matrix") {
                if mode.contains("dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
                editor.defaultSize = 18
                editor.load(NSAttributedString(string: "", attributes: bodyAttributes()), lines: [])
                func append(_ text: String) { editor.view.insertText(text, replacementRange: editor.view.selectedRange()) }
                for (label, latex) in [("正文与公式 Text 18pt： ", "f(x)+1"), ("分式 Fraction： ", "\\frac{a+b}{c}"), ("上下标： ", "x_i^2 + y_j^2"), ("长公式： ", "a+b+c+d+e+f+g+h+i+j=k")] {
                    append(label)
                    try? editor.insertFormula(MathFormula(latex: latex, block: false), replacing: editor.view.selectedRange())
                    append(" = 2 今天\n")
                }
                append("下一行保持正文大小。\n")
                try? editor.insertFormula(MathFormula(latex: "\\frac{f(x)}{g(x)}", block: true), replacing: editor.view.selectedRange())
                append("独立公式之后继续写。\n")
                if mode.contains("slash") { append("已有文字 /"); editor.updateCommandPalette() }
                window.setContentSize(NSSize(width: narrow ? 740 : 1060, height: 740))
                editor.view.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
            if mode == "saved-formula" {
                let old = try! MathFormula(latex: "f(x)+1", block: false).attachment(fontSize: 12)
                let image = (old.attachmentCell as! NSTextAttachmentCell).image!
                old.attachmentCell = FormulaAttachmentCell(image: image, baselineRatio: 0)
                let note = NSMutableAttributedString(string: "是的\n\n", attributes: bodyAttributes(size: 18))
                let index = note.length
                note.append(NSAttributedString(attachment: old))
                note.addAttribute(.baselineOffset, value: 5, range: NSRange(location: index, length: 1))
                note.append(NSAttributedString(string: " = 2 什么？\n\n今天真是个好日子\n", attributes: bodyAttributes(size: 18)))
                let data = try! note.data(from: NSRange(location: 0, length: note.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
                let reopened = try! NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
                editor.load(reopened, lines: [])
            }
            if mode == "alignment" {
                editor.load(NSAttributedString(string: "你好 /math-inline", attributes: bodyAttributes(size: 12)), lines: [])
                editFormula(block: false, range: NSRange(location: 3, length: 12))
                editor.formulaDraft?.input.stringValue = "f(x)+1"
                _ = editor.finishFormulaEditing(cancel: false)
                editor.view.insertText(" 今天", replacementRange: editor.view.selectedRange())
            }
            if mode.hasPrefix("empty") {
                if mode.contains("dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
                editor.load(NSAttributedString(string: "/math-inline", attributes: bodyAttributes()), lines: [])
                editFormula(block: false, range: NSRange(location: 0, length: 12))
            }
            if mode.hasPrefix("settings") {
                showSettings()
                // Exercise the same action as a user's language selection, without touching real preferences.
                languagePopup?.selectItem(at: mode.hasSuffix("-zh") ? 1 : 0)
                changeLanguage(languagePopup!)
                try? String(settingsWindow!.windowNumber).write(toFile: path + "/window-id", atomically: true, encoding: .utf8)
            }
            if mode.hasPrefix("slash") {
                editor.load(NSAttributedString(string: "/math", attributes: bodyAttributes()), lines: [])
                editor.view.setSelectedRange(NSRange(location: 5, length: 0))
                editor.updateCommandPalette()
            }
            if ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] == "formula" {
                editFormula(block: true, range: NSRange(location: editor.view.string.utf16.count, length: 0))
                editor.formulaDraft?.input.stringValue = "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}=\\frac{\\pi^2}{6}"
                editor.formulaDraft?.refresh()
            }
        }
    }
}
#endif
